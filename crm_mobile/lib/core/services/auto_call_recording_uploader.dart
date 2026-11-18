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

class _CachedPhoneLead {
  final String? leadId;
  final DateTime cachedAt;

  const _CachedPhoneLead({this.leadId, required this.cachedAt});
}

class _CachedLeadPhones {
  final String? primaryPhone;
  final String? alternatePhone;
  final List<String> extraPhones;
  final bool hasDetailResolution;
  final DateTime cachedAt;

  const _CachedLeadPhones({
    this.primaryPhone,
    this.alternatePhone,
    this.extraPhones = const [],
    this.hasDetailResolution = false,
    required this.cachedAt,
  });

  List<String> get allPhones {
    final seen = <String>{};
    final result = <String>[];
    for (final candidate in [primaryPhone, alternatePhone, ...extraPhones]) {
      final clean = (candidate ?? '').trim();
      if (clean.isEmpty || clean == '-') continue;
      final digits = clean.replaceAll(RegExp(r'\D'), '');
      final key = digits.length >= 10
          ? digits.substring(digits.length - 10)
          : digits;
      if (key.length >= 3 && seen.add(key)) {
        result.add(clean);
      }
    }
    return result;
  }
}

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
  static final Map<String, _CachedPhoneLead> _phoneLeadCache = {};
  static final Map<String, _CachedLeadPhones> _leadPhonesCache = {};
  static final Map<String, Future<String?>> _inFlightPhoneLookups = {};
  static DateTime? _lastPassiveSyncCompletedAt;
  static String _lastObservedCallFingerprint = '';
  static const Duration _passiveSyncCooldown = Duration(seconds: 60);
  static const Duration _phoneLookupCacheTtl = Duration(minutes: 15);

  static bool _isConnectedStatus(String? status) {
    final s = (status ?? '').trim().toUpperCase();
    return s == 'CONNECTED' || s == 'ANSWERED';
  }

  static int _parseDurationSecondsRaw(String? durStr) {
    if (durStr == null) return 0;
    final clean = durStr.trim();
    if (clean.isEmpty || clean == 'null' || clean == '--:--') return 0;
    if (clean.contains(':')) {
      final parts = clean
          .split(':')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^\d]'), '')) ?? 0)
          .toList();
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
      if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      }
    }
    return int.tryParse(clean.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
  }

  static const int _callMatchJitterMs = 3000;
  static const int _callBucketSizeMs = 1000;

  static bool _isTimestampInCallInterval(
    int targetMs,
    int intervalStartMs,
    int intervalEndMs, {
    int padBeforeMs = _callMatchJitterMs,
    int padAfterMs = _callMatchJitterMs,
  }) {
    if (targetMs <= 0 || intervalStartMs <= 0) return false;
    final effectiveEnd = intervalEndMs > intervalStartMs
        ? intervalEndMs
        : intervalStartMs;
    return targetMs >= (intervalStartMs - padBeforeMs) &&
        targetMs <= (effectiveEnd + padAfterMs);
  }

  static bool _intervalsOverlap(
    int aStartMs,
    int aEndMs,
    int bStartMs,
    int bEndMs, {
    int padBeforeMs = _callMatchJitterMs,
    int padAfterMs = _callMatchJitterMs,
  }) {
    return _isTimestampInCallInterval(
          aStartMs,
          bStartMs,
          bEndMs,
          padBeforeMs: padBeforeMs,
          padAfterMs: padAfterMs,
        ) ||
        _isTimestampInCallInterval(
          bStartMs,
          aStartMs,
          aEndMs,
          padBeforeMs: padBeforeMs,
          padAfterMs: padAfterMs,
        );
  }

  static String usablePhoneDigits(String? rawPhone) {
    final trimmed = (rawPhone ?? '').trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower == '-' ||
        lower == 'n/a' ||
        lower == 'null' ||
        lower == 'none' ||
        lower == 'not specified') {
      return '';
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 ? digits : '';
  }

  static bool isUsablePhone(String? rawPhone) =>
      usablePhoneDigits(rawPhone).isNotEmpty;

  static bool phonesMatch(String? phoneA, String? phoneB) {
    final digitsA = usablePhoneDigits(phoneA);
    final digitsB = usablePhoneDigits(phoneB);
    if (digitsA.isEmpty || digitsB.isEmpty) return false;
    final lastA = digitsA.length >= 10
        ? digitsA.substring(digitsA.length - 10)
        : digitsA;
    final lastB = digitsB.length >= 10
        ? digitsB.substring(digitsB.length - 10)
        : digitsB;
    if (lastA.length >= 10 && lastB.length >= 10) return lastA == lastB;
    return lastA == lastB ||
        digitsA.endsWith(lastB) ||
        digitsB.endsWith(lastA);
  }

  static bool hasConflictingPhoneInFileName(
    String fileName,
    String targetPhone,
  ) {
    if (!isUsablePhone(targetPhone)) return false;
    var sanitized = fileName.replaceAll(
      RegExp(r'\.?pending[-_]?[a-zA-Z0-9]*[-_]?', caseSensitive: false),
      '',
    );
    sanitized = sanitized
        .replaceAll(RegExp(r'(?:^|\D)20[2-3]\d{10}(?:\D|$)'), ' ')
        .replaceAll(RegExp(r'(?:^|\D)1[6-9]\d{11,12}(?:\D|$)'), ' ');
    for (final m in RegExp(r'\d{10,15}').allMatches(sanitized)) {
      final chunk = m.group(0)!;
      if (chunk.length == 14 &&
          (chunk.startsWith('202') || chunk.startsWith('203'))) {
        continue;
      }
      if (chunk.length == 13 && chunk.startsWith('1')) continue;
      if (!phonesMatch(chunk, targetPhone)) return true;
    }
    return false;
  }

  static String _normalizePhoneCacheKey(String phone) {
    final digits = usablePhoneDigits(phone);
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  static String _extractPrimaryPhoneDynamic(dynamic item) {
    try {
      final direct = item.phone?.toString().trim() ?? '';
      if (direct.isNotEmpty && direct != '-') return direct;
    } catch (_) {}
    try {
      final phoneNum = item.phoneNumber?.toString().trim() ?? '';
      if (phoneNum.isNotEmpty && phoneNum != '-') return phoneNum;
    } catch (_) {}
    return '';
  }

  static String _extractAlternatePhoneDynamic(dynamic item) {
    try {
      final alt = item.alternatePhone?.toString().trim() ?? '';
      if (alt.isNotEmpty && alt != '-') return alt;
    } catch (_) {}
    return '';
  }

  static List<String> _extractExtraPhonesDynamic(dynamic item) {
    final extras = <String>[];
    try {
      final customFields = item.customFields;
      if (customFields is Iterable) {
        for (final cf in customFields) {
          final val = (cf.value ?? '').toString().trim();
          if (val.isEmpty || val == '-') continue;
          final type = cf.fieldType.toString().toLowerCase();
          final name = cf.fieldName.toString().toLowerCase();
          final label = cf.label.toString().toLowerCase();
          if (type == 'phone' ||
              type == 'mobile' ||
              type == 'tel' ||
              name.contains('phone') ||
              name.contains('mobile') ||
              label.contains('phone') ||
              label.contains('mobile')) {
            extras.add(val);
          }
        }
      }
    } catch (_) {}
    return extras;
  }

  static bool _isDetailLeadDynamic(dynamic item) {
    try {
      final _ = item.customFields;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Registers phone numbers for a lead ID in memory for lookup & call confirmation.
  static void registerLeadPhones({
    required String leadId,
    String? primaryPhone,
    String? alternatePhone,
    Iterable<String> extraPhones = const [],
    bool hasDetailResolution = false,
  }) {
    final id = leadId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now();

    final existing = _leadPhonesCache[id];
    final validExisting =
        existing != null &&
        now.difference(existing.cachedAt) < _phoneLookupCacheTtl;

    String? pickNonEmpty(String? next, String? prev) {
      final n = (next ?? '').trim();
      if (n.isNotEmpty && n != '-') return n;
      final p = (prev ?? '').trim();
      return (p.isNotEmpty && p != '-') ? p : null;
    }

    final mergedPrimary = pickNonEmpty(
      primaryPhone,
      validExisting ? existing.primaryPhone : null,
    );
    final mergedAlternate = pickNonEmpty(
      alternatePhone,
      validExisting ? existing.alternatePhone : null,
    );
    final mergedExtras = <String>[
      if (validExisting) ...existing.extraPhones,
      ...extraPhones.map((e) => e.trim()).where((e) => e.isNotEmpty && e != '-'),
    ];

    final entry = _CachedLeadPhones(
      primaryPhone: mergedPrimary,
      alternatePhone: mergedAlternate,
      extraPhones: mergedExtras,
      hasDetailResolution:
          (validExisting && existing.hasDetailResolution) || hasDetailResolution,
      cachedAt: now,
    );
    _leadPhonesCache[id] = entry;

    for (final p in entry.allPhones) {
      final key = _normalizePhoneCacheKey(p);
      if (key.length >= 7) {
        _phoneLeadCache[key] = _CachedPhoneLead(leadId: id, cachedAt: now);
      }
    }
  }

  /// Returns cached phone numbers for [leadId] (primary, alternate, extras), if fresh.
  static List<String> getCachedLeadPhones(String leadId) {
    final id = leadId.trim();
    if (id.isEmpty) return const [];
    final cached = _leadPhonesCache[id];
    if (cached == null) return const [];
    if (DateTime.now().difference(cached.cachedAt) >= _phoneLookupCacheTtl) {
      return const [];
    }
    return cached.allPhones;
  }

  /// Returns structured cached phones `(primaryPhone, alternatePhone, extraPhones)` if fresh.
  static ({String? primaryPhone, String? alternatePhone, List<String> extraPhones})?
  getCachedLeadPhoneRecord(String leadId) {
    final id = leadId.trim();
    if (id.isEmpty) return null;
    final cached = _leadPhonesCache[id];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.cachedAt) >= _phoneLookupCacheTtl) {
      return null;
    }
    return (
      primaryPhone: cached.primaryPhone,
      alternatePhone: cached.alternatePhone,
      extraPhones: cached.extraPhones,
    );
  }

  /// Returns true if full LeadDetail phones have already been resolved for [leadId].
  static bool hasResolvedLeadDetailPhones(String leadId) {
    final id = leadId.trim();
    if (id.isEmpty) return false;
    final cached = _leadPhonesCache[id];
    if (cached == null) return false;
    if (DateTime.now().difference(cached.cachedAt) >= _phoneLookupCacheTtl) {
      return false;
    }
    return cached.hasDetailResolution;
  }

  /// Registers already-loaded CRM leads in memory so background call sync
  /// does not query `/leads/search/number` unnecessarily for known numbers.
  static void registerKnownLeads(Iterable<dynamic> leads) {
    for (final dynamic item in leads) {
      try {
        final id = item.id?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final primary = _extractPrimaryPhoneDynamic(item);
        final alt = _extractAlternatePhoneDynamic(item);
        final extras = _extractExtraPhonesDynamic(item);
        if (primary.isEmpty && alt.isEmpty && extras.isEmpty) {
          if (_isDetailLeadDynamic(item)) {
            registerLeadPhones(leadId: id, hasDetailResolution: true);
          }
          continue;
        }
        registerLeadPhones(
          leadId: id,
          primaryPhone: primary,
          alternatePhone: alt,
          extraPhones: extras,
          hasDetailResolution: _isDetailLeadDynamic(item),
        );
      } catch (_) {}
    }
  }

  /// Clears cached phone->lead lookups (e.g., after creating or editing a lead).
  static void invalidatePhoneLookupCache([String? phone]) {
    if (phone == null || phone.trim().isEmpty) {
      _phoneLeadCache.clear();
      _leadPhonesCache.clear();
      return;
    }
    final key = _normalizePhoneCacheKey(phone);
    _phoneLeadCache.remove(key);
    _phoneLeadCache.remove(phone.trim());
  }

  @visibleForTesting
  static void resetCallDedupStateForTesting() {
    _uploadedPaths.clear();
    _sessionUploadedKeys.clear();
    _recentCallUploads.clear();
    _recentCallEndedMs.clear();
    _lastAnyCallEndedMs = 0;
    _prefsLoaded = false;
  }

  @visibleForTesting
  static Future<void> markCallBucketUploadedForTesting({
    required String phone,
    required int timestampMs,
    String? bound,
    String? callStatus,
  }) => _markCallBucketAsUploaded(phone, timestampMs, bound, callStatus);

  @visibleForTesting
  static bool isCallRecentlyUploadedForTesting(
    String phone, {
    String? bound,
    String? leadId,
    int? timestampMs,
    String? callStatus,
  }) => _isCallRecentlyUploaded(
    phone,
    bound: bound,
    leadId: leadId,
    timestampMs: timestampMs,
    callStatus: callStatus,
  );

  static Future<String?> _resolveLeadIdByPhone({
    required String rawPhone,
    required String last10,
    List<dynamic>? knownLeads,
  }) async {
    if (!isUsablePhone(rawPhone) && !isUsablePhone(last10)) return null;
    final normKey = _normalizePhoneCacheKey(isUsablePhone(rawPhone) ? rawPhone : last10);
    if (normKey.isEmpty) return null;

    if (knownLeads != null && knownLeads.isNotEmpty) {
      registerKnownLeads(knownLeads);
      for (final dynamic item in knownLeads) {
        final id = item.id?.toString();
        if (id == null || id.isEmpty) continue;
        final candidates = [
          _extractPrimaryPhoneDynamic(item),
          _extractAlternatePhoneDynamic(item),
          ..._extractExtraPhonesDynamic(item),
        ];
        for (final p in candidates) {
          if (phonesMatch(p, rawPhone) || phonesMatch(p, last10)) {
            return id;
          }
        }
      }
    }

    final cacheKey = normKey;
    final now = DateTime.now();
    final cached = _phoneLeadCache[cacheKey];
    if (cached != null && now.difference(cached.cachedAt) < _phoneLookupCacheTtl) {
      return cached.leadId;
    }

    final existingInFlight = _inFlightPhoneLookups[cacheKey];
    if (existingInFlight != null) {
      return existingInFlight;
    }

    final future = () async {
      String? resolvedId;
      bool hadNetworkSuccess = false;
      final repo = sl<LeadsRepository>();

      if (isUsablePhone(last10)) {
        final res = await repo.searchLeadByNumber(last10);
        res.fold((_) {}, (r) {
          hadNetworkSuccess = true;
          if (r.leadId != null && r.leadId!.isNotEmpty) {
            resolvedId = r.leadId;
          }
        });
      }

      if ((resolvedId == null || resolvedId!.isEmpty) &&
          isUsablePhone(rawPhone) &&
          rawPhone.trim() != last10) {
        final res = await repo.searchLeadByNumber(rawPhone.trim());
        res.fold((_) {}, (r) {
          hadNetworkSuccess = true;
          if (r.leadId != null && r.leadId!.isNotEmpty) {
            resolvedId = r.leadId;
          }
        });
      }

      if (hadNetworkSuccess) {
        _phoneLeadCache[cacheKey] = _CachedPhoneLead(
          leadId: resolvedId,
          cachedAt: DateTime.now(),
        );
      }
      return resolvedId;
    }();

    _inFlightPhoneLookups[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightPhoneLookups.remove(cacheKey);
    }
  }

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
          final skipRealAudio =
              isMissedCallKey || path.toUpperCase().contains('_MISSED_');
          if (ts > 0) {
            for (final sAudio in existingServerAudios) {
              if (sAudio.size > 0 && skipRealAudio) {
                continue; // For missed call, skip real audio files
              }

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
                  if ((audioMs - ts).abs() <= _callMatchJitterMs) {
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
  static final Map<String, List<Map<String, dynamic>>> _recentCallUploads = {};
  static final Map<String, int> _recentCallEndedMs = {};
  static int _lastAnyCallEndedMs = 0;
  static const int _connectedAudioGraceMs = 8000;

  static void recordNativeCallEnded({
    String? phone,
    required int endedAtMs,
    bool wasOffhook = false,
    bool isExactNative = true,
  }) {
    if (endedAtMs <= 0) return;
    if (isExactNative) {
      if (endedAtMs > _lastAnyCallEndedMs) {
        _lastAnyCallEndedMs = endedAtMs;
      }
    } else if (_lastAnyCallEndedMs == 0 ||
        (endedAtMs - _lastAnyCallEndedMs).abs() > 4000) {
      _lastAnyCallEndedMs = endedAtMs;
    }
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 7) {
      final last10 =
          digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      final prev = _recentCallEndedMs[last10];
      if (isExactNative) {
        if (prev == null || endedAtMs > prev) {
          _recentCallEndedMs[last10] = endedAtMs;
        }
      } else if (prev == null || (endedAtMs - prev).abs() > 4000) {
        _recentCallEndedMs[last10] = endedAtMs;
      }
    }
  }

  static int _resolveHangupTimestampMs(
    String phone, {
    required int startTimeMs,
    required int callEndMs,
    required int nowMs,
  }) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 =
        digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    int candidate = 0;
    final perPhone = last10.isNotEmpty ? (_recentCallEndedMs[last10] ?? 0) : 0;
    if (perPhone >= startTimeMs &&
        (perPhone - callEndMs) <= 65000 &&
        (nowMs - perPhone) <= 120000) {
      candidate = perPhone;
    } else if (_lastAnyCallEndedMs >= startTimeMs &&
        (_lastAnyCallEndedMs - callEndMs) <= 65000 &&
        (nowMs - _lastAnyCallEndedMs) <= 120000 &&
        (nowMs - callEndMs) <= 90000) {
      candidate = _lastAnyCallEndedMs;
    }
    return candidate > callEndMs ? candidate : callEndMs;
  }

  /// Returns remaining ms Phase 2 must wait before posting a metadata-only
  /// call log, accounting for actual native hangup on connected calls so OEM
  /// recorders (e.g. MIUI) can flush audio even after long ring times.
  static int _resolvePhase2RemainingGraceMs({
    required String phoneNumber,
    required int startTimeMs,
    required int callEndMs,
    required int nowMs,
    required bool isExplicitMissed,
    required bool isConnectedCall,
  }) {
    final msSinceCallEnd = nowMs - callEndMs;
    final msSinceCallStart = nowMs - startTimeMs;
    final hangupMs = isConnectedCall
        ? _resolveHangupTimestampMs(
            phoneNumber,
            startTimeMs: startTimeMs,
            callEndMs: callEndMs,
            nowMs: nowMs,
          )
        : callEndMs;
    final effectiveSinceEnd =
        (nowMs - hangupMs) < msSinceCallEnd ? (nowMs - hangupMs) : msSinceCallEnd;
    final neededGraceMs = isExplicitMissed
        ? 2500
        : (isConnectedCall ? _connectedAudioGraceMs : 6000);
    if (effectiveSinceEnd < neededGraceMs || msSinceCallStart < neededGraceMs) {
      final effectiveElapsed = effectiveSinceEnd < msSinceCallStart
          ? effectiveSinceEnd
          : msSinceCallStart;
      return (neededGraceMs - effectiveElapsed).clamp(1, neededGraceMs);
    }
    return 0;
  }

  @visibleForTesting
  static int resolvePhase2GraceWaitForTesting({
    required String phoneNumber,
    required int startTimeMs,
    required int callEndMs,
    required int nowMs,
    bool isExplicitMissed = false,
    bool isConnectedCall = true,
  }) => _resolvePhase2RemainingGraceMs(
    phoneNumber: phoneNumber,
    startTimeMs: startTimeMs,
    callEndMs: callEndMs,
    nowMs: nowMs,
    isExplicitMissed: isExplicitMissed,
    isConnectedCall: isConnectedCall,
  );

  static bool _isCallRecentlyUploaded(
    String phone, {
    String? bound,
    String? leadId,
    int? timestampMs,
    String? callStatus,
  }) {
    // Never suppress across calls when timestamp is unknown
    if (timestampMs == null || timestampMs <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final key = last10.isNotEmpty ? last10 : (leadId ?? '');
    if (key.isEmpty) return false;

    final events = _recentCallUploads[key];
    if (events == null || events.isEmpty) return false;

    final hasBound = bound != null && bound.isNotEmpty;
    final dirKey =
        (bound != null && bound.toUpperCase().startsWith('IN')) ? 'IN' : 'OUT';
    final queryIsConn = _isConnectedStatus(callStatus);

    for (final e in events) {
      final recordedAt = e['recordedAt'] as int? ?? 0;
      if ((now - recordedAt) > 60000) continue;
      if (hasBound && e['dir'] != dirKey) continue;
      final ts = e['ts'] as int? ?? 0;
      if ((ts - timestampMs).abs() > _callMatchJitterMs) continue;

      final evConn = e['conn'] as bool? ?? false;
      // Disconnected/missed uploads must never suppress a connected call upload,
      // and a connected call should only suppress an unconnected shadow at the same start second.
      if (queryIsConn && !evConn) continue;
      if (queryIsConn != evConn && (ts - timestampMs).abs() > 1500) continue;
      return true;
    }
    return false;
  }

  static void _recordCallUploaded(
    String phone, {
    String? bound,
    String? leadId,
    int? timestampMs,
    String? callStatus,
    bool hasAudio = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final dirKey =
        (bound != null && bound.toUpperCase().startsWith('IN')) ? 'IN' : 'OUT';
    final isConn = _isConnectedStatus(callStatus) || hasAudio;
    final effectiveTs =
        (timestampMs != null && timestampMs > 0) ? timestampMs : now;

    final entry = <String, dynamic>{
      'ts': effectiveTs,
      'dir': dirKey,
      'conn': isConn,
      'hasAudio': hasAudio,
      'recordedAt': now,
    };

    for (final k in <String>{
      if (last10.isNotEmpty) last10,
      if (leadId != null && leadId.isNotEmpty) leadId,
    }) {
      final list = _recentCallUploads.putIfAbsent(k, () => []);
      list.removeWhere((e) => (now - (e['recordedAt'] as int? ?? 0)) > 120000);
      list.add(entry);
    }
  }

  static bool _isOutgoingRecentlyUploaded(
    String phone,
    String leadId, {
    int? timestampMs,
    bool requireConnected = true,
    bool requireAudio = false,
  }) {
    if (timestampMs == null || timestampMs <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final key = last10.isNotEmpty ? last10 : leadId;
    if (key.isEmpty) return false;

    final events = _recentCallUploads[key];
    if (events == null || events.isEmpty) return false;

    for (final e in events) {
      final recordedAt = e['recordedAt'] as int? ?? 0;
      if ((now - recordedAt) > 60000) continue;
      if (e['dir'] != 'OUT') continue;
      final ts = e['ts'] as int? ?? 0;
      // Actual call start can follow dialer tap by a few seconds
      if (ts < (timestampMs - _callMatchJitterMs) || ts > (timestampMs + 10000)) {
        continue;
      }
      if (requireConnected && (e['conn'] as bool? ?? false) != true) continue;
      if (requireAudio && (e['hasAudio'] as bool? ?? false) != true) continue;
      return true;
    }
    return false;
  }

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
    final bucket = (timestampMs ~/ _callBucketSizeMs) * _callBucketSizeMs;
    final status =
        (callStatus != null && callStatus.isNotEmpty) ? callStatus.toUpperCase() : '';
    final isConn = _isConnectedStatus(status);
    final connTag = isConn ? 'CONN' : (status == 'MISSED' ? 'MISSED' : 'NOCONN');
    final dirKey =
        (bound != null && bound.toUpperCase().startsWith('IN')) ? 'IN' : 'OUT';
    final hasExplicitBound = bound != null && bound.isNotEmpty;

    for (final b in [bucket]) {
      _uploadedPaths.add('call_${last10}_${connTag}_$b');
      _sessionUploadedKeys.add('call_${last10}_${connTag}_$b');

      if (hasExplicitBound) {
        _uploadedPaths.add('call_${last10}_${dirKey}_${connTag}_$b');
        _uploadedPaths.add('calllog_${dirKey}_${connTag}_${b}_$cleanDigits');
        _sessionUploadedKeys.add('${last10}_${dirKey}_${connTag}_$b');
      } else {
        for (final d in const ['IN', 'OUT']) {
          _uploadedPaths.add('call_${last10}_${d}_${connTag}_$b');
          _uploadedPaths.add('calllog_${d}_${connTag}_${b}_$cleanDigits');
          _sessionUploadedKeys.add('${last10}_${d}_${connTag}_$b');
        }
      }

      if (status.isNotEmpty) {
        _uploadedPaths.add('call_${last10}_${status}_$b');
        _uploadedPaths.add('calllog_${status}_${b}_$phone');
        _uploadedPaths.add('calllog_${status}_${b}_$cleanDigits');
        _uploadedPaths.add('calllog_${dirKey}_${status}_${b}_$phone');
        _uploadedPaths.add('calllog_${dirKey}_${status}_${b}_$cleanDigits');
        _sessionUploadedKeys.add('${last10}_${dirKey}_${status}_$b');
      }
    }
    _recordCallUploaded(
      phone,
      bound: bound,
      timestampMs: timestampMs,
      callStatus: status.isNotEmpty ? status : (isConn ? 'CONNECTED' : null),
      hasAudio: isConn,
    );

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
    int durationSeconds = 0,
    List<LeadAudio>? existingServerAudios,
    List<LeadCallLog>? existingServerCallLogs,
  }) async {
    await _ensurePrefsLoaded();
    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;
    final bucket = (timestampMs ~/ _callBucketSizeMs) * _callBucketSizeMs;
    final status =
        (callStatus != null && callStatus.isNotEmpty) ? callStatus.toUpperCase() : '';
    final isBoundIn = bound != null && bound.toUpperCase().startsWith('IN');
    final queryIsConn = _isConnectedStatus(status) || durationSeconds > 0;
    final connTag =
        queryIsConn ? 'CONN' : (status == 'MISSED' ? 'MISSED' : 'NOCONN');

    final buckets = [
      bucket - 2000,
      bucket - 1000,
      bucket,
      bucket + 1000,
      bucket + 2000,
    ];

    bool hasConnKey(String dirKey, int b) {
      return _uploadedPaths.contains('call_${last10}_${dirKey}_CONN_$b') ||
          _uploadedPaths.contains('call_${last10}_CONN_$b') ||
          _uploadedPaths.contains('calllog_${dirKey}_CONN_${b}_$cleanDigits') ||
          _uploadedPaths.contains('call_${last10}_CONNECTED_$b') ||
          _uploadedPaths.contains('call_${last10}_ANSWERED_$b') ||
          _uploadedPaths.contains('calllog_${dirKey}_CONNECTED_${b}_$phone') ||
          _uploadedPaths.contains('calllog_${dirKey}_CONNECTED_${b}_$cleanDigits') ||
          _uploadedPaths.contains('calllog_${dirKey}_ANSWERED_${b}_$phone') ||
          _uploadedPaths.contains('calllog_${dirKey}_ANSWERED_${b}_$cleanDigits') ||
          _sessionUploadedKeys.contains('${last10}_${dirKey}_CONN_$b') ||
          _sessionUploadedKeys.contains('call_${last10}_CONN_$b') ||
          _sessionUploadedKeys.contains('${last10}_${dirKey}_CONNECTED_$b') ||
          _sessionUploadedKeys.contains('${last10}_${dirKey}_ANSWERED_$b');
    }

    bool hasStatusOrTagKey(String dirKey, int b) {
      if (hasConnKey(dirKey, b) && (queryIsConn || (b - bucket).abs() <= 1000)) {
        return true;
      }
      if (queryIsConn) return false;
      if (_uploadedPaths.contains('call_${last10}_${dirKey}_${connTag}_$b') ||
          _uploadedPaths.contains('call_${last10}_${connTag}_$b') ||
          _uploadedPaths.contains('calllog_${dirKey}_${connTag}_${b}_$cleanDigits') ||
          _sessionUploadedKeys.contains('${last10}_${dirKey}_${connTag}_$b') ||
          _sessionUploadedKeys.contains('call_${last10}_${connTag}_$b')) {
        return true;
      }
      if (status.isNotEmpty) {
        return _uploadedPaths.contains('calllog_${dirKey}_${status}_${b}_$phone') ||
            _uploadedPaths.contains('calllog_${dirKey}_${status}_${b}_$cleanDigits') ||
            _uploadedPaths.contains('call_${last10}_${status}_$b') ||
            _sessionUploadedKeys.contains('${last10}_${dirKey}_${status}_$b');
      }
      return false;
    }

    if (bound != null && bound.isNotEmpty) {
      final dirKey = isBoundIn ? 'IN' : 'OUT';
      for (final b in buckets) {
        if (hasStatusOrTagKey(dirKey, b)) {
          return true;
        }
      }
    } else {
      for (final b in buckets) {
        if (hasStatusOrTagKey('IN', b) || hasStatusOrTagKey('OUT', b)) {
          return true;
        }
      }
    }

    final callEndMs = durationSeconds > 0
        ? (timestampMs + durationSeconds * 1000)
        : timestampMs;

    // Check against existingServerAudios using call-interval overlap
    if (existingServerAudios != null && existingServerAudios.isNotEmpty) {
      for (final sAudio in existingServerAudios) {
        if (status == 'MISSED' && sAudio.size > 0) {
          continue;
        }
        final sIsConnAudio = _isConnectedStatus(sAudio.callStatus) ||
            sAudio.durationSeconds > 0 ||
            sAudio.size > 0;
        if (queryIsConn && !sIsConnAudio) {
          continue;
        }
        final parsedTime = parseTimestampFromFileName(sAudio.displayName);
        final sAudioStartDt = parseCallDateTime(
          sAudio.callDate,
          sAudio.startTimeStr,
          sAudio.createdAt?.toIso8601String(),
        );
        final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
        final audioMs = (sAudioStartMs > 0)
            ? sAudioStartMs
            : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));
        final sAudioEndMs = sAudio.durationSeconds > 0 && audioMs > 0
            ? (audioMs + sAudio.durationSeconds * 1000)
            : audioMs;

        final bool isMatch = queryIsConn
            ? ((sAudioStartMs > 0 &&
                    _intervalsOverlap(
                      timestampMs,
                      callEndMs,
                      sAudioStartMs,
                      sAudioEndMs,
                      padBeforeMs: 2500,
                      padAfterMs: 1000,
                    )) ||
                (parsedTime != null &&
                    _isTimestampInCallInterval(
                      parsedTime,
                      timestampMs,
                      callEndMs,
                      padBeforeMs: 2500,
                      padAfterMs: 1000,
                    )) ||
                (audioMs > 0 &&
                    _isTimestampInCallInterval(
                      timestampMs,
                      audioMs,
                      sAudioEndMs,
                      padBeforeMs: 2500,
                      padAfterMs: 1000,
                    )))
            : ((audioMs > 0 &&
                    (audioMs - timestampMs).abs() <= _callMatchJitterMs) ||
                (parsedTime != null &&
                    (parsedTime - timestampMs).abs() <= _callMatchJitterMs));

        if (isMatch) {
          if (bound == null ||
              bound.isEmpty ||
              checkBoundMatch(bound, sAudio.bound ?? '')) {
            final matchedConn =
                sAudio.size > 0 || sAudio.durationSeconds > 0 || queryIsConn;
            await _markCallBucketAsUploaded(
              phone,
              timestampMs,
              bound,
              matchedConn ? 'CONNECTED' : (status.isNotEmpty ? status : 'NOT_CONNECTED'),
            );
            return true;
          }
        }
      }
    }

    // Check against existingServerCallLogs
    if (existingServerCallLogs != null && existingServerCallLogs.isNotEmpty) {
      for (final sLog in existingServerCallLogs) {
        final sStatus = sLog.callStatus.toUpperCase();
        final sDur = _parseDurationSecondsRaw(sLog.duration);
        final sIsConn = _isConnectedStatus(sStatus) || sDur > 0;

        // A 0s NOT_CONNECTED / MISSED server row must not suppress a real connected call
        if (queryIsConn && !sIsConn) continue;
        if (status.isNotEmpty && !queryIsConn && !sIsConn && sStatus != status) {
          continue;
        }

        final sDt = parseCallDateTime(
          sLog.callDate,
          sLog.startTime,
          sLog.createdAt,
        );
        if (sDt != null) {
          final sMs = sDt.millisecondsSinceEpoch;
          final bool isMatch;
          if (sIsConn && queryIsConn && sDur > 0 && durationSeconds > 0) {
            final sEndMs = sMs + sDur * 1000;
            isMatch = (sDur - durationSeconds).abs() <= 10 &&
                ((sMs - timestampMs).abs() <= _callMatchJitterMs ||
                    _intervalsOverlap(
                      timestampMs,
                      callEndMs,
                      sMs,
                      sEndMs,
                      padBeforeMs: 0,
                      padAfterMs: 0,
                    ));
          } else if (queryIsConn) {
            isMatch = _isTimestampInCallInterval(
              sMs,
              timestampMs,
              callEndMs,
              padBeforeMs: 2500,
              padAfterMs: 1000,
            );
          } else {
            isMatch = (sMs - timestampMs).abs() <= _callMatchJitterMs;
          }

          if (isMatch) {
            if (bound == null ||
                bound.isEmpty ||
                checkBoundMatch(bound, sLog.bound)) {
              await _markCallBucketAsUploaded(
                phone,
                timestampMs,
                bound,
                sIsConn ? 'CONNECTED' : (status.isNotEmpty ? status : sStatus),
              );
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

  static Future<void> _clearPendingCall({
    String? onlyIfLeadId,
    int? onlyIfStartMs,
  }) async {
    if (onlyIfLeadId != null || onlyIfStartMs != null) {
      final curLeadId = _pendingCall?['leadId']?.toString();
      final curTime = (_pendingCall?['callStartTimestamp'] as num?)?.toInt();
      if (_pendingCall != null &&
          ((onlyIfLeadId != null && curLeadId != onlyIfLeadId) ||
              (onlyIfStartMs != null && curTime != onlyIfStartMs))) {
        return;
      }
    }
    _pendingCall = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (onlyIfLeadId != null || onlyIfStartMs != null) {
        final savedLeadId = prefs.getString('pending_lead_call_id');
        final savedTime = prefs.getInt('pending_lead_time');
        if (savedLeadId != null &&
            ((onlyIfLeadId != null && savedLeadId != onlyIfLeadId) ||
                (onlyIfStartMs != null && savedTime != onlyIfStartMs))) {
          return;
        }
      }
      await prefs.remove('pending_lead_call_id');
      await prefs.remove('pending_lead_phone');
      await prefs.remove('pending_lead_time');
    } catch (_) {}
  }

  /// Automatically synchronizes recent calls when entering the Lead List screen.
  /// 1. If a call was initiated from the app, it directly matches the known lead.
  /// 2. If recent system call logs exist, it matches against [knownLeads] in memory or searches CRM.
  /// 3. Uploads call recording & logs via POST /leads/{leadId}/audios, and triggers [onUploadSuccess] when done.
  static Future<void> syncRecentCallsIfAvailable({
    List<dynamic>? knownLeads,
    VoidCallback? onUploadSuccess,
    bool force = false,
  }) async {
    if (knownLeads != null && knownLeads.isNotEmpty) {
      registerKnownLeads(knownLeads);
    }

    if (_isSyncingRecentCalls) {
      if (force) {
        _syncQueued = true;
      }
      return;
    }
    _isSyncingRecentCalls = true;
    bool syncCompletedCleanly = false;
    String? observedFingerprint;

    try {
      final service = CallRecordingService();

      // If call is actively ongoing, postpone until it ends
      if (await service.isCallOngoing()) {
        debugPrint('Sync: Call is actively ongoing, will sync once call ends.');
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Check initiated / pending call from memory or SharedPreferences
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

      final hasPendingCall =
          pendingLeadId != null &&
          pendingLeadId.isNotEmpty &&
          isUsablePhone(pendingPhone);

      // Read local system call logs before applying cooldown (zero network cost)
      final recentLogs = await service.getSystemCallLogs('');
      if (recentLogs.isNotEmpty) {
        final newest = recentLogs.first;
        observedFingerprint =
            '${newest['startTime']}_${newest['durationSeconds'] ?? newest['duration']}_${newest['callStatus']}_${newest['phoneNumber']}';
      }

      if (!force &&
          !hasPendingCall &&
          _lastPassiveSyncCompletedAt != null &&
          DateTime.now().difference(_lastPassiveSyncCompletedAt!) <
              _passiveSyncCooldown &&
          observedFingerprint != null &&
          observedFingerprint == _lastObservedCallFingerprint) {
        return;
      }

      final processedLeadPhones = <String>{};
      if (hasPendingCall && pendingPhone != null) {
        debugPrint(
          'Sync: Found pending call for lead $pendingLeadId ($pendingPhone). Auto-scanning & uploading...',
        );
        final String leadIdToUpload = pendingLeadId;
        final String phoneToUpload = pendingPhone;
        final callTs = pendingTime;
        bool pendingUploaded = false;

        final pDigits = phoneToUpload.replaceAll(RegExp(r'\D'), '');
        final pLast10 =
            pDigits.length >= 10 ? pDigits.substring(pDigits.length - 10) : pDigits;
        if (pLast10.isNotEmpty) {
          processedLeadPhones.add('${leadIdToUpload}_$pLast10');
        }

        await autoScanAndUploadLeadRecordings(
          context: null,
          leadId: leadIdToUpload,
          phoneNumber: phoneToUpload,
          callTimestamp: callTs,
          initialBound: 'OUT',
          onUploadSuccess: () {
            pendingUploaded = true;
            if (onUploadSuccess != null) onUploadSuccess();
          },
        );

        final ageMs = DateTime.now().millisecondsSinceEpoch - callTs;
        if (pendingUploaded || ageMs > 120000) {
          await _clearPendingCall(
            onlyIfLeadId: leadIdToUpload,
            onlyIfStartMs: callTs,
          );
        }

        // Schedule follow-up scan for recorders/CallLog flush delays
        Future.delayed(const Duration(milliseconds: 2500), () async {
          if (await CallRecordingService().isCallOngoing()) return;
          if (_isOutgoingRecentlyUploaded(
            phoneToUpload,
            leadIdToUpload,
            timestampMs: callTs,
            requireConnected: true,
            requireAudio: true,
          )) {
            await _clearPendingCall(
              onlyIfLeadId: leadIdToUpload,
              onlyIfStartMs: callTs,
            );
            return;
          }
          await autoScanAndUploadLeadRecordings(
            context: null,
            leadId: leadIdToUpload,
            phoneNumber: phoneToUpload,
            callTimestamp: callTs,
            initialBound: 'OUT',
            onUploadSuccess: () {
              if (onUploadSuccess != null) onUploadSuccess();
            },
          );
          await _clearPendingCall(
            onlyIfLeadId: leadIdToUpload,
            onlyIfStartMs: callTs,
          );
        });
      }

      // 2. Scan recent system call logs (last 50 calls within 48 hours)
      if (recentLogs.isEmpty) {
        syncCompletedCleanly = true;
        return;
      }

      for (final log in recentLogs.take(50)) {
        final st = log['startTime'] as int? ?? 0;
        if (st <= 0 || (now - st) > 48 * 60 * 60 * 1000) continue;

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
        final logDur = (log['durationSeconds'] as num?)?.toInt() ??
            (log['duration'] as num?)?.toInt() ??
            0;
        final isMissedLog = callTypeRaw == 'MISSED' ||
            callTypeRaw == 'REJECTED' ||
            (log['callStatus'] as String? ?? '').toUpperCase() == 'MISSED';
        final logStatusStr = isMissedLog
            ? 'MISSED'
            : (logDur > 0
                  ? 'CONNECTED'
                  : (isIncoming ? 'MISSED' : 'NOT_CONNECTED'));

        if (_isCallRecentlyUploaded(
          rawPhone,
          bound: boundStr,
          timestampMs: st,
          callStatus: logStatusStr,
        )) {
          continue;
        }

        if (await isCallAlreadyUploaded(
          phone: rawPhone,
          timestampMs: st,
          bound: boundStr,
          callStatus: logStatusStr,
          durationSeconds: logDur,
        )) {
          continue;
        }

        final last10 = cleanDigits.length >= 10
            ? cleanDigits.substring(cleanDigits.length - 10)
            : cleanDigits;

        final String? leadId = await _resolveLeadIdByPhone(
          rawPhone: rawPhone,
          last10: last10,
          knownLeads: knownLeads,
        );

        if (leadId != null && leadId.isNotEmpty) {
          final scanKey = '${leadId}_$last10';
          if (!processedLeadPhones.add(scanKey)) continue;
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
            onUploadSuccess: () {
              if (onUploadSuccess != null) onUploadSuccess();
            },
          );
        }
      }
      syncCompletedCleanly = true;
    } catch (e) {
      debugPrint('Error in syncRecentCallsIfAvailable: $e');
    } finally {
      if (syncCompletedCleanly) {
        _lastPassiveSyncCompletedAt = DateTime.now();
        if (observedFingerprint != null) {
          _lastObservedCallFingerprint = observedFingerprint;
        }
      }
      _isSyncingRecentCalls = false;
      if (_syncQueued) {
        _syncQueued = false;
        Future.delayed(const Duration(milliseconds: 500), () {
          syncRecentCallsIfAvailable(
            knownLeads: knownLeads,
            onUploadSuccess: onUploadSuccess,
            force: true,
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
    if (leadId.trim().isEmpty || !isUsablePhone(phoneNumber)) return;
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

    final callRecordingService = CallRecordingService();
    bool hasUploaded = false;
    bool wasCallActive = false;
    bool isScanExecuting = false;
    int? callEndedTimestamp;

    Future<void> doScanAndUpload() async {
      if (hasUploaded || isScanExecuting) return;
      if (await callRecordingService.isCallOngoing()) {
        debugPrint('Call is currently active, waiting for call to end.');
        return;
      }
      if (_isOutgoingRecentlyUploaded(
        phoneNumber,
        leadId,
        timestampMs: callStartTimestamp,
        requireConnected: true,
        requireAudio: true,
      )) {
        debugPrint('Outgoing call for $leadId recently uploaded, skipping duplicate.');
        hasUploaded = true;
        return;
      }
      isScanExecuting = true;
      try {
        final details = await callRecordingService.getLatestCallDetails(
          phoneNumber: phoneNumber,
          callTimestamp: callStartTimestamp,
        );

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final msSinceEnd = callEndedTimestamp != null
            ? (nowMs - callEndedTimestamp!)
            : (nowMs - callStartTimestamp);

        // Wait for Android CallLog provider to flush if call just ended or dialer just opened
        if (details == null) {
          if (callEndedTimestamp != null && msSinceEnd < 15000) {
            debugPrint('Call log not written yet after call end, postponing upload.');
            return;
          }
          if (callEndedTimestamp == null && (nowMs - callStartTimestamp) < 25000) {
            debugPrint('Call log not written yet by Android, postponing upload.');
            return;
          }
          // If the dialer opened and closed without ever entering an active call and no CallLog exists,
          // do not fabricate a dummy 0s NOT_CONNECTED record.
          if (!wasCallActive && callEndedTimestamp == null) {
            debugPrint('No active call or system CallLog detected; skipping synthetic NOT_CONNECTED upload.');
            return;
          }
        }

        final durationSec = details != null
            ? ((details['durationSeconds'] as num?)?.toInt() ?? 0)
            : 0;
        final rawStatus = details != null
            ? (details['callStatus']?.toString() ?? '')
            : '';
        final statusUpper = rawStatus.toUpperCase();

        // Android/OEM often writes DURATION=0 momentarily right after IDLE before updating real duration
        if (details != null &&
            durationSec == 0 &&
            statusUpper != 'MISSED' &&
            statusUpper != 'REJECTED' &&
            callEndedTimestamp != null &&
            msSinceEnd < 6000) {
          debugPrint('CallLog duration is still 0 right after hangup; postponing upload.');
          return;
        }

        final startMs =
            details != null && (details['startTime'] as int? ?? 0) > 0
            ? (details['startTime'] as int)
            : callStartTimestamp;
        final endMs = details != null && (details['endTime'] as int? ?? 0) > 0
            ? (details['endTime'] as int)
            : nowMs;

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
        if (details != null) {
          await CallHistoryStorage.addOrUpdateCall(callHistoryEntry);
        }

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
            await CallHistoryStorage.markCallAsSynced(phoneNumber, startMs);
            await _clearPendingCall();
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
        // Call was active and has ended: allow Android CallLog + OEM recorder to flush
        wasCallActive = false;
        callEndedTimestamp ??= DateTime.now().millisecondsSinceEpoch;
        recordNativeCallEnded(
          phone: phoneNumber,
          endedAtMs: callEndedTimestamp!,
          wasOffhook: true,
          isExactNative: false,
        );
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (!hasUploaded) doScanAndUpload();
        });
      } else if (pollTicks >= 40) {
        // Dialer elapsed without active call (60s window accommodates SIM chooser)
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
    if (!isUsablePhone(phoneNumber)) return;
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
        final recFileName = recordingPath.split(RegExp(r'[/\\]')).last;
        if (hasConflictingPhoneInFileName(recFileName, phoneNumber)) {
          debugPrint(
            'Blocking cross-lead upload: $recordingPath conflicts with $phoneNumber ($leadId)',
          );
          return;
        }
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
            final detailsPhone = callDetails?['phoneNumber']?.toString() ?? '';
            if (isUsablePhone(detailsPhone) &&
                !phonesMatch(detailsPhone, phoneNumber)) {
              debugPrint(
                'Blocking cross-lead upload: callDetails phone $detailsPhone != $phoneNumber ($leadId)',
              );
              return;
            }
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
    if (!isUsablePhone(phoneNumber)) return;
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
    bool skippedGrowingRecording = false;
    // Tracks timestamps & intervals of calls for which an audio file was successfully uploaded in Phase 1.
    // Phase 2 will skip these so we don't double-post a connected call.
    final Set<int> uploadedAudioTimestamps = {};
    final List<Map<String, int>> uploadedAudioIntervals = [];

    try {
      final scanPhoneKey = _normalizePhoneCacheKey(phoneNumber);
      _sessionUploadedKeys.removeWhere(
        (k) =>
            k.startsWith('${scanPhoneKey}_') ||
            k.startsWith('calllog_') && k.endsWith('_$phoneNumber'),
      );
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
        final isOngoingNow = await service.isCallOngoing();
        if (isOngoingNow || ageMs < 3500) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (!await file.exists()) continue;
          final length2 = await file.length();
          if (length != length2 || isOngoingNow) {
            debugPrint(
              'Recording file $path is actively growing ($length -> $length2 bytes, ongoing=$isOngoingNow). Will retry after flush.',
            );
            skippedGrowingRecording = true;
            continue;
          }
          finalLength = length2;
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
          final recDurMs = (recording['durationMs'] as num?)?.toInt() ?? 0;
          final fileTimestamp =
              parseTimestampFromFileName(fileName) ?? recTimestamp;
          final effectiveTime = fileTimestamp > 0
              ? fileTimestamp
              : recTimestamp;
          if (effectiveTime > 0) {
            uploadedAudioTimestamps.add(effectiveTime);
            uploadedAudioIntervals.add({
              'start': effectiveTime,
              'end': recDurMs > 0 ? effectiveTime + recDurMs : effectiveTime,
            });
            await _markCallBucketAsUploaded(
              phoneNumber,
              effectiveTime,
              null,
              'CONNECTED',
            );
          }
          if (callTimestamp > 0 &&
              effectiveTime > 0 &&
              (effectiveTime - callTimestamp).abs() < 3500) {
            uploadedAudioTimestamps.add(callTimestamp);
            await _markCallBucketAsUploaded(
              phoneNumber,
              callTimestamp,
              null,
              'CONNECTED',
            );
          }
          if (recTimestamp > 0) {
            uploadedAudioTimestamps.add(recTimestamp);
            if (parseTimestampFromFileName(fileName) == null && recDurMs > 0) {
              // When filename lacks start timestamp, recTimestamp (lastModified) is endTime
              uploadedAudioIntervals.add({
                'start': recTimestamp - recDurMs,
                'end': recTimestamp,
              });
            }
          }
          continue;
        }

        if (hasConflictingPhoneInFileName(fileName, phoneNumber)) {
          debugPrint(
            'Phase 1: Skipping conflicting filename $fileName for $leadId ($phoneNumber).',
          );
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
        final detailsPhone = callDetails?['phoneNumber']?.toString() ?? '';
        if (isUsablePhone(detailsPhone) &&
            !phonesMatch(detailsPhone, phoneNumber)) {
          debugPrint(
            'Phase 1: Skipping mismatched callDetails phone $detailsPhone for $leadId ($phoneNumber).',
          );
          continue;
        }

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

        final metaStartMs =
            parseCallDateTime(
              meta['callDate'],
              meta['startTime'],
            )?.millisecondsSinceEpoch ??
            ((callDetails?['startTime'] as num?)?.toInt() ?? targetSearchTime);
        final metaDurSec = _parseDurationSecondsRaw(meta['duration']);
        final alreadyConnectedUploaded =
            metaStartMs > 0 &&
            (_isCallRecentlyUploaded(
                  phoneNumber,
                  bound: targetBound,
                  leadId: leadId,
                  timestampMs: metaStartMs,
                  callStatus: 'CONNECTED',
                ) ||
                await isCallAlreadyUploaded(
                  phone: phoneNumber,
                  timestampMs: metaStartMs,
                  bound: targetBound,
                  callStatus: 'CONNECTED',
                  durationSeconds: metaDurSec,
                  existingServerAudios: serverAudios,
                  existingServerCallLogs: serverCallLogs,
                ));
        if (alreadyConnectedUploaded) {
          debugPrint(
            'Phase 1: Connected call already uploaded around $metaStartMs for $leadId ($phoneNumber). Skipping duplicate audio upload for $path.',
          );
          await _markAsUploaded(path, finalLength);
          uploadedAudioTimestamps.add(metaStartMs);
          uploadedAudioIntervals.add({
            'start': metaStartMs,
            'end': metaDurSec > 0 ? metaStartMs + metaDurSec * 1000 : metaStartMs,
          });
          continue;
        }

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
            // Mark this call interval & timestamp so Phase 2 knows audio was already uploaded
            final metaDurSec = _parseDurationSecondsRaw(meta['duration']);
            final effectiveDurMs = localDurMs > 0
                ? localDurMs
                : (metaDurSec > 0
                      ? metaDurSec * 1000
                      : ((callDetails?['durationSeconds'] as num?)?.toInt() ??
                                0) *
                            1000);
            bool callTimestampMatchesRec = actualStartMs <= 0 && fileTimestamp <= 0;
            if (actualStartMs > 0) {
              final actualEndMs =
                  (callDetails != null &&
                      (callDetails['endTime'] as int? ?? 0) > actualStartMs)
                  ? (callDetails['endTime'] as int)
                  : (effectiveDurMs > 0
                        ? actualStartMs + effectiveDurMs
                        : actualStartMs);
              uploadedAudioTimestamps.add(actualStartMs);
              uploadedAudioIntervals.add({
                'start': actualStartMs,
                'end': actualEndMs,
              });
              await _markCallBucketAsUploaded(
                phoneNumber,
                actualStartMs,
                targetBound,
                'CONNECTED',
              );
              if (callTimestamp > 0 &&
                  _isTimestampInCallInterval(
                    callTimestamp,
                    actualStartMs,
                    actualEndMs,
                    padBeforeMs: _callMatchJitterMs,
                    padAfterMs: _callMatchJitterMs,
                  )) {
                callTimestampMatchesRec = true;
              }
            }
            if (fileTimestamp > 0) {
              uploadedAudioTimestamps.add(fileTimestamp);
              await _markCallBucketAsUploaded(
                phoneNumber,
                fileTimestamp,
                targetBound,
                'CONNECTED',
              );
              if (callTimestamp > 0 &&
                  (callTimestamp - fileTimestamp).abs() <= _callMatchJitterMs) {
                callTimestampMatchesRec = true;
              }
            }
            if (callTimestamp > 0 && callTimestampMatchesRec) {
              uploadedAudioTimestamps.add(callTimestamp);
              await _markCallBucketAsUploaded(
                phoneNumber,
                callTimestamp,
                targetBound,
                'CONNECTED',
              );
            }
            if (recTimestamp > 0 &&
                parseTimestampFromFileName(fileName) == null &&
                effectiveDurMs > 0) {
              uploadedAudioIntervals.add({
                'start': recTimestamp - effectiveDurMs,
                'end': recTimestamp,
              });
            }
            if (callDetails != null) {
              final s = callDetails['startTime'] as int? ?? 0;
              final e = callDetails['endTime'] as int? ?? 0;
              if (s > 0) uploadedAudioTimestamps.add(s);
              if (s > 0) {
                uploadedAudioIntervals.add({
                  'start': s,
                  'end': e > s ? e : s,
                });
              }
            }
            await CallHistoryStorage.markCallAsSynced(
              phoneNumber,
              actualStartMs,
            );

            _currentlyUploadingPaths.remove(path);
            _currentlyUploadingPaths.remove(cleanName);
            serverAudios.add(audio);
            uploadedAny = true;
            _recordCallUploaded(
              phoneNumber,
              bound: targetBound,
              leadId: leadId,
              timestampMs: actualStartMs,
              callStatus: 'CONNECTED',
              hasAudio: true,
            );
          },
        );
      }

      // ─── Phase 2: Scan & Upload Call Logs (No Audio File) ───
      final sevenDaysAgo =
          DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);
      final systemCallLogs = await service.getSystemCallLogs(phoneNumber);
      final trackedCallHistory = await CallHistoryStorage.loadCallHistory();

      final leadPhoneDigits = usablePhoneDigits(phoneNumber);
      final leadLast10 = leadPhoneDigits.length >= 10
          ? leadPhoneDigits.substring(leadPhoneDigits.length - 10)
          : leadPhoneDigits;

      final List<Map<String, dynamic>> rawCalls = [];

      // Only include system call logs from the last 7 days belonging to phoneNumber
      for (final log in systemCallLogs) {
        final logPhone = log['phoneNumber']?.toString() ?? '';
        if (!phonesMatch(logPhone, phoneNumber)) {
          continue;
        }
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
        // Never upload synthetic 0s placeholders from local storage; real 0s/missed calls
        // always come from Android systemCallLogs.
        if (h.durationSeconds <= 0) continue;
        if (await StaffPersonalNumbersRepositoryImpl.isNumberBlocked(
          h.phoneNumber,
        )) {
          continue;
        }
        if (phonesMatch(h.phoneNumber, phoneNumber)) {
          final hSt = h.startTime > 0 ? h.startTime : h.timestamp;
          if (hSt >= sevenDaysAgo) {
            rawCalls.add({
              'id': h.id,
              'phoneNumber': h.phoneNumber,
              'startTime': hSt,
              'endTime': h.endTime > 0 ? h.endTime : hSt,
              'durationSeconds': h.durationSeconds,
              'callType': h.callType,
              'callStatus': h.callStatus,
              'isTracked': true,
            });
          }
        }
      }

      // Deduplicate raw calls:
      //  - Merge only within tight jitter (5s for system-vs-system, 15s when matching
      //    tracked history) and NEVER merge two distinct calls that both have duration > 0.
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

          final sameDirection = isCallIncoming == isExistingIncoming;
          final existingDur =
              allUnuploadedCalls[i]['durationSeconds'] as int? ?? 0;
          final bothFromSystem =
              (call['isTracked'] != true) &&
              (allUnuploadedCalls[i]['isTracked'] != true);
          final maxDiff = bothFromSystem ? 1500 : 4000;
          final isNearInTime = (st - existingSt).abs() < maxDiff;

          final shouldMerge =
              sameDirection &&
              isNearInTime &&
              !(dur > 0 && existingDur > 0 && bothFromSystem);

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

            if (dur > existingDur ||
                (dur == existingDur &&
                    ((newIsAnswered && !existingIsAnswered) ||
                        (isCallIncoming && !isExistingIncoming)))) {
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
        final isExplicitMissed =
            callTypeRaw == 'MISSED' || callTypeRaw == 'REJECTED';
        final isIncoming =
            callTypeRaw == 'INCOMING' ||
            callTypeRaw == 'INBOUND' ||
            isExplicitMissed ||
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

        final rawEndMs = callLog['endTime'] as int? ?? 0;
        final callEndMs = (rawEndMs > startTimeMs)
            ? rawEndMs
            : (callDuration > 0
                  ? startTimeMs + callDuration * 1000
                  : startTimeMs);

        final startTimeBucket = (startTimeMs ~/ _callBucketSizeMs) * _callBucketSizeMs;
        final uniqueKey = 'calllog_${boundStr}_${callStatusStr}_${startTimeBucket}_$phoneNumber';
        final sessionKey = '${leadLast10}_${boundStr}_${callStatusStr}_$startTimeBucket';

        // 1. If real audio was already uploaded in Phase 1 or exists on server for this call,
        // (even if Android CallLog reported duration=0), skip call-log-only post.
        const int audioMatchPad = _callMatchJitterMs;
        final isAudioAlreadyUploaded =
            uploadedAudioIntervals.any(
              (iv) {
                final ivStart = iv['start'] ?? 0;
                final ivEnd = iv['end'] ?? 0;
                return isConnectedCall
                    ? _intervalsOverlap(
                        startTimeMs,
                        callEndMs,
                        ivStart,
                        ivEnd,
                        padBeforeMs: 2500,
                        padAfterMs: 1000,
                      )
                    : (ivStart > 0 &&
                        (ivStart - startTimeMs).abs() <= _callMatchJitterMs);
              },
            ) ||
            uploadedAudioTimestamps.any(
              (ts) => isConnectedCall
                  ? _isTimestampInCallInterval(
                      ts,
                      startTimeMs,
                      callEndMs,
                      padBeforeMs: 2500,
                      padAfterMs: 1000,
                    )
                  : (ts > 0 && (ts - startTimeMs).abs() <= _callMatchJitterMs),
            );

        final hasServerAudio = serverAudios.any((sAudio) {
          if (sAudio.size <= 0) return false;
          final sBound = (sAudio.bound ?? '').toUpperCase();
          if (sBound.isNotEmpty && !checkBoundMatch(boundStr, sBound)) {
            return false;
          }
          final parsedTime = parseTimestampFromFileName(sAudio.displayName);
          final sAudioStartDt = parseCallDateTime(
            sAudio.callDate,
            sAudio.startTimeStr,
            sAudio.createdAt?.toIso8601String(),
          );
          final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
          final audioMs = (sAudioStartMs > 0)
              ? sAudioStartMs
              : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));
          if (audioMs <= 0) return false;
          if (!isConnectedCall) {
            return (audioMs - startTimeMs).abs() <= _callMatchJitterMs;
          }
          final sAudioEndMs = sAudio.durationSeconds > 0
              ? audioMs + sAudio.durationSeconds * 1000
              : audioMs;
          return _intervalsOverlap(
            startTimeMs,
            callEndMs,
            audioMs,
            sAudioEndMs,
            padBeforeMs: 2500,
            padAfterMs: 1000,
          );
        });

        if (isAudioAlreadyUploaded || hasServerAudio) {
          debugPrint(
            'Phase 2: Audio already exists or uploaded for call at $startTimeMs. Skipping call-log-only post.',
          );
          await _markAsUploaded(uniqueKey, 0);
          await _markCallBucketAsUploaded(phoneNumber, startTimeMs, boundStr, 'CONNECTED');
          continue;
        }

        // 2. Check if an unflushed / in-flight audio recording exists on device for this call.
        // If Phase 1 skipped it because it is still growing or uploading, wait & retry without
        // prematurely marking the call as uploaded. If Phase 1 failed permanently, allow Phase 2
        // to upload the call log metadata so the call is never lost.
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        bool hasPendingDeviceAudio = false;
        for (final rec in allRecordings) {
          final recPath = rec['path'] as String? ?? '';
          final recName = recPath.split('/').last;
          final recTs = (rec['timestamp'] as num?)?.toInt() ?? 0;
          final recDurMs = (rec['durationMs'] as num?)?.toInt() ?? 0;
          final parsedNameTs = parseTimestampFromFileName(recName);
          final recStartMs = parsedNameTs ??
              (recDurMs > 0 && recTs > recDurMs ? recTs - recDurMs : recTs);
          final recEndMs = parsedNameTs != null && recDurMs > 0
              ? parsedNameTs + recDurMs
              : (recTs > recStartMs ? recTs : recStartMs);

          final bool matchesInterval = isConnectedCall
              ? _intervalsOverlap(
                  startTimeMs,
                  callEndMs,
                  recStartMs,
                  recEndMs,
                  padBeforeMs: audioMatchPad,
                  padAfterMs: 1000,
                )
              : (recStartMs - startTimeMs).abs() <= audioMatchPad;
          if (!matchesInterval) continue;

          final ageMs = recTs > 0 ? (nowMs - recTs) : 10000;
          if (ageMs < 4000 ||
              _currentlyUploadingPaths.contains(recPath) ||
              _currentlyUploadingPaths.contains(cleanFileName(recName))) {
            hasPendingDeviceAudio = true;
            break;
          }
        }
        if (hasPendingDeviceAudio) {
          debugPrint(
            'Phase 2: Device audio for call at $startTimeMs is still flushing/uploading. Postponing retry.',
          );
          if (minRemainingWaitMs == null || minRemainingWaitMs > 2500) {
            minRemainingWaitMs = 2500;
          }
          continue;
        }

        final graceWaitMs = _resolvePhase2RemainingGraceMs(
          phoneNumber: phoneNumber,
          startTimeMs: startTimeMs,
          callEndMs: callEndMs,
          nowMs: nowMs,
          isExplicitMissed: isExplicitMissed,
          isConnectedCall: isConnectedCall,
        );
        if (graceWaitMs > 0) {
          if (minRemainingWaitMs == null || graceWaitMs < minRemainingWaitMs) {
            minRemainingWaitMs = graceWaitMs;
          }
          debugPrint(
            'Phase 2: Call at $startTimeMs is too recent. Waiting ${graceWaitMs}ms before fallback upload.',
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
          durationSeconds: callDuration,
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

            final sStatus = sLog.callStatus.toUpperCase();
            final sDur = _parseDurationSecondsRaw(sLog.duration);
            final sIsConn = _isConnectedStatus(sStatus) || sDur > 0;

            // Never let a 0s NOT_CONNECTED / MISSED server record block a real connected call
            if (isConnectedCall && !sIsConn) continue;

            final sDt = parseCallDateTime(
              sLog.callDate,
              sLog.startTime,
              sLog.createdAt,
            );
            if (sDt != null) {
              final sMs = sDt.millisecondsSinceEpoch;
              final bool isMatch;
              if (isConnectedCall && sIsConn && sDur > 0 && callDuration > 0) {
                isMatch = (sMs - startTimeMs).abs() <= _callMatchJitterMs &&
                    (sDur - callDuration).abs() <= 10;
              } else if (!isConnectedCall && sIsConn) {
                isMatch = (sMs - startTimeMs).abs() <= _callMatchJitterMs;
              } else {
                isMatch = sStatus == callStatusStr &&
                    (isConnectedCall
                        ? _isTimestampInCallInterval(
                            sMs,
                            startTimeMs,
                            callEndMs,
                            padBeforeMs: 2500,
                            padAfterMs: 1000,
                          )
                        : (sMs - startTimeMs).abs() <= _callMatchJitterMs);
              }
              if (isMatch) {
                alreadySyncedInHistory = true;
                break;
              }
            }
          }
        }

        // 2. Check serverAudios
        if (!alreadySyncedInHistory && serverAudios.isNotEmpty) {
          for (final sAudio in serverAudios) {
            if (!isConnectedCall && sAudio.size <= 0) continue;
            final parsedTime = parseTimestampFromFileName(sAudio.displayName);
            final sAudioStartDt = parseCallDateTime(
              sAudio.callDate,
              sAudio.startTimeStr,
              sAudio.createdAt?.toIso8601String(),
            );
            final sAudioStartMs = sAudioStartDt?.millisecondsSinceEpoch ?? 0;
            final audioMs = (sAudioStartMs > 0)
                ? sAudioStartMs
                : (parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0));
            if (audioMs <= 0) continue;
            final sAudioEndMs = sAudio.durationSeconds > 0
                ? audioMs + sAudio.durationSeconds * 1000
                : audioMs;

            final bool isMatch = isConnectedCall
                ? _intervalsOverlap(
                    startTimeMs,
                    callEndMs,
                    audioMs,
                    sAudioEndMs,
                    padBeforeMs: audioMatchPad,
                    padAfterMs: 1000,
                  )
                : (audioMs - startTimeMs).abs() <= audioMatchPad;
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
          await _markCallBucketAsUploaded(
            phoneNumber,
            startTimeMs,
            boundStr,
            callStatusStr,
          );
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

        if (_isCallRecentlyUploaded(
          phoneNumber,
          bound: boundStr,
          leadId: leadId,
          timestampMs: startTimeMs,
          callStatus: callStatusStr,
        )) {
          debugPrint(
            'Phase 2: Call was recently uploaded for $leadId ($phoneNumber). Skipping duplicate upload for now.',
          );
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
            _recordCallUploaded(
              phoneNumber,
              bound: boundStr,
              leadId: leadId,
              timestampMs: startTimeMs,
              callStatus: callStatusStr,
              hasAudio: false,
            );
          },
        );
      }

      if (skippedGrowingRecording &&
          (minRemainingWaitMs == null || minRemainingWaitMs > 2500)) {
        minRemainingWaitMs = 2500;
      }

      if (minRemainingWaitMs != null && minRemainingWaitMs > 0) {
        Future.delayed(Duration(milliseconds: minRemainingWaitMs + 300), () {
          autoScanAndUploadLeadRecordings(
            context: null,
            leadId: leadId,
            phoneNumber: phoneNumber,
            callTimestamp: callTimestamp,
            initialBound: initialBound,
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
        ((callDetails['durationSeconds'] as num?)?.toInt() ?? 0) > 0) {
      durSec = (callDetails['durationSeconds'] as num).toInt();
    }
    if (durSec <= 0 && filePath.isNotEmpty) {
      try {
        final durMs = await CallRecordingService().getAudioDuration(filePath);
        if (durMs > 0) {
          durSec = (durMs / 1000).round().clamp(1, 86400);
        }
      } catch (_) {}
    }

    // 3. Start time & End time calculation (exact timestamps in ms)
    int? startMs;
    int? endMs;

    // First resolve the exact timestamp from the recording filename or callTimestamp
    int? fileStartMs = parseTimestampFromFileName(fileName);
    if ((fileStartMs == null || fileStartMs <= 0) && callTimestamp > 0) {
      fileStartMs = callTimestamp;
    }

    // Accept System CallLog details if fileStartMs lies within [start - 2m, end + 2m]
    // (critical for >2-minute calls whose filename lacks a start timestamp).
    if (callDetails != null) {
      final s = callDetails['startTime'] as int? ?? 0;
      final e = callDetails['endTime'] as int? ?? 0;
      final d = (callDetails['durationSeconds'] as num?)?.toInt() ?? 0;
      final effectiveE = e > s ? e : (d > 0 ? s + d * 1000 : s);
      if (s > 0) {
        if (fileStartMs == null ||
            fileStartMs <= 0 ||
            (fileStartMs >= (s - 120000) &&
                fileStartMs <= (effectiveE + 120000))) {
          startMs = s;
          if (e > 0) endMs = e;
          if (durSec <= 0 && d > 0) durSec = d;
        } else {
          debugPrint(
            'callDetails window ($s..$effectiveE) mismatched with file timestamp ($fileStartMs). Ignoring mismatched CallLog details.',
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
          ((callDetails['durationSeconds'] as num?)?.toInt() ?? 0) > 0) {
        final callDurSec = (callDetails['durationSeconds'] as num).toInt();
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
    if (durSec <= 0 && file.existsSync() && file.lengthSync() > 1000) {
      durSec = 1;
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
