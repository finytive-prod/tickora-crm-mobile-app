import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  bool isRead;
  final Map<String, dynamic>? data;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'data': data,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? 'Notification',
        body: json['body'] as String? ?? '',
        type: json['type'] as String? ?? 'SYSTEM_ALERT',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        isRead: json['isRead'] as bool? ?? false,
        data: json['data'] as Map<String, dynamic>?,
      );
}

class NotificationService extends ValueNotifier<List<AppNotification>> {
  NotificationService._() : super([]) {
    _loadNotifications();
  }

  static final NotificationService instance = NotificationService._();
  static const String _storageKey = 'tickora_notifications_cache_v1';

  int get unreadCount => value.where((n) => !n.isRead).length;

  Future<SharedPreferences?> _getPrefs() async {
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        return sl<SharedPreferences>();
      }
      return await SharedPreferences.getInstance();
    } catch (_) {
      try {
        return await SharedPreferences.getInstance();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;
      final rawJson = prefs.getString(_storageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(rawJson);
        value = decoded.map((item) => AppNotification.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
  }

  Future<void> _saveNotifications() async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;
      final encoded = jsonEncode(value.map((n) => n.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  void addNotification({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? data,
  }) {
    addNotificationAsync(title: title, body: body, type: type, data: data);
  }

  Future<void> addNotificationAsync({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? data,
  }) async {
    final notificationId = data?['notificationId']?.toString() ??
        data?['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // Avoid duplicate adding by notificationId
    final existingIndex = value.indexWhere((n) => n.id == notificationId);
    if (existingIndex != -1) return;

    final newNotification = AppNotification(
      id: notificationId,
      title: title,
      body: body,
      type: type ?? data?['type']?.toString() ?? 'SYSTEM_ALERT',
      timestamp: DateTime.now(),
      isRead: false,
      data: data,
    );

    value = [newNotification, ...value];
    await _saveNotifications();
  }

  void markAsRead(String id) {
    bool updated = false;
    final newList = value.map((n) {
      if (n.id == id && !n.isRead) {
        updated = true;
        return AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          type: n.type,
          timestamp: n.timestamp,
          isRead: true,
          data: n.data,
        );
      }
      return n;
    }).toList();

    if (updated) {
      value = newList;
      _saveNotifications();
    }
  }

  void markAllAsRead() {
    value = value
        .map((n) => AppNotification(
              id: n.id,
              title: n.title,
              body: n.body,
              type: n.type,
              timestamp: n.timestamp,
              isRead: true,
              data: n.data,
            ))
        .toList();
    _saveNotifications();
  }

  void clearAll() {
    value = [];
    _saveNotifications();
  }
}
