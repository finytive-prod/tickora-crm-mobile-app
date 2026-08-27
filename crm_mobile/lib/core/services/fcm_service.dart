import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:logger/logger.dart';

/// Top-level background message handler.
/// Must be a top-level function (not a class method) for Firebase Messaging.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized in main.dart before this is registered.
  // Background messages are automatically shown by the system tray.
  // Add any custom background processing here if needed.
}

/// Singleton service that manages Firebase Cloud Messaging (FCM).
///
/// Responsibilities:
/// - Request notification permissions (Android 13+ / iOS)
/// - Obtain and refresh FCM device tokens
/// - Send device tokens to the backend API
/// - Display foreground notifications via flutter_local_notifications
/// - Handle notification tap actions
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// The Android notification channel used for foreground notifications.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'tickora_crm_notifications', // Must match AndroidManifest meta-data value
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

  /// Sends the FCM device token to the backend for push notification targeting.
  Future<void> _sendTokenToBackend(String token) async {
    final logger = sl<Logger>();
    logger.i('FCM Token: $token');

    try {
      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      final candidateUrls = <String>[];

      if (baseUrl.contains('/api/crm/lead-service')) {
        candidateUrls.add(baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/users/device-token'));
        candidateUrls.add(baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/auth/device-token'));
        candidateUrls.add(baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/device-token'));
        candidateUrls.add('$baseUrl/device-token');
      } else {
        candidateUrls.add('$baseUrl/device-token');
      }

      final apiClient = sl<ApiClient>();
      bool success = false;

      for (final url in candidateUrls) {
        try {
          final res = await apiClient.post(
            url,
            data: {
              'token': token,
              'fcmToken': token,
              'deviceToken': token,
              'platform': 'android',
            },
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            logger.i('FCM token sent to backend successfully via $url');
            success = true;
            break;
          }
        } catch (_) {
          // Try next candidate URL silently
        }
      }

      if (!success) {
        logger.w('Device token endpoint not active on backend. FCM initialized locally.');
      }
    } catch (e) {
      logger.w('FCM token registration warning: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Local notifications setup (for foreground display)
  // ---------------------------------------------------------------------------

  Future<void> _setupLocalNotifications() async {
    // Create the Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Initialize with Android settings
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
      final android = message.notification?.android;

      // Show a local notification only when the app is in the foreground
      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
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
    // When the app is in background and the user taps the notification
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // When the app was terminated and launched via a notification tap
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        _onMessageOpenedApp(message);
      }
    });
  }

  /// Called when a user taps on a notification (background/terminated).
  void _onMessageOpenedApp(RemoteMessage message) {
    final logger = sl<Logger>();
    logger.i('Notification tapped — data: ${message.data}');

    // TODO: Implement deep-link navigation based on message.data
    // Example:
    // final type = message.data['type'];    // e.g. 'lead', 'followup'
    // final id = message.data['id'];        // e.g. '12345'
    // Navigate to the appropriate screen using a GlobalKey<NavigatorState>
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
