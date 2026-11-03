import 'dart:async';
import 'dart:io';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:crm_mobile/core/services/direct_call_helper.dart';
import 'package:crm_mobile/core/utils/staff_phone_resolver.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/call_history.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/repositories/staff_personal_numbers_repository.dart';

class AutoCallRecordingUploader {
  static const String _prefKey = 'uploaded_call_recordings_v5';
  static final Set<String> _uploadedPaths = {};
  static final Set<String> _failedUploads = {};
  static final Set<String> _currentlyUploadingPaths = {};
  // Session-level guard: tracks (boundStr+bucket) keys uploaded in THIS scan run.
  // Cleared on each new scan entry, preventing same call from posting twice due
  // to the same startTime appearing in both systemCallLogs and trackedCallHistory.
  static final Set<String> _sessionUploadedKeys = {};
  static bool _prefsLoaded = false;

  static Future<void> clearFailedUploads() async {
    _failedUploads.clear();
    _currentlyUploadingPaths.clear();
    _uploadedPaths.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (e) {
      debugPrint('Error clearing uploaded recording prefs: $e');
    }
  }

  static Future<void> _ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKeys = prefs.getStringList(_prefKey) ?? [];
      _uploadedPaths.addAll(savedKeys);
      _prefsLoaded = true;
    } catch (e) {
      debugPrint('Error loading uploaded recording prefs: $e');
    }
  }

  static String cleanFileName(String name) {
    var clean = name.trim();
    // Normalize + to _ for consistent comparison (e.g. Call_+918925966055 → Call__918925966055)
    clean = clean.replaceAll('+', '_');
    while (true) {
      final old = clean;
      clean = clean.replaceAll(
        RegExp(r'^\.?pending[-_]?[a-zA-Z0-9]*[-_]?', caseSensitive: false),
        '',
      );
      clean = clean.replaceAll(
        RegExp(r'^\.?pending', caseSensitive: false),
        '',
      );
      while (clean.startsWith('.')) {
        clean = clean.substring(1);
      }
      clean = clean
          .replaceAll(RegExp(r'^REC_\d+_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^REC_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^INBOUND_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^OUTBOUND_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^INCOMING_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^OUTGOING_', caseSensitive: false), '')
          .replaceAll(RegExp(r'^Call_', caseSensitive: false), '');

      // Strip leading phone number (7 to 15 digits, optionally with (digits)),
      // BUT do NOT strip 14-digit date timestamps (starting with 202/203) or 13-digit epoch ms (16-19)
      final phoneMatch = RegExp(
        r'^(?!(?:20[2-3]\d{11}|1[6-9]\d{11}))\d{7,15}(\(\d{7,15}\))?[-_]?',
        caseSensitive: false,
      ).firstMatch(clean);
      if (phoneMatch != null) {
        clean = clean.substring(phoneMatch.end);
      }

      if (clean == old) break;
    }
    return clean;
  }

  static DateTime? parseCallDateTime(
    String? dateStr,
    String? timeStr, [
    String? createdAt,
  ]) {
    final cleanTime = (timeStr ?? '').trim();
    final cleanDate = (dateStr ?? '').trim();

    if (cleanTime.isNotEmpty && cleanTime != '--:--' && cleanTime != 'null') {
      try {
        final parsed = DateTime.parse(cleanTime).toLocal();
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
    }

    if (cleanDate.isNotEmpty) {
      var dStr = cleanDate;
      if (dStr.toUpperCase() == 'TODAY') {
        dStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      } else if (dStr.toUpperCase() == 'YESTERDAY') {
        dStr = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().subtract(const Duration(days: 1)));
      }

      if (cleanTime.isNotEmpty && cleanTime != '--:--' && cleanTime != 'null') {
        final combined = '$dStr $cleanTime';
        final formats = [
          'yyyy-MM-dd hh:mm:ss a',
          'yyyy-MM-dd hh:mm a',
          'yyyy-MM-dd HH:mm:ss',
          'yyyy-MM-dd HH:mm',
          'dd-MM-yyyy hh:mm:ss a',
          'dd-MM-yyyy hh:mm a',
          'dd-MM-yyyy HH:mm:ss',
          'dd-MM-yyyy HH:mm',
          'yyyy/MM/dd hh:mm:ss a',
          'yyyy/MM/dd HH:mm:ss',
          'dd/MM/yyyy hh:mm:ss a',
          'dd/MM/yyyy HH:mm:ss',
        ];
        for (final fmt in formats) {
          try {
            final parsed = DateFormat(fmt).parse(combined);
            if (parsed.year > 2000) return parsed;
          } catch (_) {}
        }
      }

      try {
        final parsed = DateTime.parse(dStr).toLocal();
        if (parsed.year > 2000) {
          if (parsed.hour != 0 || parsed.minute != 0 || parsed.second != 0 || createdAt == null || createdAt.isEmpty) {
            return parsed;
          }
        }
      } catch (_) {}
      if (createdAt != null && createdAt.isNotEmpty) {
        try {
          final parsed = DateTime.parse(createdAt).toLocal();
          if (parsed.year > 2000) return parsed;
        } catch (_) {}
      }
      try {
        final parsed = DateFormat('yyyy-MM-dd').parse(dStr);
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
      try {
        final parsed = DateFormat('dd-MM-yyyy').parse(dStr);
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
      try {
        final parsed = DateTime.parse(dStr).toLocal();
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
    }

    if (createdAt != null && createdAt.isNotEmpty) {
      try {
        final parsed = DateTime.parse(createdAt).toLocal();
        if (parsed.year > 2000) return parsed;
      } catch (_) {}
    }

    return null;
  }

  static Future<void> _markAsUploaded(String path, int length) async {
    await _ensurePrefsLoaded();
    final fileName = path.split('/').last;
    final cleanName = cleanFileName(fileName);

    _uploadedPaths.add(path);
    _uploadedPaths.add('${path}_$length');
    _uploadedPaths.add('${path}_0');
    _uploadedPaths.add(fileName);
    _uploadedPaths.add('${fileName}_$length');
    _uploadedPaths.add(cleanName);
    _uploadedPaths.add('${cleanName}_$length');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _uploadedPaths.toList());
    } catch (e) {
      debugPrint('Error saving uploaded recording prefs: $e');
    }
  }

  static Future<bool> isAlreadyUploaded(
    String path,
    int length, {
    List<LeadAudio>? existingServerAudios,
  }) async {
    await _ensurePrefsLoaded();

    final isMissedCallKey = path.startsWith('missed_');
    final isCallLogKey = path.startsWith('calllog_');

    // Ignore empty/corrupted audio fragments under 100 bytes unless it's a dummy missed/calllog entry
    if (!isMissedCallKey && !isCallLogKey && length > 0 && length < 100)
      return true;

    final fileName = path.split('/').last;
    final clean = cleanFileName(fileName);
    final hasTimestampInName = parseTimestampFromFileName(fileName) != null;

    // 1. ALWAYS check local uploaded cache first regardless of existingServerAudios
    if (_uploadedPaths.contains(path) ||
        _uploadedPaths.contains('${path}_$length') ||
        _uploadedPaths.contains('${fileName}_$length') ||
        (clean.length >= 8 && _uploadedPaths.contains('${clean}_$length')) ||
        (hasTimestampInName && _uploadedPaths.contains(fileName))) {
      return true;
    }

    if (isMissedCallKey || isCallLogKey) {
      if (existingServerAudios != null) {
        final parts = path.split('_');
        if (parts.length >= 3) {
          int ts = 0;
          for (final part in parts) {
            final parsed = int.tryParse(part);
            if (parsed != null && parsed > 1000000000) {
              ts = parsed;
              break;
            }
          }
          final keyBound = parts.any((p) => p.toUpperCase() == 'IN') ? 'IN' : 'OUT';
          if (ts > 0) {
            for (final sAudio in existingServerAudios) {
              if (sAudio.size > 0 && isMissedCallKey)
                continue; // For missed call, skip real audio files

              final parsedTime = parseTimestampFromFileName(sAudio.displayName);
              final sAudioStartDt = parseCallDateTime(sAudio.callDate, sAudio.startTimeStr, sAudio.createdAt?.toIso8601String());
              final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
              final audioMs = (sAudioStartMs > 0) ? sAudioStartMs : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));

              if (audioMs > 0) {
                final serverBound = sAudio.bound?.toUpperCase() ?? '';
                final isBoundMatch =
                    serverBound.isEmpty ||
                    (keyBound == 'IN' &&
                        (serverBound == 'IN' ||
                            serverBound == 'INBOUND' ||
                            serverBound.contains('IN'))) ||
                    (keyBound == 'OUT' &&
                        (serverBound == 'OUT' ||
                            serverBound == 'OUTGOING' ||
                            serverBound.contains('OUT')));

                if (isBoundMatch) {
                  if ((audioMs - ts).abs() < 45000) {
                    await _markAsUploaded(path, 0);
                    return true;
                  }
                }
              }
            }
          }
        }
      }
      return false;
    }

    // 2. Real audio file matching against server audios
    if (existingServerAudios != null) {
      final fileTimestamp = parseTimestampFromFileName(fileName);
      for (final sAudio in existingServerAudios) {
        if (sAudio.size <= 0) continue; // Missed/dummy entries are size 0

        final serverTimestamp =
            parseTimestampFromFileName(sAudio.displayName) ??
            (sAudio.createdAt?.millisecondsSinceEpoch ?? 0);

        if (fileTimestamp != null && fileTimestamp > 0 && serverTimestamp > 0) {
          final diff = (fileTimestamp - serverTimestamp).abs();
          if (diff < 5000 &&
              (sAudio.size == length ||
                  (length > 0 && (sAudio.size - length).abs() < 2048))) {
            await _markAsUploaded(path, length);
            return true;
          }
        } else if (sAudio.size == length && length > 1000) {
          final serverClean = cleanFileName(sAudio.displayName.toLowerCase());
          if (serverClean == clean.toLowerCase()) {
            await _markAsUploaded(path, length);
            return true;
          }
        }
      }
      return false;
    }

    return false;
  }

  static final Set<String> _activeScanningLeads = {};
  static final Set<String> _queuedScanningLeads = {};
  static final Map<String, int> _lastCallUploadTimes = {};

  static bool _isCallRecentlyUploaded(String phone, {String? bound, String? leadId, int? timestampMs}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
    final b = (bound != null && bound.toUpperCase().startsWith('IN')) ? 'IN' : 'OUT';

    final keys = [
      if (last10.isNotEmpty) '${last10}_$b',
      if (last10.isNotEmpty) last10,
      if (leadId != null && leadId.isNotEmpty) '${leadId}_$b',
      if (leadId != null && leadId.isNotEmpty) leadId,
      if (timestampMs != null && timestampMs > 0 && last10.isNotEmpty)
        '${last10}_${b}_${(timestampMs ~/ 3500) * 3500}',
    ];

    for (final k in keys) {
      final t = _lastCallUploadTimes[k];
      if (t != null && (now - t) < 60000) {
        return true;
      }
    }
    return false;
  }

  static void _recordCallUploaded(String phone, {String? bound, String? leadId, int? timestampMs}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
    final b = (bound != null && bound.toUpperCase().startsWith('IN')) ? 'IN' : 'OUT';

    if (last10.isNotEmpty) {
      _lastCallUploadTimes['${last10}_$b'] = now;
      _lastCallUploadTimes[last10] = now;
    }
    if (leadId != null && leadId.isNotEmpty) {
      _lastCallUploadTimes['${leadId}_$b'] = now;
      _lastCallUploadTimes[leadId] = now;
    }
    if (timestampMs != null && timestampMs > 0 && last10.isNotEmpty) {
      _lastCallUploadTimes['${last10}_${b}_${(timestampMs ~/ 3500) * 3500}'] = now;
    }
  }

  static bool _isOutgoingRecentlyUploaded(String phone, String leadId) =>
      _isCallRecentlyUploaded(phone, bound: 'OUT', leadId: leadId);

  static void _recordOutgoingUploaded(String phone, String leadId) =>
      _recordCallUploaded(phone, bound: 'OUT', leadId: leadId);

  static Future<void> _markCallBucketAsUploaded(
    String phone,
    int timestampMs, [
    String? bound,
    String? callStatus,
  ]) async {
    await _ensurePrefsLoaded();
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final bucket = (timestampMs ~/ 3500) * 3500;
    final status = (callStatus != null && callStatus.isNotEmpty) ? callStatus.toUpperCase() : '';
    final dirKey = (bound != null && bound.toUpperCase().startsWith('IN')) ? 'IN' : 'OUT';

    for (final b in [
      bucket - 7000,
      bucket - 3500,
      bucket,
      bucket + 3500,
      bucket + 7000,
    ]) {
      _uploadedPaths.add('call_${last10}_$b');
      _uploadedPaths.add('call_${last10}_IN_$b');
      _uploadedPaths.add('call_${last10}_OUT_$b');
      _uploadedPaths.add('calllog_IN_${b}_$phone');
      _uploadedPaths.add('calllog_OUT_${b}_$phone');
      _uploadedPaths.add('calllog_IN_${b}_$cleanDigits');
      _uploadedPaths.add('calllog_OUT_${b}_$cleanDigits');
      _uploadedPaths.add('call_${last10}_${dirKey}_$b');
      _sessionUploadedKeys.add('${last10}_${dirKey}_$b');
      _sessionUploadedKeys.add('call_${last10}_$b');
      if (status.isNotEmpty) {
        _uploadedPaths.add('call_${last10}_${status}_$b');
        _uploadedPaths.add('calllog_${status}_${b}_$phone');
        _uploadedPaths.add('calllog_${status}_${b}_$cleanDigits');
        _uploadedPaths.add('calllog_${dirKey}_${status}_${b}_$phone');
        _uploadedPaths.add('calllog_${dirKey}_${status}_${b}_$cleanDigits');
        _sessionUploadedKeys.add('${last10}_${dirKey}_${status}_$b');
      }
    }
    _recordCallUploaded(phone, bound: bound, timestampMs: timestampMs);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _uploadedPaths.toList());
    } catch (_) {}
  }

  static Future<bool> isCallAlreadyUploaded({
    required String phone,
    required int timestampMs,
    String? bound,
    String? callStatus,
    List<LeadAudio>? existingServerAudios,
    List<LeadCallLog>? existingServerCallLogs,
  }) async {
    await _ensurePrefsLoaded();
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final bucket = (timestampMs ~/ 3500) * 3500;
    final status = (callStatus != null && callStatus.isNotEmpty) ? callStatus.toUpperCase() : '';
    final isBoundIn = bound != null && bound.toUpperCase().startsWith('IN');

    final buckets = [
      bucket - 35000,
      bucket - 28000,
      bucket - 21000,
      bucket - 14000,
      bucket - 10500,
      bucket - 7000,
      bucket - 3500,
      bucket,
      bucket + 3500,
      bucket + 7000,
      bucket + 10500,
      bucket + 14000,
      bucket + 21000,
      bucket + 28000,
      bucket + 35000,
    ];

    if (bound != null && bound.isNotEmpty) {
      final dirKey = isBoundIn ? 'IN' : 'OUT';
      for (final b in buckets) {
        if (_uploadedPaths.contains('call_${last10}_${dirKey}_$b') ||
            _uploadedPaths.contains('call_${last10}_$b') ||
            _uploadedPaths.contains('calllog_${dirKey}_${b}_$phone') ||
            _uploadedPaths.contains('calllog_${dirKey}_${b}_$cleanDigits') ||
            _sessionUploadedKeys.contains('${last10}_${dirKey}_$b') ||
            _sessionUploadedKeys.contains('call_${last10}_$b') ||
            (status.isNotEmpty &&
                (_uploadedPaths.contains('calllog_${dirKey}_${status}_${b}_$phone') ||
                    _uploadedPaths.contains('call_${last10}_${status}_$b') ||
                    _sessionUploadedKeys.contains('${last10}_${dirKey}_${status}_$b')))) {
          return true;
        }
      }
    } else {
      for (final b in buckets) {
        final key1 = 'call_${last10}_$b';
        final key2 = 'call_${last10}_IN_$b';
        final key2b = 'call_${last10}_OUT_$b';
        final key3 = 'calllog_IN_${b}_$phone';
        final key4 = 'calllog_OUT_${b}_$phone';
        final key5 = 'calllog_IN_${b}_$cleanDigits';
        final key6 = 'calllog_OUT_${b}_$cleanDigits';

        if (_uploadedPaths.contains(key1) ||
            _uploadedPaths.contains(key2) ||
            _uploadedPaths.contains(key2b) ||
            _uploadedPaths.contains(key3) ||
            _uploadedPaths.contains(key4) ||
            _uploadedPaths.contains(key5) ||
            _uploadedPaths.contains(key6) ||
            _sessionUploadedKeys.contains(key1)) {
          return true;
        }
      }
    }

    // Check against existingServerAudios (45s tolerance for both IN and OUT)
    if (existingServerAudios != null && existingServerAudios.isNotEmpty) {
      const maxDiff = 45000;
      for (final sAudio in existingServerAudios) {
        if (status == 'MISSED' && sAudio.size > 0) {
          // A missed call has no real audio file; don't match against existing real audios
          continue;
        }
        final parsedTime = parseTimestampFromFileName(sAudio.displayName);
        final sAudioStartDt = parseCallDateTime(sAudio.callDate, sAudio.startTimeStr, sAudio.createdAt?.toIso8601String());
        final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
        final audioMs = (sAudioStartMs > 0) ? sAudioStartMs : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));

        final bool isMatch = (sAudioStartMs > 0 && (sAudioStartMs - timestampMs).abs() < maxDiff) ||
            (parsedTime != null && (parsedTime - timestampMs).abs() < maxDiff) ||
            (audioMs > 0 && (audioMs - timestampMs).abs() < maxDiff);

        if (isMatch) {
          if (bound == null ||
              bound.isEmpty ||
              checkBoundMatch(bound, sAudio.bound ?? '')) {
            await _markCallBucketAsUploaded(phone, timestampMs, bound, callStatus);
            return true;
          }
        }
      }
    }

    // Check against existingServerCallLogs (45s tolerance for both IN and OUT)
    if (existingServerCallLogs != null && existingServerCallLogs.isNotEmpty) {
      const maxDiff = 45000;
      for (final sLog in existingServerCallLogs) {
        if (status.isNotEmpty) {
          final sStatus = sLog.callStatus.toUpperCase();
          if (sStatus != status &&
              !(sStatus.contains('CONN') && status.contains('ANS')) &&
              !(sStatus.contains('ANS') && status.contains('CONN'))) {
            continue;
          }
        }
        final sDt = parseCallDateTime(
          sLog.callDate,
          sLog.startTime,
          sLog.createdAt,
        );
        if (sDt != null) {
          final sMs = sDt.millisecondsSinceEpoch;
          final bool isMatch = (sMs - timestampMs).abs() < maxDiff;
          if (isMatch) {
            if (bound == null ||
                bound.isEmpty ||
                checkBoundMatch(bound, sLog.bound)) {
              await _markCallBucketAsUploaded(phone, timestampMs, bound, callStatus);
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  static bool _isSyncingRecentCalls = false;
  static bool _syncQueued = false;
  static Map<String, dynamic>? _pendingCall;

  static Future<void> _clearPendingCall() async {
    _pendingCall = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_lead_call_id');
      await prefs.remove('pending_lead_phone');
      await prefs.remove('pending_lead_time');
    } catch (_) {}
  }

  /// Automatically synchronizes recent calls when entering the Lead List screen.
  /// 1. If a call was initiated from the app, it directly matches the known lead.
  /// 2. If recent system call logs exist, it matches against [knownLeads] in memory or searches CRM.
  /// 3. Uploads call recording & logs via POST /leads/{leadId}/audios, and fetches updated audios/logs via GET.
  static Future<void> syncRecentCallsIfAvailable({
    List<dynamic>? knownLeads,
    VoidCallback? onUploadSuccess,
  }) async {
    if (_isSyncingRecentCalls) {
      _syncQueued = true;
      return;
    }
    _isSyncingRecentCalls = true;

    try {
      final service = CallRecordingService();

      // If call is actively ongoing, postpone until it ends
      if (await service.isCallOngoing()) {
        debugPrint('Sync: Call is actively ongoing, will sync once call ends.');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Process initiated / pending call from memory or SharedPreferences
      String? pendingLeadId = _pendingCall?['leadId'] as String?;
      String? pendingPhone = _pendingCall?['phoneNumber'] as String?;
      int pendingTime = (_pendingCall?['callStartTimestamp'] as int?) ?? 0;

      if (pendingLeadId == null || pendingLeadId.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedLeadId = prefs.getString('pending_lead_call_id');
          final savedPhone = prefs.getString('pending_lead_phone');
          final savedTime = prefs.getInt('pending_lead_time') ?? 0;
          if (savedLeadId != null &&
              savedLeadId.isNotEmpty &&
              (now - savedTime) < 30 * 60 * 1000) {
            pendingLeadId = savedLeadId;
            pendingPhone = savedPhone;
            pendingTime = savedTime;
          }
        } catch (_) {}
      }

      if (pendingLeadId != null &&
          pendingLeadId.isNotEmpty &&
          pendingPhone != null &&
          pendingPhone.isNotEmpty) {
        debugPrint(
          'Sync: Found pending call for lead $pendingLeadId ($pendingPhone). Auto-scanning & uploading...',
        );
        await _clearPendingCall();

        final repo = sl<LeadsRepository>();
        final leadIdToUpload = pendingLeadId;
        final phoneToUpload = pendingPhone;

        await autoScanAndUploadLeadRecordings(
          context: null,
          leadId: leadIdToUpload,
          phoneNumber: phoneToUpload,
          callTimestamp: pendingTime,
          initialBound: 'OUT',
          onUploadSuccess: () async {
            try {
              await repo.getLeadAudios(leadIdToUpload);
              await repo.getLeadCallLogs(leadIdToUpload);
            } catch (_) {}
            if (onUploadSuccess != null) onUploadSuccess();
          },
        );

        // Schedule follow-up scan for recorders that take 2-3s to flush file to storage
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (_isOutgoingRecentlyUploaded(phoneToUpload, leadIdToUpload)) return;
          autoScanAndUploadLeadRecordings(
            context: null,
            leadId: leadIdToUpload,
            phoneNumber: phoneToUpload,
            callTimestamp: pendingTime,
            initialBound: 'OUT',
            onUploadSuccess: () async {
              try {
                await repo.getLeadAudios(leadIdToUpload);
                await repo.getLeadCallLogs(leadIdToUpload);
              } catch (_) {}
              if (onUploadSuccess != null) onUploadSuccess();
            },
          );
        });
      }

      // 2. Scan recent system call logs (last 30 calls within 24 hours)
      final recentLogs = await service.getSystemCallLogs('');
      if (recentLogs.isEmpty) return;

      for (final log in recentLogs.take(30)) {
        final st = log['startTime'] as int? ?? 0;
        if (st <= 0 || (now - st) > 24 * 60 * 60 * 1000) continue;

        final rawPhone = log['phoneNumber']?.toString() ?? '';
        final cleanDigits = rawPhone.replaceAll(RegExp(r'\D'), '');
        if (cleanDigits.length < 7) continue;

        if (await StaffPersonalNumbersRepositoryImpl.isNumberBlocked(
          rawPhone,
        )) {
          continue;
        }

        final callTypeRaw = (log['callType'] as String? ?? '').toUpperCase();
        final isIncoming = callTypeRaw == 'INCOMING' ||
            callTypeRaw == 'INBOUND' ||
            callTypeRaw == 'MISSED' ||
            callTypeRaw == 'REJECTED';
        final boundStr = isIncoming ? 'IN' : 'OUT';
        final logDur = (log['durationSeconds'] as num?)?.toInt() ?? (log['duration'] as num?)?.toInt() ?? 0;
        final isMissedLog = callTypeRaw == 'MISSED' || callTypeRaw == 'REJECTED' || (log['callStatus'] as String? ?? '').toUpperCase() == 'MISSED';
        final logStatusStr = isMissedLog ? 'MISSED' : (logDur > 0 ? 'CONNECTED' : (isIncoming ? 'MISSED' : 'NOT_CONNECTED'));

        if (_isCallRecentlyUploaded(rawPhone, bound: boundStr, timestampMs: st)) {
          continue;
        }

        if (await isCallAlreadyUploaded(
          phone: rawPhone,
          timestampMs: st,
          bound: boundStr,
          callStatus: logStatusStr,
        )) {
          continue;
        }

        final last10 = cleanDigits.length >= 10
            ? cleanDigits.substring(cleanDigits.length - 10)
            : cleanDigits;

        String? leadId;

        // Try to match against in-memory loaded leads first (instant)
        if (knownLeads != null && knownLeads.isNotEmpty) {
          for (final dynamic item in knownLeads) {
            final p = item.phone?.toString() ?? '';
            final pDigits = p.replaceAll(RegExp(r'\D'), '');
            final pLast10 = pDigits.length >= 10
                ? pDigits.substring(pDigits.length - 10)
                : pDigits;
            if (pLast10.isNotEmpty &&
                (pLast10 == last10 ||
                    cleanDigits.endsWith(pLast10) ||
                    pDigits.endsWith(last10))) {
              leadId = item.id?.toString();
              break;
            }
          }
        }

        // If not in in-memory leads, search backend with clean 10-digit number
        final repo = sl<LeadsRepository>();
        if (leadId == null || leadId.isEmpty) {
          final searchResult = await repo.searchLeadByNumber(last10);
          leadId = searchResult.fold((_) => null, (r) => r.leadId);
        }

        // Fallback to searching with raw number if different
        if ((leadId == null || leadId.isEmpty) && rawPhone != last10) {
          final searchResult = await repo.searchLeadByNumber(rawPhone);
          leadId = searchResult.fold((_) => null, (r) => r.leadId);
        }

        if (leadId != null && leadId.isNotEmpty) {
          debugPrint(
            'Recent unuploaded call detected for lead $leadId ($rawPhone) at $st. Auto-uploading...',
          );
          final matchedLeadId = leadId;
          await autoScanAndUploadLeadRecordings(
            context: null,
            leadId: matchedLeadId,
            phoneNumber: rawPhone,
            callTimestamp: st,
            initialBound: boundStr,
            onUploadSuccess: () async {
              try {
                await repo.getLeadAudios(matchedLeadId);
                await repo.getLeadCallLogs(matchedLeadId);
              } catch (_) {}
              if (onUploadSuccess != null) onUploadSuccess();
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Error in syncRecentCallsIfAvailable: $e');
    } finally {
      _isSyncingRecentCalls = false;
      if (_syncQueued) {
        _syncQueued = false;
        Future.delayed(const Duration(milliseconds: 500), () {
          syncRecentCallsIfAvailable(
            knownLeads: knownLeads,
            onUploadSuccess: onUploadSuccess,
          );
        });
      }
    }
  }

  /// Initiates a phone call to [phoneNumber] for [leadId] and automatically tracks
  /// call start time, end time, duration, caller (from) & receiver (to) numbers.
  static Future<void> makeCallAndAutoUpload({
    required BuildContext context,
    required String leadId,
    required String phoneNumber,
    String? leadName,
    VoidCallback? onUploadSuccess,
  }) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number available for this lead.'),
        ),
      );
      return;
    }

    final isBlocked = await StaffPersonalNumbersRepositoryImpl.isNumberBlocked(
      phoneNumber,
    );
    if (!context.mounted) return;
    if (isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Calling blocked/personal number: ${leadName ?? phoneNumber} (Recording & log tracking disabled).',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      DirectCallHelper.makeCall(phoneNumber);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Calling ${leadName ?? phoneNumber}... Call recording will auto-upload when finished.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    final callStartTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Persist pending call info so lead list automatically syncs even if app is backgrounded
    _pendingCall = {
      'leadId': leadId,
      'phoneNumber': phoneNumber,
      'leadName': leadName,
      'callStartTimestamp': callStartTimestamp,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_lead_call_id', leadId);
      await prefs.setString('pending_lead_phone', phoneNumber);
      await prefs.setInt('pending_lead_time', callStartTimestamp);
    } catch (_) {}

    // Launch dialer IMMEDIATELY without waiting for async disk I/O
    DirectCallHelper.makeCall(phoneNumber);

    // Track call history and setup auto-upload timers in background
    unawaited(
      _trackCallAndSetupUpload(
        context: context,
        leadId: leadId,
        phoneNumber: phoneNumber,
        leadName: leadName,
        callStartTimestamp: callStartTimestamp,
        onUploadSuccess: onUploadSuccess,
      ),
    );
  }

  static Future<void> trackCurrentCallForLead({
    required String leadId,
    required String phoneNumber,
    String? leadName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _pendingCall = {
      'leadId': leadId,
      'phoneNumber': phoneNumber,
      'leadName': leadName ?? 'quick call user',
      'callStartTimestamp': now,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_lead_call_id', leadId);
      await prefs.setString('pending_lead_phone', phoneNumber);
      await prefs.setInt('pending_lead_time', now);
    } catch (_) {}

    unawaited(
      _trackCallAndSetupUpload(
        context: null,
        leadId: leadId,
        phoneNumber: phoneNumber,
        leadName: leadName ?? 'quick call user',
        callStartTimestamp: now,
      ),
    );
  }

  static Future<void> _trackCallAndSetupUpload({
    BuildContext? context,
    required String leadId,
    required String phoneNumber,
    String? leadName,
    required int callStartTimestamp,
    VoidCallback? onUploadSuccess,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final staffUserName = prefs.getString('userName')?.trim();
    final staffUserPhone = prefs.getString('userPhone')?.trim();
    final fromUser = (staffUserName != null && staffUserName.isNotEmpty)
        ? staffUserName
        : ((staffUserPhone != null && staffUserPhone.isNotEmpty)
              ? staffUserPhone
              : 'Staff');
    final callId = DateTime.now().microsecondsSinceEpoch.toString();

    final formattedStart = DateFormat(
      'dd-MM-yyyy HH:mm:ss',
    ).format(DateTime.fromMillisecondsSinceEpoch(callStartTimestamp));

    debugPrint(
      '=================================================================',
    );
    debugPrint(
      'CALL STARTED -> From: $fromUser | To: $phoneNumber | Start Time: $formattedStart',
    );
    debugPrint(
      '=================================================================',
    );

    // Create initial CallHistory record
    var callHistoryEntry = CallHistory(
      id: callId,
      phoneNumber: phoneNumber,
      contactName: leadName,
      callType: 'OUTGOING',
      timestamp: callStartTimestamp,
      startTime: callStartTimestamp,
      endTime: callStartTimestamp,
      durationSeconds: 0,
      appUserName: staffUserName,
      appUserPhone: staffUserPhone ?? fromUser,
      callStatus: 'NOT_CONNECTED',
    );
    await CallHistoryStorage.addOrUpdateCall(callHistoryEntry);

    final callRecordingService = CallRecordingService();
    bool hasUploaded = false;
    bool wasCallActive = false;
    bool isScanExecuting = false;

    Future<void> doScanAndUpload() async {
      if (hasUploaded || isScanExecuting) return;
      if (await callRecordingService.isCallOngoing()) {
        debugPrint('Call is currently active, waiting for call to end.');
        return;
      }
      if (_isOutgoingRecentlyUploaded(phoneNumber, leadId)) {
        debugPrint('Outgoing call for $leadId recently uploaded, skipping duplicate.');
        return;
      }
      isScanExecuting = true;
      try {
        final details = await callRecordingService.getLatestCallDetails(
          phoneNumber: phoneNumber,
          callTimestamp: callStartTimestamp,
        );

        // If system call log is not available yet and call is recent (< 25s), wait for Android to write it
        if (details == null && (DateTime.now().millisecondsSinceEpoch - callStartTimestamp) < 25000) {
          debugPrint('Call log not written yet by Android, postponing upload.');
          return;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final startMs =
            details != null && (details['startTime'] as int? ?? 0) > 0
            ? (details['startTime'] as int)
            : callStartTimestamp;
        final endMs = details != null && (details['endTime'] as int? ?? 0) > 0
            ? (details['endTime'] as int)
            : nowMs;
        final durationSec = details != null
            ? (details['durationSeconds'] as int? ?? 0)
            : 0;

        final rawStatus = details != null
            ? (details['callStatus']?.toString() ?? '')
            : '';
        final statusUpper = rawStatus.toUpperCase();
        final statusStr = durationSec > 0 || statusUpper == 'ANSWERED' || statusUpper == 'CONNECTED'
            ? 'CONNECTED'
            : (statusUpper == 'UNANSWERED' || statusUpper == 'MISSED'
                  ? statusUpper
                  : 'NOT_CONNECTED');

        final formattedEnd = DateFormat(
          'dd-MM-yyyy HH:mm:ss',
        ).format(DateTime.fromMillisecondsSinceEpoch(endMs));

        callHistoryEntry = callHistoryEntry.copyWith(
          startTime: startMs,
          endTime: endMs,
          durationSeconds: durationSec,
          callStatus: statusStr,
        );
        await CallHistoryStorage.addOrUpdateCall(callHistoryEntry);
        await CallHistoryStorage.markCallAsSynced(phoneNumber, startMs);

        debugPrint(
          '=================================================================',
        );
        debugPrint(
          'CALL ENDED/TRACKED -> From: $fromUser | To: $phoneNumber | End Time: $formattedEnd | Duration: ${durationSec}s',
        );
        debugPrint(
          '=================================================================',
        );

        await autoScanAndUploadLeadRecordings(
          context: (context != null && context.mounted) ? context : null,
          leadId: leadId,
          phoneNumber: phoneNumber,
          callTimestamp: startMs,
          initialBound: 'OUT',
          onUploadSuccess: () async {
            hasUploaded = true;
            await _clearPendingCall();
            try {
              final repo = sl<LeadsRepository>();
              await repo.getLeadAudios(leadId);
              await repo.getLeadCallLogs(leadId);
            } catch (_) {}
            if (onUploadSuccess != null) onUploadSuccess();
          },
        );
      } catch (e) {
        debugPrint('Error in doScanAndUpload: $e');
      } finally {
        isScanExecuting = false;
      }
    }

    // Active real-time watcher: detects call termination every 1.5 seconds and uploads immediately
    int pollTicks = 0;
    Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      pollTicks++;
      if (hasUploaded || pollTicks > 160) {
        // Max 4 minutes
        timer.cancel();
        return;
      }

      final isOngoing = await callRecordingService.isCallOngoing();
      if (isOngoing) {
        wasCallActive = true;
      } else if (wasCallActive) {
        // Call was active and has ended
        wasCallActive = false;
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (!hasUploaded) doScanAndUpload();
        });
      } else if (pollTicks >= 20) {
        // Dialer elapsed without active call (cancelled before connecting)
        timer.cancel();
        if (!hasUploaded) doScanAndUpload();
      }
    });

    // Fallback milestone checks for calls not caught by periodic watcher
    for (final delaySec in [30, 60, 120]) {
      Future.delayed(Duration(seconds: delaySec), () async {
        if (!hasUploaded && !await callRecordingService.isCallOngoing()) {
          await doScanAndUpload();
        }
      });
    }
  }

  /// Scans system recordings for a call to [phoneNumber] around [callTimestamp]
  /// and automatically uploads it if found and not already uploaded.
  static Future<void> checkAndUploadLatestRecording({
    required BuildContext? context,
    required String leadId,
    required String phoneNumber,
    required int callTimestamp,
    VoidCallback? onUploadSuccess,
  }) async {
    try {
      final service = CallRecordingService();
      String? recordingPath = await service.findLatestSystemRecording(
        callTimestamp: callTimestamp,
        phoneNumber: phoneNumber,
      );

      // Retry once after 3 seconds if not immediately found
      if (recordingPath == null) {
        await Future.delayed(const Duration(seconds: 3));
        recordingPath = await service.findLatestSystemRecording(
          callTimestamp: callTimestamp,
          phoneNumber: phoneNumber,
        );
      }

      if (recordingPath != null && recordingPath.isNotEmpty) {
        final file = File(recordingPath);
        if (await file.exists()) {
          // Wait for file length stability to ensure phone recorder has finished writing complete file
          int length = await file.length();
          await Future.delayed(const Duration(milliseconds: 600));
          if (await file.exists()) {
            length = await file.length();
          }

          if (length >= 100) {
            if (await isAlreadyUploaded(recordingPath, length)) {
              debugPrint('Recording $recordingPath already uploaded.');
              if (onUploadSuccess != null) onUploadSuccess();
              return;
            }

            final callDetails = await CallRecordingService()
                .getLatestCallDetails(
                  phoneNumber: phoneNumber,
                  callTimestamp: callTimestamp,
                );
            final prefs = await SharedPreferences.getInstance();
            final staffPhone = prefs.getString('userPhone')?.trim() ?? '';

            final meta = await buildAudioMetadata(
              filePath: recordingPath,
              phoneNumber: phoneNumber,
              bound: null,
              callTimestamp: callTimestamp,
              callDetails: callDetails,
              staffUserPhone: staffPhone,
            );

            debugPrint(
              'Auto-uploading call recording: $recordingPath for leadId: $leadId with meta: $meta',
            );

            final repo = sl<LeadsRepository>();
            final result = await repo.uploadLeadAudio(
              leadId,
              recordingPath,
              bound: meta['bound'],
              startTime: meta['startTime'],
              endTime: meta['endTime'],
              from: meta['from'],
              to: meta['to'],
              duration: meta['duration'],
              callDate: meta['callDate'],
              callStatus: 'CONNECTED',
            );

            result.fold(
              (failure) {
                debugPrint('Auto-upload failed: ${failure.message}');
                if (onUploadSuccess != null) onUploadSuccess();
              },
              (audio) async {
                await _markAsUploaded(recordingPath!, length);
                await CallHistoryStorage.markCallAsSynced(
                  phoneNumber,
                  callTimestamp,
                );
                debugPrint(
                  'Call recording auto-uploaded successfully! Audio ID: ${audio.id}',
                );
                if (onUploadSuccess != null) {
                  onUploadSuccess();
                }
              },
            );
          }
        }
      } else {
        debugPrint(
          'No new system recording found for call at $callTimestamp for $phoneNumber',
        );
        if (onUploadSuccess != null) onUploadSuccess();
      }
    } catch (e) {
      debugPrint('Error in checkAndUploadLatestRecording: $e');
      if (onUploadSuccess != null) onUploadSuccess();
    }
  }

  /// Scans system recordings for ALL recordings (incoming or outgoing) matching [phoneNumber]
  /// and automatically uploads any new/unuploaded recordings to the backend.
  static Future<void> autoScanAndUploadLeadRecordings({
    required BuildContext? context,
    required String leadId,
    required String phoneNumber,
    int callTimestamp = 0,
    String? initialBound,
    List<LeadAudio>? existingServerAudios,
    List<LeadCallLog>? existingServerCallLogs,
    VoidCallback? onUploadSuccess,
  }) async {
    if (phoneNumber.isEmpty) return;
    if (await StaffPersonalNumbersRepositoryImpl.isNumberBlocked(phoneNumber)) {
      debugPrint(
        'Skipping autoScanAndUploadLeadRecordings for blocked personal number: $phoneNumber',
      );
      return;
    }

    if (!_activeScanningLeads.add(leadId)) {
      _queuedScanningLeads.add(leadId);
      debugPrint(
        'Scan already in progress for leadId: $leadId, queued for next run.',
      );
      return;
    }

    bool uploadedAny = false;
    // Tracks timestamps of calls for which an audio file was successfully uploaded in Phase 1.
    // Phase 2 will skip these so we don't double-post a connected call.
    final Set<int> uploadedAudioTimestamps = {};

    try {
      _sessionUploadedKeys.clear();
      List<LeadAudio> serverAudios = existingServerAudios != null
          ? List.from(existingServerAudios)
          : [];
      List<LeadCallLog> serverCallLogs = existingServerCallLogs != null
          ? List.from(existingServerCallLogs)
          : [];

      if (existingServerAudios == null || existingServerCallLogs == null) {
        try {
          final repo = sl<LeadsRepository>();
          if (existingServerAudios == null) {
            final audiosRes = await repo.getLeadAudios(leadId);
            audiosRes.fold((_) {}, (list) => serverAudios = list);
          }
          if (existingServerCallLogs == null) {
            final logsRes = await repo.getLeadCallLogs(leadId);
            logsRes.fold(
              (_) {},
              (history) => serverCallLogs = history.callHistory,
            );
          }
        } catch (e) {
          debugPrint('Could not fetch server logs for deduplication: $e');
        }
      }
      final service = CallRecordingService();
      final allRecordings = await service.getAllSystemRecordings(
        phoneNumber,
        callTimestamp: callTimestamp,
      );
      final prefs = await SharedPreferences.getInstance();
      final staffPhone = prefs.getString('userPhone')?.trim() ?? '';

      for (final recording in allRecordings) {
        final path = recording['path'] as String?;
        if (path == null || path.isEmpty) continue;

        final file = File(path);
        if (!await file.exists()) continue;
        final length = await file.length();
        if (length <= 0) continue;

        final lastMod = await file.lastModified();
        final ageMs =
            DateTime.now().millisecondsSinceEpoch -
            lastMod.millisecondsSinceEpoch;

        var finalLength = length;
        if (ageMs < 4000) {
          final isOngoing = await service.isCallOngoing();
          if (isOngoing) {
            await Future.delayed(const Duration(milliseconds: 150));
            if (!await file.exists()) continue;
            final length2 = await file.length();
            if (length != length2) {
              debugPrint(
                'Recording file $path is actively growing ($length -> $length2 bytes). Live call ongoing, skipping.',
              );
              continue;
            }
            finalLength = length2;
          }
        }

        final fileName = path.split('/').last;
        final cleanName = cleanFileName(fileName);

        if (_currentlyUploadingPaths.contains(path) ||
            _currentlyUploadingPaths.contains(cleanName)) {
          continue;
        }

        if (await isAlreadyUploaded(
          path,
          finalLength,
          existingServerAudios: serverAudios,
        )) {
          final recTimestamp = (recording['timestamp'] as num?)?.toInt() ?? 0;
          final fileTimestamp =
              parseTimestampFromFileName(fileName) ?? recTimestamp;
          final effectiveTime = fileTimestamp > 0
              ? fileTimestamp
              : recTimestamp;
          if (effectiveTime > 0) {
            uploadedAudioTimestamps.add(effectiveTime);
            await _markCallBucketAsUploaded(phoneNumber, effectiveTime, null);
          }
          if (callTimestamp > 0 && effectiveTime > 0 && (effectiveTime - callTimestamp).abs() < 3500) {
            uploadedAudioTimestamps.add(callTimestamp);
            await _markCallBucketAsUploaded(phoneNumber, callTimestamp, null);
          }
          if (recTimestamp > 0) {
            uploadedAudioTimestamps.add(recTimestamp);
          }
          continue;
        }

        final recTimestamp = (recording['timestamp'] as num?)?.toInt() ?? 0;
        final fileTimestamp =
            parseTimestampFromFileName(fileName) ?? recTimestamp;
        final targetSearchTime = (fileTimestamp > 0)
            ? fileTimestamp
            : callTimestamp;

        final callDetails = await service.getLatestCallDetails(
          phoneNumber: phoneNumber,
          callTimestamp: targetSearchTime,
        );

        final localDurMs = (recording['durationMs'] as num?)?.toInt() ?? 0;
        final localDurSec = (localDurMs / 1000).round();

        final recCallType =
            recording['callType']?.toString().trim().toUpperCase() ?? '';
        final callDetailsType =
            callDetails?['callType']?.toString().trim().toUpperCase() ?? '';
        final lowerFileName = fileName.toLowerCase();

        final bool isDefiniteIncoming =
            callDetailsType == 'INCOMING' ||
            callDetailsType == 'INBOUND' ||
            callDetailsType == 'MISSED' ||
            recCallType == 'INBOUND' ||
            recCallType == 'INCOMING' ||
            recCallType == 'IN' ||
            recCallType.startsWith('INC') ||
            lowerFileName.contains('incoming') ||
            lowerFileName.contains('inbound') ||
            lowerFileName.contains('call_in') ||
            lowerFileName.contains('_inc_') ||
            lowerFileName.contains('(in)');

        final bool isDefiniteOutgoing =
            !isDefiniteIncoming &&
            (callDetailsType == 'OUTGOING' ||
                callDetailsType == 'OUTBOUND' ||
                recCallType == 'OUTBOUND' ||
                recCallType == 'OUTGOING' ||
                recCallType == 'OUT' ||
                recCallType.startsWith('OUT') ||
                lowerFileName.contains('outgoing') ||
                lowerFileName.contains('outbound') ||
                lowerFileName.contains('call_out') ||
                lowerFileName.contains('_outg_') ||
                lowerFileName.contains('(out)'));

        String targetBound;
        if (isDefiniteIncoming) {
          targetBound = 'IN';
        } else if (isDefiniteOutgoing) {
          targetBound = 'OUT';
        } else if (initialBound != null && initialBound.isNotEmpty) {
          targetBound = initialBound.toUpperCase().startsWith('IN')
              ? 'IN'
              : 'OUT';
        } else if (callTimestamp > 0 &&
            (fileTimestamp <= 0 ||
                (fileTimestamp - callTimestamp).abs() < 180000)) {
          targetBound = 'OUT';
        } else {
          targetBound = 'IN';
        }

        final meta = await buildAudioMetadata(
          filePath: path,
          phoneNumber: phoneNumber,
          bound: targetBound,
          callTimestamp: targetSearchTime,
          callDetails: callDetails,
          staffUserPhone: staffPhone,
          duration: localDurSec > 0 ? localDurSec.toString() : null,
        );

        debugPrint(
          'Auto-uploading call recording ($finalLength bytes): $path for leadId: $leadId with meta: $meta',
        );
        _currentlyUploadingPaths.add(path);
        _currentlyUploadingPaths.add(cleanName);

        // Uploading actual audio recording file — call was connected
        String callStatusFinal = 'CONNECTED';

        final repo = sl<LeadsRepository>();
        final result = await repo.uploadLeadAudio(
          leadId,
          path,
          bound: meta['bound'],
          startTime: meta['startTime'],
          endTime: meta['endTime'],
          from: meta['from'],
          to: meta['to'],
          duration: meta['duration'],
          callDate: meta['callDate'],
          callStatus: callStatusFinal,
        );

        result.fold(
          (failure) {
            debugPrint('Auto-upload failed for $path: ${failure.message}');
            _currentlyUploadingPaths.remove(path);
            _currentlyUploadingPaths.remove(cleanName);
          },
          (audio) async {
            debugPrint('Successfully uploaded recording: ${audio.id}');
            await _markAsUploaded(path, finalLength);

            final actualStartMs =
                (callDetails != null &&
                    (callDetails['startTime'] as int? ?? 0) > 0)
                ? (callDetails['startTime'] as int)
                : (callTimestamp > 0
                      ? callTimestamp
                      : (recording['timestamp'] as int? ?? 0));
            // Mark this call timestamp so Phase 2 knows audio was already uploaded
            if (actualStartMs > 0) {
              uploadedAudioTimestamps.add(actualStartMs);
              await _markCallBucketAsUploaded(
                phoneNumber,
                actualStartMs,
                targetBound,
              );
            }
            if (fileTimestamp > 0) {
              uploadedAudioTimestamps.add(fileTimestamp);
              await _markCallBucketAsUploaded(
                phoneNumber,
                fileTimestamp,
                targetBound,
              );
            }
            if (callTimestamp > 0) {
              uploadedAudioTimestamps.add(callTimestamp);
              await _markCallBucketAsUploaded(
                phoneNumber,
                callTimestamp,
                targetBound,
              );
            }
            if (callDetails != null) {
              final s = callDetails['startTime'] as int? ?? 0;
              final e = callDetails['endTime'] as int? ?? 0;
              if (s > 0) uploadedAudioTimestamps.add(s);
              if (e > 0) uploadedAudioTimestamps.add(e);
            }
            await CallHistoryStorage.markCallAsSynced(
              phoneNumber,
              actualStartMs,
            );

            _currentlyUploadingPaths.remove(path);
            _currentlyUploadingPaths.remove(cleanName);
            serverAudios.add(audio);
            uploadedAny = true;
            _recordCallUploaded(phoneNumber, bound: targetBound, leadId: leadId, timestampMs: actualStartMs);
          },
        );
      }

      // ─── Phase 2: Scan & Upload Call Logs (No Audio File) ───
      final sevenDaysAgo =
          DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);
      final systemCallLogs = await service.getSystemCallLogs(phoneNumber);
      final trackedCallHistory = await CallHistoryStorage.loadCallHistory();

      final leadPhoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
      final leadLast10 = leadPhoneDigits.length >= 10
          ? leadPhoneDigits.substring(leadPhoneDigits.length - 10)
          : leadPhoneDigits;

      final List<Map<String, dynamic>> rawCalls = [];

      // Only include system call logs from the last 7 days to avoid old history polluting dedup
      for (final log in systemCallLogs) {
        final logPhone = log['phoneNumber']?.toString() ?? '';
        if (logPhone.isNotEmpty &&
            await StaffPersonalNumbersRepositoryImpl.isNumberBlocked(
              logPhone,
            )) {
          continue;
        }
        final st = log['startTime'] as int? ?? 0;
        if (st > 0 && st >= sevenDaysAgo) rawCalls.add(log);
      }

      for (final h in trackedCallHistory) {
        if (await StaffPersonalNumbersRepositoryImpl.isNumberBlocked(
          h.phoneNumber,
        )) {
          continue;
        }
        final hPhoneDigits = h.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final hLast10 = hPhoneDigits.length >= 10
            ? hPhoneDigits.substring(hPhoneDigits.length - 10)
            : hPhoneDigits;
        if (leadLast10.isNotEmpty &&
            (hLast10 == leadLast10 || hPhoneDigits.contains(leadLast10))) {
          final hSt = h.startTime > 0 ? h.startTime : h.timestamp;
          final isRecentPlaceholder = h.callType.toUpperCase() == 'OUTGOING' &&
              h.durationSeconds == 0 &&
              h.callStatus.toUpperCase() == 'NOT_CONNECTED' &&
              (DateTime.now().millisecondsSinceEpoch - hSt) < 120000;
          if (isRecentPlaceholder) continue;

          if (hSt >= sevenDaysAgo) {
            rawCalls.add({
              'id': h.id,
              'phoneNumber': h.phoneNumber,
              'startTime': hSt,
              'endTime': h.endTime > 0 ? h.endTime : hSt,
              'durationSeconds': h.durationSeconds,
              'callType': h.callType,
              'callStatus': h.callStatus,
            });
          }
        }
      }

      // Deduplicate raw calls:
      //  - Same call direction (IN vs OUT)
      //  - startTime within 30 seconds of each other
      // This is tight enough to avoid merging distinct back-to-back calls
      // but still collapses system-log + tracked-history duplicates for the SAME call.
      final List<Map<String, dynamic>> allUnuploadedCalls = [];
      for (final call in rawCalls) {
        final st = call['startTime'] as int? ?? 0;
        if (st <= 0) continue;
        final dur = call['durationSeconds'] as int? ?? 0;
        final callTypeRaw = (call['callType'] as String? ?? '').toUpperCase();
        final isCallIncoming =
            callTypeRaw == 'INCOMING' ||
            callTypeRaw == 'INBOUND' ||
            callTypeRaw == 'MISSED' ||
            callTypeRaw == 'REJECTED' ||
            (call['callStatus'] as String? ?? '').toUpperCase() == 'MISSED';

        bool isDuplicate = false;
        for (int i = 0; i < allUnuploadedCalls.length; i++) {
          final existingSt = allUnuploadedCalls[i]['startTime'] as int? ?? 0;
          final existingTypeRaw =
              (allUnuploadedCalls[i]['callType'] as String? ?? '')
                  .toUpperCase();
          final isExistingIncoming =
              existingTypeRaw == 'INCOMING' ||
              existingTypeRaw == 'INBOUND' ||
              existingTypeRaw == 'MISSED' ||
              existingTypeRaw == 'REJECTED' ||
              (allUnuploadedCalls[i]['callStatus'] as String? ?? '')
                      .toUpperCase() ==
                  'MISSED';

          // Merge if SAME direction OR if both are 0-second unanswered attempts at the same time,
          // but ONLY if within jitter (20s for outgoing, 3.5s for incoming) and NOT both having positive duration.
          final sameDirection = isCallIncoming == isExistingIncoming;
          final existingDur =
              allUnuploadedCalls[i]['durationSeconds'] as int? ?? 0;
          final isBothUnanswered = (dur == 0 && existingDur == 0);
          final maxDiff = (!isCallIncoming && !isExistingIncoming) ? 20000 : 3500;
          final isNearInTime = (st - existingSt).abs() < maxDiff;

          final shouldMerge = (!isCallIncoming && !isExistingIncoming && isNearInTime) ||
              ((sameDirection || isBothUnanswered) && isNearInTime && !(dur > 0 && existingDur > 0));

          if (shouldMerge) {
            final newStatus = (call['callStatus'] as String? ?? '')
                .toUpperCase();
            final existingStatus =
                (allUnuploadedCalls[i]['callStatus'] as String? ?? '')
                    .toUpperCase();
            final newIsAnswered =
                newStatus == 'ANSWERED' || newStatus == 'CONNECTED';
            final existingIsAnswered =
                existingStatus == 'ANSWERED' || existingStatus == 'CONNECTED';

            if (dur >= existingDur ||
                (newIsAnswered && !existingIsAnswered) ||
                (isCallIncoming && !isExistingIncoming)) {
              allUnuploadedCalls[i] = call;
            }
            isDuplicate = true;
            break;
          }
        }
        if (!isDuplicate) {
          allUnuploadedCalls.add(call);
        }
      }

      int? minRemainingWaitMs;

      for (final callLog in allUnuploadedCalls) {
        final startTimeMs = callLog['startTime'] as int? ?? 0;
        if (startTimeMs <= 0) continue;

        final callDuration = callLog['durationSeconds'] as int? ?? 0;
        final callStatusRaw = (callLog['callStatus'] as String? ?? '')
            .toUpperCase();

        final callTypeRaw = (callLog['callType'] as String? ?? 'OUTGOING')
            .toUpperCase();
        final isIncoming =
            callTypeRaw == 'INCOMING' ||
            callTypeRaw == 'INBOUND' ||
            callTypeRaw == 'MISSED' ||
            callTypeRaw == 'REJECTED' ||
            callStatusRaw == 'MISSED';

        final boundStr = isIncoming ? 'IN' : 'OUT';
        final isConnectedCall = callDuration > 0 ||
            callStatusRaw == 'ANSWERED' ||
            callStatusRaw == 'CONNECTED';
        final callStatusStr = isConnectedCall
            ? 'CONNECTED'
            : (isIncoming ? 'MISSED' : 'NOT_CONNECTED');
        final durationStr = isConnectedCall
            ? (callDuration > 0 ? callDuration.toString() : '1')
            : '0';

        final startTimeBucket = (startTimeMs ~/ 3500) * 3500;
        final uniqueKey = 'calllog_${boundStr}_${callStatusStr}_${startTimeBucket}_$phoneNumber';
        final sessionKey = '${leadLast10}_${boundStr}_${callStatusStr}_$startTimeBucket';

        // 1. If audio was already uploaded for this call in Phase 1 or in past, skip it entirely.
        const audioTolerance = 45000;
        final isAudioAlreadyUploaded = isConnectedCall && uploadedAudioTimestamps.any(
          (ts) => (ts - startTimeMs).abs() < audioTolerance || (ts - (startTimeMs + callDuration * 1000)).abs() < audioTolerance,
        );

        final hasServerAudio = isConnectedCall && serverAudios.any((sAudio) {
          final sBound = (sAudio.bound ?? '').toUpperCase();
          if (sBound.isNotEmpty && !checkBoundMatch(boundStr, sBound)) return false;
          final parsedTime = parseTimestampFromFileName(sAudio.displayName);
          final sAudioStartDt = parseCallDateTime(sAudio.callDate, sAudio.startTimeStr, sAudio.createdAt?.toIso8601String());
          final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
          final audioMs = (sAudioStartMs > 0) ? sAudioStartMs : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));
          return audioMs > 0 && (audioMs - startTimeMs).abs() < audioTolerance;
        });

        if (isAudioAlreadyUploaded || hasServerAudio) {
          debugPrint(
            'Phase 2: Audio already exists or uploaded for call at $startTimeMs. Skipping call-log-only post.',
          );
          await _markAsUploaded(uniqueKey, 0);
          await _markCallBucketAsUploaded(phoneNumber, startTimeMs, boundStr, callStatusStr);
          continue;
        }

        // 2. Check if an audio recording exists on device for this call
        final hasAudioOnDevice = isConnectedCall && allRecordings.any((rec) {
          final recTs = (rec['timestamp'] as num?)?.toInt() ?? 0;
          final recPath = rec['path'] as String? ?? '';
          final recFileTs = parseTimestampFromFileName(recPath.split('/').last) ?? recTs;
          final diffStart = (recFileTs - startTimeMs).abs();
          final diffEnd = (recFileTs - (startTimeMs + callDuration * 1000)).abs();
          return diffStart < audioTolerance || diffEnd < audioTolerance;
        });
        if (hasAudioOnDevice) {
          debugPrint(
            'Phase 2: Audio recording exists on device for call at $startTimeMs. Skipping call-log-only post.',
          );
          await _markAsUploaded(uniqueKey, 0);
          await _markCallBucketAsUploaded(phoneNumber, startTimeMs, boundStr, callStatusStr);
          continue;
        }

        final callEndMs = (callLog['endTime'] as int? ?? 0) > 0
            ? (callLog['endTime'] as int)
            : (startTimeMs + callDuration * 1000);
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final msSinceCallEnd = nowMs - callEndMs;
        final msSinceCallStart = nowMs - startTimeMs;

        // Grace period: Wait 5s for connected calls to allow audio file to be written to disk.
        // For missed/unanswered calls (0 duration), no audio file is ever created, upload immediately with 0ms wait.
        final neededGraceMs = isConnectedCall ? 5000 : 0;
        if (neededGraceMs > 0 && (msSinceCallEnd < neededGraceMs || msSinceCallStart < neededGraceMs)) {
          final effectiveElapsed = msSinceCallEnd < msSinceCallStart
              ? msSinceCallEnd
              : msSinceCallStart;
          final waitMs = neededGraceMs - effectiveElapsed;
          if (minRemainingWaitMs == null || waitMs < minRemainingWaitMs) {
            minRemainingWaitMs = waitMs;
          }
          debugPrint(
            'Phase 2: Call at $startTimeMs is too recent (${msSinceCallEnd}ms since end). Waiting before fallback upload.',
          );
          continue;
        }

        // Session-level guard: prevents posting the same call twice
        if (_sessionUploadedKeys.contains(sessionKey) ||
            _sessionUploadedKeys.contains(uniqueKey)) {
          debugPrint(
            'Phase 2: Session guard hit for $sessionKey — skipping duplicate.',
          );
          continue;
        }

        if (_currentlyUploadingPaths.contains(uniqueKey)) continue;

        if (await isAlreadyUploaded(
          uniqueKey,
          0,
          existingServerAudios: serverAudios,
        )) {
          continue;
        }

        if (await isCallAlreadyUploaded(
          phone: phoneNumber,
          timestampMs: startTimeMs,
          bound: boundStr,
          callStatus: callStatusStr,
          existingServerAudios: serverAudios,
          existingServerCallLogs: serverCallLogs,
        )) {
          debugPrint(
            'Phase 2: Call at $startTimeMs already uploaded to backend, skipping duplicate.',
          );
          continue;
        }

        bool alreadySyncedInHistory = false;

        // 1. Check serverCallLogs
        if (serverCallLogs.isNotEmpty) {
          for (final sLog in serverCallLogs) {
            final sBoundUpper = sLog.bound.toUpperCase();
            final matchesBound =
                (isIncoming &&
                    (sBoundUpper == 'IN' || sBoundUpper.startsWith('INC'))) ||
                (!isIncoming &&
                    (sBoundUpper == 'OUT' || sBoundUpper.startsWith('OUT')));
            if (!matchesBound) continue;

            final sDt = parseCallDateTime(
              sLog.callDate,
              sLog.startTime,
              sLog.createdAt,
            );
            if (sDt != null) {
              final sMs = sDt.millisecondsSinceEpoch;
              const maxTolerance = 45000;
              final isSameCallStatus =
                  sLog.callStatus.toUpperCase() == callStatusStr.toUpperCase() ||
                  (sLog.callStatus.toUpperCase().contains('CONN') && callStatusStr.toUpperCase().contains('ANS')) ||
                  (sLog.callStatus.toUpperCase().contains('ANS') && callStatusStr.toUpperCase().contains('CONN'));
              final bool isMatch = isSameCallStatus && (sMs - startTimeMs).abs() < maxTolerance;
              if (isMatch) {
                alreadySyncedInHistory = true;
                break;
              }
            }
          }
        }

        // 2. Check serverAudios (only for connected calls, as missed calls never have audio files)
        if (!alreadySyncedInHistory && isConnectedCall && serverAudios.isNotEmpty) {
          const maxTolerance = 45000;
          for (final sAudio in serverAudios) {
            final parsedTime = parseTimestampFromFileName(sAudio.displayName);
            final sAudioStartDt = parseCallDateTime(sAudio.callDate, sAudio.startTimeStr, sAudio.createdAt?.toIso8601String());
            final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
            final audioMs = (sAudioStartMs > 0) ? sAudioStartMs : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));

            final bool isMatch = (sAudioStartMs > 0 && (sAudioStartMs - startTimeMs).abs() < maxTolerance) ||
                (parsedTime != null && (parsedTime - startTimeMs).abs() < maxTolerance) ||
                (audioMs > 0 && (audioMs - startTimeMs).abs() < maxTolerance);
            if (isMatch) {
              final sBoundUpper = (sAudio.bound ?? '').toUpperCase();
              final matchesBound =
                  sBoundUpper.isEmpty ||
                  checkBoundMatch(boundStr, sBoundUpper);
              if (matchesBound) {
                alreadySyncedInHistory = true;
                break;
              }
            }
          }
        }

        if (alreadySyncedInHistory) {
          await _markAsUploaded(uniqueKey, 0);
          await _markCallBucketAsUploaded(phoneNumber, startTimeMs, boundStr);
          _sessionUploadedKeys.add(sessionKey);
          _sessionUploadedKeys.add(uniqueKey);
          debugPrint(
            'Phase 2: Call at $startTimeMs was already synced. Skipping dummy upload.',
          );
          continue;
        }

        final endTimeMs = callLog['endTime'] as int? ?? startTimeMs;
        final dt = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
        final dateStr = DateFormat('yyyy-MM-dd').format(dt);
        final startTimeStr = DateFormat('HH:mm:ss').format(dt);
        final endDt = DateTime.fromMillisecondsSinceEpoch(
          endTimeMs > 0 ? endTimeMs : startTimeMs,
        );
        final endTimeStr = DateFormat('HH:mm:ss').format(endDt);

        String effectiveStaffPhone = staffPhone;
        try {
          final freshPrefs = await SharedPreferences.getInstance();
          if (effectiveStaffPhone.isEmpty) {
            effectiveStaffPhone =
                freshPrefs.getString('userPhone')?.trim() ?? '';
          }
        } catch (_) {}

        if (effectiveStaffPhone.isEmpty) {
          try {
            effectiveStaffPhone = await CallRecordingService()
                .getDevicePhoneNumber();
          } catch (_) {}
        }

        if (effectiveStaffPhone.isEmpty) {
          try {
            effectiveStaffPhone =
                await StaffPhoneResolver.getOrFetchStaffPhone();
          } catch (_) {}
        }
        if (effectiveStaffPhone.isEmpty) {
          effectiveStaffPhone = 'Staff';
        }

        final String fromNum;
        final String toNum;
        if (isIncoming) {
          fromNum = phoneNumber.isNotEmpty ? phoneNumber : 'Lead';
          toNum = effectiveStaffPhone;
        } else {
          fromNum = effectiveStaffPhone;
          toNum = phoneNumber.isNotEmpty ? phoneNumber : 'Lead';
        }

        if (_isCallRecentlyUploaded(phoneNumber, bound: boundStr, leadId: leadId, timestampMs: startTimeMs)) {
          debugPrint(
            'Phase 2: Call was recently uploaded for $leadId ($phoneNumber). Suppressing duplicate call log upload.',
          );
          await _markAsUploaded(uniqueKey, 0);
          await _markCallBucketAsUploaded(phoneNumber, startTimeMs, boundStr, callStatusStr);
          continue;
        }

        debugPrint(
          'Auto-uploading call log only ($boundStr, status=$callStatusStr, duration=${durationStr}s) for leadId: $leadId at $startTimeStr',
        );
        // Register session key BEFORE upload to block concurrent duplicate uploads
        // from the rapid burst (300ms / 1500ms / 3500ms re-scans).
        _sessionUploadedKeys.add(sessionKey);
        _currentlyUploadingPaths.add(uniqueKey);

        final repo = sl<LeadsRepository>();
        final result = await repo.uploadLeadAudio(
          leadId,
          null, // null audio file — sending call log metadata only
          bound: boundStr,
          startTime: startTimeStr,
          endTime: endTimeStr,
          from: fromNum,
          to: toNum,
          duration: durationStr,
          callDate: dateStr,
          callStatus: callStatusStr,
        );

        result.fold(
          (failure) {
            debugPrint('Auto-upload call metadata failed: ${failure.message}');
            // On failure, remove session key so a retry on next scan is allowed
            _sessionUploadedKeys.remove(sessionKey);
            _currentlyUploadingPaths.remove(uniqueKey);
            _uploadedPaths.remove(uniqueKey);
            _uploadedPaths.remove('${uniqueKey}_0');
          },
          (audio) async {
            debugPrint('Successfully uploaded call log metadata: ${audio.id}');
            await _markAsUploaded(uniqueKey, 0);
            await _markCallBucketAsUploaded(phoneNumber, startTimeMs, boundStr, callStatusStr);
            _sessionUploadedKeys.add(sessionKey);
            _sessionUploadedKeys.add(uniqueKey);
            await CallHistoryStorage.markCallAsSynced(phoneNumber, startTimeMs);
            _currentlyUploadingPaths.remove(uniqueKey);
            serverAudios.add(audio);
            uploadedAny = true;
            _recordCallUploaded(phoneNumber, bound: boundStr, leadId: leadId, timestampMs: startTimeMs);
          },
        );
      }

      if (minRemainingWaitMs != null && minRemainingWaitMs > 0) {
        Future.delayed(Duration(milliseconds: minRemainingWaitMs + 300), () {
          autoScanAndUploadLeadRecordings(
            context: null,
            leadId: leadId,
            phoneNumber: phoneNumber,
            callTimestamp: callTimestamp,
            initialBound: initialBound,
            existingServerAudios: existingServerAudios,
            existingServerCallLogs: existingServerCallLogs,
            onUploadSuccess: onUploadSuccess,
          );
        });
      }

      if (uploadedAny && onUploadSuccess != null) {
        onUploadSuccess();
      }
    } catch (e) {
      debugPrint('Error in autoScanAndUploadLeadRecordings: $e');
      if (onUploadSuccess != null) {
        onUploadSuccess();
      }
    } finally {
      _activeScanningLeads.remove(leadId);
      if (_queuedScanningLeads.remove(leadId)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          autoScanAndUploadLeadRecordings(
            context: null,
            leadId: leadId,
            phoneNumber: phoneNumber,
            onUploadSuccess: onUploadSuccess,
          );
        });
      }
    }
  }

  static bool checkBoundMatch(String b1, String b2) {
    final norm1 = b1.trim().toUpperCase();
    final norm2 = b2.trim().toUpperCase();
    if (norm1.isEmpty || norm2.isEmpty) return true;
    final isB1In =
        norm1 == 'IN' ||
        norm1 == 'INBOUND' ||
        norm1 == 'INCOMING' ||
        norm1.startsWith('INC') ||
        norm1.startsWith('INB');
    final isB1Out =
        norm1 == 'OUT' ||
        norm1 == 'OUTBOUND' ||
        norm1 == 'OUTGOING' ||
        norm1.startsWith('OUT');
    final isB2In =
        norm2 == 'IN' ||
        norm2 == 'INBOUND' ||
        norm2 == 'INCOMING' ||
        norm2.startsWith('INC') ||
        norm2.startsWith('INB');
    final isB2Out =
        norm2 == 'OUT' ||
        norm2 == 'OUTBOUND' ||
        norm2 == 'OUTGOING' ||
        norm2.startsWith('OUT');

    if (isB1In && isB2In) return true;
    if (isB1Out && isB2Out) return true;
    return false;
  }

  static int? parseTimestampFromFileName(String fileName) {
    try {
      // 1. Try parsing directly from raw fileName FIRST (handles filenames like 8220021569(8220021569)_20260921131348.mp3)
      final rawMatch1 = RegExp(
        r'(?:^|[^0-9])(20[2-3]\d)[-_]?(\d{2})[-_]?(\d{2})[-_._]?(\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?:$|[^0-9])',
      ).firstMatch(fileName);
      if (rawMatch1 != null) {
        final yyyy = int.parse(rawMatch1.group(1)!);
        final mm = int.parse(rawMatch1.group(2)!);
        final dd = int.parse(rawMatch1.group(3)!);
        final hh = int.parse(rawMatch1.group(4)!);
        final mi = int.parse(rawMatch1.group(5)!);
        final ss = int.parse(rawMatch1.group(6)!);
        if (mm >= 1 &&
            mm <= 12 &&
            dd >= 1 &&
            dd <= 31 &&
            hh >= 0 &&
            hh <= 23 &&
            mi >= 0 &&
            mi <= 59 &&
            ss >= 0 &&
            ss <= 59) {
          return DateTime(yyyy, mm, dd, hh, mi, ss).millisecondsSinceEpoch;
        }
      }

      final cleanName = cleanFileName(fileName);

      // Pattern 1: YYYYMMDD_HHMMSS or YYYYMMDDHHMMSS (e.g. 20260911_110844, 20260911110844)
      final p1 = RegExp(
        r'(?:^|[^0-9])(20[2-3]\d)[-_]?(\d{2})[-_]?(\d{2})[-_._]?(\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?:$|[^0-9])',
      ).firstMatch(cleanName);
      if (p1 != null) {
        final yyyy = int.parse(p1.group(1)!);
        final mm = int.parse(p1.group(2)!);
        final dd = int.parse(p1.group(3)!);
        final hh = int.parse(p1.group(4)!);
        final mi = int.parse(p1.group(5)!);
        final ss = int.parse(p1.group(6)!);
        if (mm >= 1 &&
            mm <= 12 &&
            dd >= 1 &&
            dd <= 31 &&
            hh >= 0 &&
            hh <= 23 &&
            mi >= 0 &&
            mi <= 59 &&
            ss >= 0 &&
            ss <= 59) {
          return DateTime(yyyy, mm, dd, hh, mi, ss).millisecondsSinceEpoch;
        }
      }

      // Pattern 2: Epoch timestamp in ms (13 digits)
      final p2 = RegExp(
        r'(?:^|[^0-9])(1\d{12})(?:$|[^0-9])',
      ).firstMatch(cleanName);
      if (p2 != null) {
        final val = int.tryParse(p2.group(1)!);
        if (val != null && val > 1500000000000 && val < 2500000000000) {
          return val;
        }
      }

      // Pattern 3: YYMMDD_HHMMSS (e.g. 260911_110844)
      final p3 = RegExp(
        r'(?:^|[^0-9])(\d{2})(\d{2})(\d{2})[-_]?(\d{2})(\d{2})(\d{2})(?:$|[^0-9])',
      ).firstMatch(cleanName);
      if (p3 != null) {
        final yy = int.parse(p3.group(1)!);
        final mm = int.parse(p3.group(2)!);
        final dd = int.parse(p3.group(3)!);
        final hh = int.parse(p3.group(4)!);
        final mi = int.parse(p3.group(5)!);
        final ss = int.parse(p3.group(6)!);
        final yyyy = 2000 + yy;
        if (yyyy >= 2020 &&
            yyyy <= 2040 &&
            mm >= 1 &&
            mm <= 12 &&
            dd >= 1 &&
            dd <= 31 &&
            hh >= 0 &&
            hh <= 23 &&
            mi >= 0 &&
            mi <= 59 &&
            ss >= 0 &&
            ss <= 59) {
          return DateTime(yyyy, mm, dd, hh, mi, ss).millisecondsSinceEpoch;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, String>> buildAudioMetadata({
    required String filePath,
    required String phoneNumber,
    String? bound,
    String? startTime,
    String? endTime,
    String? from,
    String? to,
    String? duration,
    String? callDate,
    int callTimestamp = 0,
    Map<String, dynamic>? callDetails,
    String? staffUserPhone,
  }) async {
    final Map<String, String> meta = {};
    final file = File(filePath);
    final fileName = filePath.split('/').last;
    final lowerName = fileName.toLowerCase();

    // 1. bound (IN or OUT)
    String resBound = bound ?? '';
    if (resBound.isNotEmpty) {
      final bUpper = resBound.trim().toUpperCase();
      if (bUpper == 'IN' || bUpper == 'INBOUND' || bUpper == 'INCOMING') {
        resBound = 'IN';
      } else if (bUpper == 'OUT' ||
          bUpper == 'OUTBOUND' ||
          bUpper == 'OUTGOING') {
        resBound = 'OUT';
      } else {
        resBound = '';
      }
    }

    // Concrete callDetails or filename incoming indicators override any assumed 'OUT'
    if (callDetails != null && callDetails['callType'] != null) {
      final ct = callDetails['callType'].toString().trim().toUpperCase();
      if (ct == 'INCOMING' || ct == 'INBOUND' || ct == 'MISSED') {
        resBound = 'IN';
      } else if (ct == 'OUTGOING' || ct == 'OUTBOUND') {
        if (resBound.isEmpty) resBound = 'OUT';
      }
    }

    if (lowerName.contains('inbound') ||
        lowerName.contains('incoming') ||
        lowerName.contains('call_in') ||
        lowerName.contains('_inc_') ||
        lowerName.contains('(in)')) {
      resBound = 'IN';
    } else if (lowerName.contains('outbound') ||
        lowerName.contains('outgoing') ||
        lowerName.contains('call_out') ||
        lowerName.contains('_outg_') ||
        lowerName.contains('(out)')) {
      if (resBound.isEmpty) resBound = 'OUT';
    }

    if (resBound.isEmpty) {
      try {
        final effectiveTime =
            parseTimestampFromFileName(fileName) ??
            (callTimestamp > 0 ? callTimestamp : 0);
        final detected = await CallRecordingService().detectCallType(
          filePath: filePath,
          fileName: fileName,
          phoneNumber: phoneNumber,
          timestamp: effectiveTime,
          callTimestamp: callTimestamp,
        );
        resBound =
            (detected.toLowerCase() == 'inbound' ||
                detected.toLowerCase() == 'incoming')
            ? 'IN'
            : 'OUT';
      } catch (_) {
        resBound = (callTimestamp > 0) ? 'OUT' : 'IN';
      }
    }
    meta['bound'] = resBound;

    // 2. Duration calculation (in seconds)
    int durSec = 0;
    if (duration != null && duration.isNotEmpty) {
      durSec = int.tryParse(duration) ?? 0;
    }
    if (durSec <= 0 &&
        callDetails != null &&
        (callDetails['durationSeconds'] as int? ?? 0) > 0) {
      durSec = callDetails['durationSeconds'] as int;
    }

    // 3. Start time & End time calculation (exact timestamps in ms)
    int? startMs;
    int? endMs;

    // First resolve the exact timestamp from the recording filename or callTimestamp
    int? fileStartMs = parseTimestampFromFileName(fileName);
    if ((fileStartMs == null || fileStartMs <= 0) && callTimestamp > 0) {
      fileStartMs = callTimestamp;
    }

    // Check System CallLog details ONLY if its startTime is within 2 minutes of fileStartMs (or if fileStartMs is unknown)
    if (callDetails != null) {
      final s = callDetails['startTime'] as int? ?? 0;
      final e = callDetails['endTime'] as int? ?? 0;
      final d = callDetails['durationSeconds'] as int? ?? 0;
      if (s > 0) {
        if (fileStartMs == null ||
            fileStartMs <= 0 ||
            (s - fileStartMs).abs() < 120000) {
          startMs = s;
          if (e > 0) endMs = e;
          if (durSec <= 0 && d > 0) durSec = d;
        } else {
          debugPrint(
            'callDetails startTime ($s) mismatched with file timestamp ($fileStartMs). Ignoring mismatched CallLog details.',
          );
        }
      }
    }

    // Priority 2: Use fileStartMs if startMs was not matched from callDetails
    if ((startMs == null || startMs <= 0) &&
        fileStartMs != null &&
        fileStartMs > 0) {
      startMs = fileStartMs;
    }

    // Priority 3: If startMs still unknown, calculate from file lastModified & duration
    if ((startMs == null || startMs <= 0) && file.existsSync()) {
      final lastMod = file.lastModifiedSync().millisecondsSinceEpoch;
      if (durSec > 0) {
        startMs = lastMod - (durSec * 1000);
        endMs ??= lastMod;
      } else {
        startMs = lastMod;
      }
    }

    // Priority 4: Fallback to callTimestamp if passed
    if ((startMs == null || startMs <= 0) && callTimestamp > 0) {
      startMs = callTimestamp;
    }

    // Final fallback to DateTime.now()
    startMs ??= DateTime.now().millisecondsSinceEpoch;

    // Calculate endMs: preserve callDetails.endTime if available and valid
    if (endMs == null || endMs <= startMs) {
      if (callDetails != null &&
          (callDetails['durationSeconds'] as int? ?? 0) > 0) {
        final callDurSec = callDetails['durationSeconds'] as int;
        endMs = startMs + (callDurSec * 1000);
      } else if (durSec > 0) {
        endMs = startMs + (durSec * 1000);
      } else if (file.existsSync()) {
        final lastMod = file.lastModifiedSync().millisecondsSinceEpoch;
        endMs = lastMod > startMs ? lastMod : startMs + 1000;
      } else {
        endMs = startMs + 1000;
      }
    }

    // Ensure endMs is strictly greater than startMs so startTime and endTime are never identical
    if (endMs <= startMs) {
      final addSec = durSec > 0 ? durSec : 1;
      endMs = startMs + (addSec * 1000);
    }

    if (durSec <= 0 && endMs > startMs) {
      durSec = (endMs - startMs) ~/ 1000;
    }

    final startDt = DateTime.fromMillisecondsSinceEpoch(startMs);
    final endDt = DateTime.fromMillisecondsSinceEpoch(endMs);

    meta['callDate'] = callDate ?? DateFormat('yyyy-MM-dd').format(startDt);
    meta['startTime'] = startTime ?? DateFormat('HH:mm:ss').format(startDt);
    meta['endTime'] = endTime ?? DateFormat('HH:mm:ss').format(endDt);
    meta['duration'] = durSec > 0 ? durSec.toString() : (duration ?? '0');

    // 4. from & to numbers calculation
    String userPhone = (staffUserPhone != null && staffUserPhone.isNotEmpty)
        ? staffUserPhone
        : '';

    try {
      final prefs = await SharedPreferences.getInstance();
      if (userPhone.isEmpty) {
        userPhone = prefs.getString('userPhone')?.trim() ?? '';
      }
      if (userPhone.isEmpty) {
        userPhone = prefs.getString('userName')?.trim() ?? '';
      }
    } catch (_) {}

    if (userPhone.isEmpty) {
      try {
        userPhone = await StaffPhoneResolver.getOrFetchStaffPhone();
      } catch (_) {}
    }

    if (userPhone.isEmpty) {
      try {
        userPhone = await CallRecordingService().getDevicePhoneNumber();
      } catch (_) {}
    }

    if (userPhone.isEmpty) {
      userPhone = 'Staff';
    }

    final String finalFrom;
    final String finalTo;

    if (resBound == 'IN') {
      finalFrom = (from != null && from.isNotEmpty) ? from : phoneNumber;
      finalTo = (to != null && to.isNotEmpty) ? to : userPhone;
    } else {
      finalFrom = (from != null && from.isNotEmpty) ? from : userPhone;
      finalTo = (to != null && to.isNotEmpty) ? to : phoneNumber;
    }

    meta['from'] = finalFrom;
    meta['to'] = finalTo;

    return meta;
  }
}
