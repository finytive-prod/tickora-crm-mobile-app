import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

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

  final FlutterTts _tts = FlutterTts();
  bool _ttsInitialized = false;
  DateTime? _lastSelfLeadCreatedAt;
  String? _cachedUserId;

  bool get isRecentSelfLeadCreated =>
      _lastSelfLeadCreatedAt != null &&
      DateTime.now().difference(_lastSelfLeadCreatedAt!).inMinutes < 3;

  void recordSelfLeadCreated() {
    _lastSelfLeadCreatedAt = DateTime.now();
  }

  static bool isSelfAddLeadNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    final lowerTitle = title.toLowerCase();
    final lowerBody = body.toLowerCase();
    final type = data?['type']?.toString().toLowerCase() ?? '';
    final action = data?['action']?.toString().toLowerCase() ?? '';
    final fullText = '$lowerTitle $lowerBody $type $action';

    // Admin assignments, reminders, followups, calls, tasks MUST play sound
    if (fullText.contains('assign') ||
        fullText.contains('reminder') ||
        fullText.contains('followup') ||
        fullText.contains('follow-up') ||
        fullText.contains('call') ||
        fullText.contains('task')) {
      return false;
    }

    // Explicit self-lead creation keywords
    final hasSelfKeyword = fullText.contains('self') && fullText.contains('lead');
    final hasLeadCreatedKeyword = fullText.contains('lead created') ||
        fullText.contains('lead added') ||
        fullText.contains('created lead') ||
        fullText.contains('create lead') ||
        fullText.contains('new lead created') ||
        fullText.contains('new lead added') ||
        fullText.contains('lead registration') ||
        fullText.contains('lead_created') ||
        fullText.contains('lead_create') ||
        fullText.contains('lead_add') ||
        fullText.contains('self_lead') ||
        fullText.contains('self_add');

    if (hasSelfKeyword || hasLeadCreatedKeyword) {
      return true;
    }

    // Lead created recently in this app (within 3 minutes)
    if (instance.isRecentSelfLeadCreated && fullText.contains('lead')) {
      return true;
    }

    // Created by the currently logged-in user
    if (instance._cachedUserId != null && instance._cachedUserId!.isNotEmpty) {
      final createdBy = data?['createdBy']?.toString() ?? data?['creatorId']?.toString();
      if (createdBy != null && createdBy == instance._cachedUserId && fullText.contains('lead')) {
        return true;
      }
    }

    return false;
  }

  static String? extractLeadId(Map<String, dynamic>? data, {String? title, String? body}) {
    if (data != null && data.isNotEmpty) {
      // 1. Direct keys
      for (final key in [
        'leadId',
        'lead_id',
        'leadID',
        'leadIdToUpload',
        'leadUuid',
        'lead_uuid',
      ]) {
        final val = data[key]?.toString().trim();
        if (val != null && val.isNotEmpty && val != 'null') {
          return val;
        }
      }

      // 2. Nested objects
      if (data['lead'] != null) {
        if (data['lead'] is Map) {
          final m = data['lead'] as Map;
          final val = (m['id'] ?? m['leadId'] ?? m['lead_id'])?.toString().trim();
          if (val != null && val.isNotEmpty && val != 'null') return val;
        } else if (data['lead'] is String) {
          final val = data['lead'].toString().trim();
          if (val.isNotEmpty && val != 'null') return val;
        }
      }

      // 3. Nested data / payload object
      if (data['data'] != null && data['data'] is Map) {
        final d = data['data'] as Map;
        final val = (d['leadId'] ?? d['lead_id'] ?? d['leadID'])?.toString().trim();
        if (val != null && val.isNotEmpty && val != 'null') return val;
      }

      if (data['payload'] != null && data['payload'] is String) {
        try {
          final decoded = jsonDecode(data['payload']);
          if (decoded is Map<String, dynamic>) {
            final res = extractLeadId(decoded);
            if (res != null) return res;
          }
        } catch (_) {}
      }

      // 4. Explicit entityId when entityType indicates LEAD
      final entityType = (data['entityType'] ?? data['entity_type'])?.toString().toUpperCase() ?? '';
      final type = data['type']?.toString().toUpperCase() ?? '';
      if (entityType == 'LEAD' ||
          (entityType.isEmpty && (type == 'LEAD' || type == 'LEAD_CREATED' || type == 'LEAD_ASSIGNED' || type == 'NEW_LEAD'))) {
        for (final key in ['entityId', 'entity_id']) {
          final val = data[key]?.toString().trim();
          if (val != null && val.isNotEmpty && val != 'null') {
            return val;
          }
        }
      }
    }

    return null;
  }

  static Future<String?> resolveLeadId(
    Map<String, dynamic>? data, {
    String? title,
    String? body,
  }) async {
    // 1. Direct extraction
    final directId = extractLeadId(data, title: title, body: body);
    if (directId != null && directId.isNotEmpty) {
      return directId;
    }

    // 2. Try candidate IDs (e.g. followupId, entityId) against backend endpoints
    final candidateIds = <String>[];
    if (data != null) {
      for (final k in ['followupId', 'followUpId', 'follow_up_id', 'entityId', 'entity_id', 'id']) {
        final val = data[k]?.toString().trim();
        if (val != null && val.isNotEmpty && val != 'null' && !candidateIds.contains(val)) {
          candidateIds.add(val);
        }
      }
    }

    if (candidateIds.isNotEmpty && sl.isRegistered<ApiClient>()) {
      final apiClient = sl<ApiClient>();
      final baseUrl = ApiUrl.leadService;

      for (final cid in candidateIds) {
        // Try follow-up lookup
        try {
          final res = await apiClient.get('$baseUrl/leads/followups/$cid');
          final rBody = res.data;
          if (rBody != null && rBody['data'] != null) {
            final fData = rBody['data'] is Map ? rBody['data'] as Map : null;
            final realLeadId = (fData?['leadId'] ?? fData?['lead']?['id'])?.toString().trim();
            if (realLeadId != null && realLeadId.isNotEmpty) {
              return realLeadId;
            }
          }
        } catch (_) {}

        // Try direct lead verification
        try {
          final res = await apiClient.get('$baseUrl/leads/$cid');
          final rBody = res.data;
          if (rBody != null && (rBody['success'] == true || res.statusCode == 200) && rBody['data'] != null) {
            return cid;
          }
        } catch (_) {}
      }
    }

    // 3. Try phone search if present in data, title, or body
    if (sl.isRegistered<LeadsRepository>()) {
      final phone = data?['phone']?.toString().trim() ??
          data?['phoneNumber']?.toString().trim() ??
          data?['mobile']?.toString().trim();
      if (phone != null && phone.isNotEmpty) {
        try {
          final searchRes = await sl<LeadsRepository>().searchLeadByNumber(phone);
          final leadId = searchRes.fold((_) => null, (r) => r.leadId);
          if (leadId != null && leadId.isNotEmpty) return leadId;
        } catch (_) {}
      }

      final text = '${title ?? ''} ${body ?? ''}';
      final phoneMatch = RegExp(r'(?:\+91|0)?[6-9]\d{9}').firstMatch(text);
      if (phoneMatch != null) {
        try {
          final searchRes = await sl<LeadsRepository>().searchLeadByNumber(phoneMatch.group(0)!);
          final leadId = searchRes.fold((_) => null, (r) => r.leadId);
          if (leadId != null && leadId.isNotEmpty) return leadId;
        } catch (_) {}
      }
    }

    return null;
  }

  int get unreadCount => value.where((n) => !n.isRead).length;

  Future<void> _initTts() async {
    if (_ttsInitialized) return;
    try {
      await _tts.setLanguage("en-US");
      await _tts.setSpeechRate(0.38);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      try {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
        );
      } catch (_) {}
      _ttsInitialized = true;
    } catch (e) {
      debugPrint("TTS Init Error: $e");
    }
  }

  Future<void> speakNotificationTitle(String title) async {
    try {
      if (title.trim().isEmpty) return;
      await _initTts();
      await _tts.stop();
      await _tts.setSpeechRate(0.38);
      final cleanTitle = title.replaceAll(RegExp(r'[^\w\s\d,.-]'), '').trim();
      final textToSpeak = cleanTitle.isNotEmpty ? cleanTitle : title;
      await _tts.speak(textToSpeak);
    } catch (e) {
      debugPrint("TTS Speak Error: $e");
    }
  }

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

  Future<void> refresh() async {
    await _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;
      _cachedUserId ??= prefs.getString('userId');
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
    bool speakTitle = false,
  }) {
    addNotificationAsync(
      title: title,
      body: body,
      type: type,
      data: data,
      speakTitle: speakTitle,
    );
  }

  Future<void> addNotificationAsync({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? data,
    bool speakTitle = false,
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

    final isSelfLead = isSelfAddLeadNotification(title: title, body: body, data: data);
    if (speakTitle && !isSelfLead) {
      await speakNotificationTitle(title);
    }
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
