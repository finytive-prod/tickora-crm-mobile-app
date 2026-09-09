import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/services/notification_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:logger/logger.dart';

/// Top-level background message handler.
/// Must be a top-level function (not a class method) for Firebase Messaging.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final title = message.notification?.title ?? message.data['title']?.toString() ?? 'New Notification';
  final body = message.notification?.body ?? message.data['body']?.toString() ?? '';
  NotificationService.instance.addNotification(
    title: title,
    body: body,
    data: message.data,
  );
}

/// Singleton service that manages Firebase Cloud Messaging (FCM).
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// The Android notification channel used for foreground notifications.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'tickora_crm_notifications',
    'Tickora CRM Notifications',
    description: 'Notifications from Tickora CRM',
    importance: Importance.high,
    showBadge: true,
  );

  /// Initialize the FCM service. Call this after the user is authenticated.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _setupLocalNotifications();
    await _requestPermission();
    await _getTokenAndRegister();
    _listenForTokenRefresh();
    _listenForForegroundMessages();
    _handleNotificationTaps();

    _isInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Permission
  // ---------------------------------------------------------------------------

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final logger = sl<Logger>();
    logger.i('FCM permission status: ${settings.authorizationStatus}');
  }

  // ---------------------------------------------------------------------------
  // Token management
  // ---------------------------------------------------------------------------

  Future<void> _getTokenAndRegister() async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _sendTokenToBackend(token);
    }
  }

  void _listenForTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) {
      _sendTokenToBackend(newToken);
    });
  }

  /// Sends the FCM device token to the backend API: POST /api/crm/notification-service/fcm/register
  Future<void> _sendTokenToBackend(String token) async {
    final logger = sl<Logger>();
    logger.i('FCM Token generated: $token');

    try {
      final candidateUrls = <String>[
        '${ApiUrl.notificationService}/fcm/register',
        '${ApiUrl.identityService}/users/device-token',
        '${ApiUrl.identityService}/auth/device-token',
      ];

      final apiClient = sl<ApiClient>();
      bool success = false;

      for (final url in candidateUrls) {
        try {
          final res = await apiClient.post(
            url,
            data: {
              'token': token,
              'deviceType': 'android',
            },
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            logger.i('FCM token registered successfully via $url');
            success = true;
            break;
          }
        } catch (err) {
          logger.d('Endpoint candidate $url failed: $err');
        }
      }

      if (!success) {
        logger.w('Device token endpoint pending backend active status. FCM initialized locally.');
      }
    } catch (e) {
      logger.w('FCM token registration warning: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Local notifications setup (for foreground display)
  // ---------------------------------------------------------------------------

  Future<void> _setupLocalNotifications() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  // ---------------------------------------------------------------------------
  // Foreground message handling
  // ---------------------------------------------------------------------------

  void _listenForForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final title = notification?.title ?? message.data['title']?.toString() ?? 'New Notification';
      final body = notification?.body ?? message.data['body']?.toString() ?? '';

      NotificationService.instance.addNotification(
        title: title,
        body: body,
        data: message.data,
      );

      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/launcher_icon',
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Notification tap handling
  // ---------------------------------------------------------------------------

  void _handleNotificationTaps() {
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        _onMessageOpenedApp(message);
      }
    });
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Notification';
    final body = message.notification?.body ?? message.data['body']?.toString() ?? '';

    NotificationService.instance.addNotification(
      title: title,
      body: body,
      data: message.data,
    );
  }

  /// Called when a user taps on a foreground local notification.
  void _onNotificationTapped(NotificationResponse response) {
    final logger = sl<Logger>();
    logger.i('Local notification tapped — payload: ${response.payload}');

    // TODO: Parse the payload JSON and navigate to the appropriate screen
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Deletes the FCM token. Call this on logout to stop receiving
  /// notifications for the logged-out user.
  Future<void> deleteToken() async {
    await _messaging.deleteToken();
    _isInitialized = false;
    final logger = sl<Logger>();
    logger.i('FCM token deleted (user logged out)');
  }
}
