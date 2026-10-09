import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/services/notification_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:logger/logger.dart';

/// Top-level background message handler.
/// Must be a top-level function (not a class method) for Firebase Messaging.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ??
        data['title']?.toString() ??
        data['name']?.toString() ??
        data['subject']?.toString() ??
        data['header']?.toString() ??
        'New Notification';

    final body = notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        data['content']?.toString() ??
        data['description']?.toString() ??
        data['text']?.toString() ??
        '';

    if (title.isNotEmpty || body.isNotEmpty) {
      await NotificationService.instance.addNotificationAsync(
        title: title,
        body: body,
        data: data,
        speakTitle: true,
      );
    }
  } catch (e) {
    debugPrint('Error handling background FCM message: $e');
  }
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
    importance: Importance.max,
    showBadge: true,
    playSound: true,
  );

  /// Initialize the FCM service. Call this on app startup or user authentication.
  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _requestPermission();
    await _getTokenAndRegister();
    
    if (!_isInitialized) {
      _listenForTokenRefresh();
      _listenForForegroundMessages();
      _handleNotificationTaps();
      _isInitialized = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Permission
  // ---------------------------------------------------------------------------

  Future<void> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Explicitly set foreground notification presentation options
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (sl.isRegistered<Logger>()) {
        sl<Logger>().i('FCM permission status: ${settings.authorizationStatus}');
      }
    } catch (e) {
      debugPrint('Error requesting FCM permissions: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Token management
  // ---------------------------------------------------------------------------

  Future<void> _getTokenAndRegister() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('Error fetching FCM token: $e');
    }
  }

  void _listenForTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) {
      _sendTokenToBackend(newToken);
    });
  }

  /// Sends the FCM device token to backend endpoints.
  Future<void> _sendTokenToBackend(String token) async {
    final logger = sl.isRegistered<Logger>() ? sl<Logger>() : null;
    logger?.i('FCM Token generated: $token');

    try {
      final candidateUrls = <String>[
        '${ApiUrl.notificationService}/fcm/register',
        '${ApiUrl.notificationService}/fcm/token',
        '${ApiUrl.notificationService}/fcm/device-token',
        '${ApiUrl.notificationService}/device-token',
        '${ApiUrl.notificationService}/register',
        '${ApiUrl.identityService}/users/device-token',
        '${ApiUrl.identityService}/users/fcm-token',
        '${ApiUrl.identityService}/auth/device-token',
        '${ApiUrl.leadService}/device-token',
      ];

      if (!sl.isRegistered<ApiClient>()) return;
      final apiClient = sl<ApiClient>();
      bool success = false;

      final payload = {
        'token': token,
        'fcmToken': token,
        'deviceToken': token,
        'deviceType': 'android',
        'platform': 'ANDROID',
      };

      for (final url in candidateUrls) {
        try {
          final res = await apiClient.post(
            url,
            data: payload,
          );
          if (res.statusCode == 200 || res.statusCode == 201 || (res.data != null && res.data['success'] == true)) {
            logger?.i('FCM token registered successfully via $url');
            success = true;
            break;
          }
        } catch (err) {
          logger?.d('Endpoint candidate $url failed: $err');
        }
      }

      if (!success) {
        logger?.w('Device token endpoint candidates completed. Token stored locally.');
      }
    } catch (e) {
      logger?.w('FCM token registration warning: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Local notifications setup (for foreground display)
  // ---------------------------------------------------------------------------

  Future<void> _setupLocalNotifications() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_channel);

    // Request Android 13+ runtime notification permissions
    await androidPlugin?.requestNotificationsPermission();

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
      final data = message.data;

      final title = notification?.title ??
          data['title']?.toString() ??
          data['name']?.toString() ??
          data['subject']?.toString() ??
          data['header']?.toString() ??
          'New Notification';

      final body = notification?.body ??
          data['body']?.toString() ??
          data['message']?.toString() ??
          data['content']?.toString() ??
          data['description']?.toString() ??
          data['text']?.toString() ??
          '';

      if (title.isNotEmpty || body.isNotEmpty) {
        NotificationService.instance.addNotification(
          title: title,
          body: body,
          data: data,
          speakTitle: true,
        );

        final notificationId = message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(100000);

        _localNotifications.show(
          notificationId,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/launcher_icon',
              styleInformation: BigTextStyleInformation(body),
              playSound: true,
              enableVibration: true,
            ),
          ),
          payload: jsonEncode(data),
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
    final notification = message.notification;
    final data = message.data;

    final title = notification?.title ??
        data['title']?.toString() ??
        data['name']?.toString() ??
        data['subject']?.toString() ??
        'Notification';

    final body = notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        data['content']?.toString() ??
        '';

    if (title.isNotEmpty || body.isNotEmpty) {
      NotificationService.instance.addNotification(
        title: title,
        body: body,
        data: data,
      );
    }
  }

  /// Called when a user taps on a foreground local notification banner.
  void _onNotificationTapped(NotificationResponse response) {
    final logger = sl.isRegistered<Logger>() ? sl<Logger>() : null;
    logger?.i('Local notification tapped — payload: ${response.payload}');

    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        final title = data['title']?.toString() ?? 'Notification';
        final body = data['body']?.toString() ?? data['message']?.toString() ?? '';
        NotificationService.instance.addNotification(
          title: title,
          body: body,
          data: data,
        );
      } catch (e) {
        logger?.w('Error parsing notification payload: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Returns the current FCM device token if available.
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Deletes the FCM token. Call this on logout to stop receiving
  /// notifications for the logged-out user.
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } catch (_) {}
    _isInitialized = false;
    final logger = sl.isRegistered<Logger>() ? sl<Logger>() : null;
    logger?.i('FCM token deleted (user logged out)');
  }
}
