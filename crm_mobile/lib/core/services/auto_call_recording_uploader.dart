import 'dart:async';
import 'dart:io';
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

class AutoCallRecordingUploader {
  static const String _prefKey = 'uploaded_call_recordings_v5';
  static final Set<String> _uploadedPaths = {};
  static final Set<String> _failedUploads = {};
  static final Set<String> _currentlyUploadingPaths = {};
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
      clean = clean.replaceAll(RegExp(r'^\.?pending[-_]?[a-zA-Z0-9]*[-_]?', caseSensitive: false), '');
      clean = clean.replaceAll(RegExp(r'^\.?pending', caseSensitive: false), '');
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
      final phoneMatch = RegExp(r'^(?!(?:20[2-3]\d{11}|1[6-9]\d{11}))\d{7,15}(\(\d{7,15}\))?[-_]?', caseSensitive: false).firstMatch(clean);
      if (phoneMatch != null) {
        clean = clean.substring(phoneMatch.end);
      }

      if (clean == old) break;
    }
    return clean;
  }

  static Future<void> _markAsUploaded(String path, int length) async {
    await _ensurePrefsLoaded();
    final fileName = path.split('/').last;
    final cleanName = cleanFileName(fileName);

    _uploadedPaths.add('${path}_$length');
    _uploadedPaths.add('${fileName}_$length');
    _uploadedPaths.add('${cleanName}_$length');
    _uploadedPaths.add(fileName);
    _uploadedPaths.add(cleanName);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _uploadedPaths.toList());
    } catch (e) {
      debugPrint('Error saving uploaded recording prefs: $e');
    }
  }

  static Future<bool> isAlreadyUploaded(String path, int length, {List<LeadAudio>? existingServerAudios}) async {
    await _ensurePrefsLoaded();

    final isMissedCallKey = path.startsWith('missed_');

    // Ignore empty/corrupted audio fragments under 100 bytes unless it's a missed call entry
    if (length > 0 && length < 100) return true;

    if (isMissedCallKey) {
      if (existingServerAudios != null) {
        // Parse timestamp from missed call key: missed_IN_1726650000000_+919876543210
        final parts = path.split('_');
        if (parts.length >= 3) {
          final ts = int.tryParse(parts[2]) ?? 0;
          final keyBound = parts[1].toUpperCase(); // 'IN' or 'OUT'
          if (ts > 0) {
            for (final sAudio in existingServerAudios) {
              // Missed call entries are 0-byte dummy records. Do not compare with real audio files (size > 0).
              if (sAudio.size > 0) continue;

              final parsedTime = parseTimestampFromFileName(sAudio.displayName);
              final audioMs = parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0);

              if (audioMs > 0) {
                final serverBound = sAudio.bound?.toUpperCase() ?? '';
                final isBoundMatch = serverBound.isEmpty ||
                    (keyBound == 'IN' && (serverBound == 'IN' || serverBound == 'INBOUND' || serverBound.contains('IN'))) ||
                    (keyBound == 'OUT' && (serverBound == 'OUT' || serverBound == 'OUTGOING' || serverBound.contains('OUT')));

                if (isBoundMatch) {
                  if ((audioMs - ts).abs() < 120000) { // 2 minute tolerance for 0-byte missed call records
                    await _markAsUploaded(path, 0);
                    return true;
                  }
                }
              }
            }
          }
        }
        return false;
      }
      return _uploadedPaths.contains(path) || _uploadedPaths.contains('${path}_0');
    }

    final fileName = path.split('/').last;
    final clean = cleanFileName(fileName);

    // If server audios list is provided, check if the server already has this exact recording
    if (existingServerAudios != null) {
      bool foundOnServer = false;
      for (final sAudio in existingServerAudios) {
        final serverClean = cleanFileName(sAudio.displayName.toLowerCase());
        if (serverClean == clean.toLowerCase() || (sAudio.size == length && serverClean.contains(clean.toLowerCase()))) {
          foundOnServer = true;
          break;
        }
      }
      if (foundOnServer) {
        await _markAsUploaded(path, length);
        return true;
      }
      return false;
    }

    // Fallback to checking local cache only when existingServerAudios is not provided
    if (_uploadedPaths.contains('${path}_$length')) return true;
    if (_uploadedPaths.contains('${fileName}_$length')) return true;
    if (_uploadedPaths.contains(clean)) return true;
    if (_uploadedPaths.contains(path)) return true;
    if (clean.length >= 8 && _uploadedPaths.contains('${clean}_$length')) return true;

    return false;
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
        const SnackBar(content: Text('No phone number available for this lead.')),
      );
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calling ${leadName ?? phoneNumber}... Call recording will auto-upload when finished.'),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    final callStartTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Launch dialer IMMEDIATELY without waiting for async disk I/O
    DirectCallHelper.makeCall(phoneNumber);

    // Track call history and setup auto-upload timers in background
    unawaited(_trackCallAndSetupUpload(
      context: context,
      leadId: leadId,
      phoneNumber: phoneNumber,
      leadName: leadName,
      callStartTimestamp: callStartTimestamp,
      onUploadSuccess: onUploadSuccess,
    ));
  }

  static Future<void> _trackCallAndSetupUpload({
    required BuildContext context,
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
        : ((staffUserPhone != null && staffUserPhone.isNotEmpty) ? staffUserPhone : 'Staff');
    final callId = DateTime.now().microsecondsSinceEpoch.toString();

    final formattedStart = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(callStartTimestamp));

    debugPrint('=================================================================');
    debugPrint('CALL STARTED -> From: $fromUser | To: $phoneNumber | Start Time: $formattedStart');
    debugPrint('=================================================================');

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
      callStatus: 'UNANSWERED',
    );
    await CallHistoryStorage.addOrUpdateCall(callHistoryEntry);

    // Multi-stage post-call tracking to calculate exact call end time, duration, and scan audio
    for (final delaySec in [3, 8, 15, 30, 45, 60, 90, 120, 180, 240, 300]) {
      Future.delayed(Duration(seconds: delaySec), () async {
        final callRecordingService = CallRecordingService();
        final details = await callRecordingService.getLatestCallDetails(
          phoneNumber: phoneNumber,
          callTimestamp: callStartTimestamp,
        );

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final startMs = details != null && (details['startTime'] as int? ?? 0) > 0
            ? (details['startTime'] as int)
            : callStartTimestamp;
        final endMs = details != null && (details['endTime'] as int? ?? 0) > 0
            ? (details['endTime'] as int)
            : nowMs;
        final durationSec = details != null
            ? (details['durationSeconds'] as int? ?? 0)
            : 0;

        final rawStatus = details != null ? (details['callStatus']?.toString() ?? '') : '';
        final statusStr = rawStatus.isNotEmpty
            ? rawStatus
            : (durationSec > 0 ? 'ANSWERED' : 'UNANSWERED');

        final formattedEnd = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(endMs));

        callHistoryEntry = callHistoryEntry.copyWith(
          startTime: startMs,
          endTime: endMs,
          durationSeconds: durationSec,
          callStatus: statusStr,
        );
        await CallHistoryStorage.addOrUpdateCall(callHistoryEntry);

        debugPrint('=================================================================');
        debugPrint('CALL ENDED -> From: $fromUser | To: $phoneNumber | End Time: $formattedEnd | Duration: ${durationSec}s');
        debugPrint('=================================================================');

        autoScanAndUploadLeadRecordings(
          context: context.mounted ? context : null,
          leadId: leadId,
          phoneNumber: phoneNumber,
          callTimestamp: callStartTimestamp,
          onUploadSuccess: onUploadSuccess,
        );
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

            final callDetails = await CallRecordingService().getLatestCallDetails(
              phoneNumber: phoneNumber,
              callTimestamp: callTimestamp,
            );
            final prefs = await SharedPreferences.getInstance();
            final staffPhone = prefs.getString('userPhone')?.trim() ?? '';

        final meta = await buildAudioMetadata(
              filePath: recordingPath,
              phoneNumber: phoneNumber,
              callTimestamp: callTimestamp,
              callDetails: callDetails,
              staffUserPhone: staffPhone,
            );

            debugPrint('Auto-uploading call recording: $recordingPath for leadId: $leadId with meta: $meta');

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
            );

            result.fold(
              (failure) {
                debugPrint('Auto-upload failed: ${failure.message}');
                if (onUploadSuccess != null) onUploadSuccess();
              },
              (audio) async {
                await _markAsUploaded(recordingPath!, length);
                await CallHistoryStorage.markCallAsSynced(phoneNumber, callTimestamp);
                debugPrint('Call recording auto-uploaded successfully! Audio ID: ${audio.id}');
                if (onUploadSuccess != null) {
                  onUploadSuccess();
                }
              },
            );
          }
        }
      } else {
        debugPrint('No new system recording found for call at $callTimestamp for $phoneNumber');
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
    List<LeadAudio>? existingServerAudios,
    VoidCallback? onUploadSuccess,
  }) async {
    if (phoneNumber.isEmpty) return;

    bool uploadedAny = false;

    try {
      final service = CallRecordingService();
      final allRecordings = await service.getAllSystemRecordings(phoneNumber, callTimestamp: callTimestamp);
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
        final ageMs = DateTime.now().millisecondsSinceEpoch - lastMod.millisecondsSinceEpoch;

        var finalLength = length;
        if (ageMs < 4000) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (!await file.exists()) continue;
          final length2 = await file.length();
          if (length != length2) {
            debugPrint('Recording file $path is actively growing ($length -> $length2 bytes). Live call ongoing, skipping.');
            continue;
          }
          finalLength = length2;
        }

        final fileName = path.split('/').last;
        final cleanName = cleanFileName(fileName);

        if (_currentlyUploadingPaths.contains(path) || _currentlyUploadingPaths.contains(cleanName)) continue;

        if (await isAlreadyUploaded(path, finalLength, existingServerAudios: existingServerAudios)) {
          continue;
        }

        final callDetails = await service.getLatestCallDetails(
          phoneNumber: phoneNumber,
          callTimestamp: callTimestamp,
        );

        final localDurMs = (recording['durationMs'] as num?)?.toInt() ?? 0;
        final localDurSec = (localDurMs / 1000).round();

        final meta = await buildAudioMetadata(
          filePath: path,
          phoneNumber: phoneNumber,
          callTimestamp: callTimestamp,
          callDetails: callDetails,
          staffUserPhone: staffPhone,
          duration: localDurSec > 0 ? localDurSec.toString() : null,
        );

        debugPrint('Auto-uploading call recording ($finalLength bytes): $path for leadId: $leadId with meta: $meta');
        _currentlyUploadingPaths.add(path);
        _currentlyUploadingPaths.add(cleanName);

        var callStatusStrRaw = callDetails != null ? (callDetails['callStatus'] as String? ?? '') : '';
        String callStatusFinal = 'CONNECTED';
        
        if (callStatusStrRaw.toUpperCase() == 'UNANSWERED' || callStatusStrRaw.toUpperCase() == 'REJECTED') {
          callStatusFinal = 'NOT_CONNECTED';
        } else if (callStatusStrRaw.toUpperCase() == 'MISSED') {
          callStatusFinal = 'MISSED';
        }

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
            
            final actualStartMs = (callDetails != null && (callDetails['startTime'] as int? ?? 0) > 0) 
                ? (callDetails['startTime'] as int) 
                : (callTimestamp > 0 ? callTimestamp : (recording['timestamp'] as int? ?? 0));
            await CallHistoryStorage.markCallAsSynced(phoneNumber, actualStartMs);
            
            _currentlyUploadingPaths.remove(path);
            _currentlyUploadingPaths.remove(cleanName);
            if (existingServerAudios != null) {
              existingServerAudios.add(audio);
            }
            uploadedAny = true;
          },
        );
      }

      // ─── Phase 2: Scan & Upload Missed Calls & Unanswered Calls (No Audio File) ───
      final systemCallLogs = await service.getSystemCallLogs(phoneNumber);
      final trackedCallHistory = await CallHistoryStorage.loadCallHistory();

      final leadPhoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
      final leadLast10 = leadPhoneDigits.length >= 10 ? leadPhoneDigits.substring(leadPhoneDigits.length - 10) : leadPhoneDigits;

      final List<Map<String, dynamic>> rawCalls = [];

      for (final log in systemCallLogs) {
        rawCalls.add(log);
      }

      for (final h in trackedCallHistory) {
        final hPhoneDigits = h.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final hLast10 = hPhoneDigits.length >= 10 ? hPhoneDigits.substring(hPhoneDigits.length - 10) : hPhoneDigits;
        if (leadLast10.isNotEmpty && (hLast10 == leadLast10 || hPhoneDigits.contains(leadLast10))) {
          rawCalls.add({
            'id': h.id,
            'phoneNumber': h.phoneNumber,
            'startTime': h.startTime > 0 ? h.startTime : h.timestamp,
            'endTime': h.endTime > 0 ? h.endTime : h.timestamp,
            'durationSeconds': h.durationSeconds,
            'callType': h.callType,
            'callStatus': h.callStatus,
          });
        }
      }

      // Deduplicate raw calls by startTime (within 120 seconds of each other)
      final List<Map<String, dynamic>> allUnuploadedCalls = [];
      for (final call in rawCalls) {
        final st = call['startTime'] as int? ?? 0;
        if (st <= 0) continue;
        final dur = call['durationSeconds'] as int? ?? 0;

        bool isDuplicate = false;
        for (int i = 0; i < allUnuploadedCalls.length; i++) {
          final existingSt = allUnuploadedCalls[i]['startTime'] as int? ?? 0;
          if ((st - existingSt).abs() < 120000) {
            // Keep the entry with higher duration / richer call details
            final existingDur = allUnuploadedCalls[i]['durationSeconds'] as int? ?? 0;
            if (dur > existingDur) {
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

      for (final callLog in allUnuploadedCalls) {
        final startTimeMs = callLog['startTime'] as int? ?? 0;
        if (startTimeMs <= 0) continue;

        // Phase 2 is ONLY for calls without audio files (missed/unanswered).
        // Skip calls that were explicitly answered (duration > 0 and status is ANSWERED/CONNECTED)
        final callDuration = callLog['durationSeconds'] as int? ?? 0;
        final callStatusRaw = (callLog['callStatus'] as String? ?? '').toUpperCase();
        final isExplicitlyAnswered = (callStatusRaw == 'ANSWERED' || callStatusRaw == 'CONNECTED') && callDuration > 0;
        if (isExplicitlyAnswered) {
          debugPrint('Phase 2: Skipping answered call at $startTimeMs (duration=${callDuration}s, status=$callStatusRaw)');
          continue;
        }

        // Check if we ALREADY found a valid device audio recording (>= 100 bytes) for this exact call log
        bool hasDeviceRecording = false;
        final endTimeMs = callLog['endTime'] as int? ?? startTimeMs;
        
        for (final recording in allRecordings) {
          final rPath = recording['path'] as String?;
          if (rPath != null && rPath.isNotEmpty) {
            final f = File(rPath);
            if (f.existsSync() && f.lengthSync() >= 100) {
              final rTime = parseTimestampFromFileName(rPath.split('/').last) ?? (recording['timestamp'] as int? ?? 0);
              if (rTime > 0) {
                // Recording timestamp can be the start of the call (from filename) or end of the call (last modified)
                final diffStart = (rTime - startTimeMs).abs();
                final diffEnd = (rTime - endTimeMs).abs();
                if (diffStart < 120000 || diffEnd < 120000) { // 2 minute tolerance
                  hasDeviceRecording = true;
                  break;
                }
              }
            }
          }
        }

        // If an audio file exists on device for this call, let Phase 1 handle uploading it with audio!
        if (hasDeviceRecording) {
          debugPrint('Call at $startTimeMs has associated device audio recording. Skipping Phase 2 no-audio upload.');
          continue;
        }

        bool alreadySyncedInHistory = false;
        final cPhoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
        final cLast10 = cPhoneDigits.length >= 10 ? cPhoneDigits.substring(cPhoneDigits.length - 10) : cPhoneDigits;

        if (existingServerAudios != null) {
          for (final sAudio in existingServerAudios) {
            if (sAudio.size > 0) continue;
            final parsedTime = parseTimestampFromFileName(sAudio.displayName);
            final audioMs = parsedTime ?? (sAudio.createdAt?.millisecondsSinceEpoch ?? 0);
            if (audioMs > 0 && (audioMs - startTimeMs).abs() < 120000) {
              alreadySyncedInHistory = true;
              break;
            }
          }
        }

        if (!alreadySyncedInHistory) {
          final allPathsToCheck = [..._uploadedPaths, ..._currentlyUploadingPaths];
          for (final uploadedPath in allPathsToCheck) {
            if (uploadedPath.startsWith('missed_')) continue;
            final rTime = parseTimestampFromFileName(uploadedPath.split('/').last.split('_').firstWhere((e) => e.contains(RegExp(r'\d')), orElse: () => '')) ?? parseTimestampFromFileName(uploadedPath.split('/').last);
            if (rTime != null && rTime > 0) {
              final diffStart = (rTime - startTimeMs).abs();
              if (diffStart < 60000) { // 1 min tolerance
                if (cLast10.isNotEmpty && uploadedPath.replaceAll(RegExp(r'\D'), '').contains(cLast10)) {
                  alreadySyncedInHistory = true;
                  break;
                }
              }
            }
          }
        }

        if (alreadySyncedInHistory) {
          debugPrint('Phase 2: Call at $startTimeMs was already synced. Skipping dummy upload.');
          continue;
        }

        final callTypeRaw = (callLog['callType'] as String? ?? 'OUTGOING').toUpperCase();
        final isIncoming = callTypeRaw == 'INCOMING' || callTypeRaw == 'MISSED' || callTypeRaw == 'REJECTED';
        final boundStr = isIncoming ? 'IN' : 'OUT';
        final uniqueKey = 'missed_${boundStr}_${startTimeMs}_$phoneNumber';

        if (_currentlyUploadingPaths.contains(uniqueKey)) continue;

        if (await isAlreadyUploaded(uniqueKey, 0, existingServerAudios: existingServerAudios)) {
          continue;
        }

        final dt = DateTime.fromMillisecondsSinceEpoch(startTimeMs);
        final dateStr = DateFormat('yyyy-MM-dd').format(dt);
        final startTimeStr = DateFormat('HH:mm:ss').format(dt);
        // endTimeMs is already declared above, just use it for endDt
        final endDt = DateTime.fromMillisecondsSinceEpoch(endTimeMs > 0 ? endTimeMs : startTimeMs);
        final endTimeStr = DateFormat('HH:mm:ss').format(endDt);
        // Try fresh read from SharedPreferences if staffPhone is empty
        String effectiveStaffPhone = staffPhone;
        try {
          final freshPrefs = await SharedPreferences.getInstance();
          if (effectiveStaffPhone.isEmpty) {
            effectiveStaffPhone = freshPrefs.getString('userPhone')?.trim() ?? '';
          }
        } catch (_) {}
        // Last resort: get device SIM phone number
        if (effectiveStaffPhone.isEmpty) {
          try {
            effectiveStaffPhone = await CallRecordingService().getDevicePhoneNumber();
          } catch (_) {}
        }
        
        if (effectiveStaffPhone.isEmpty) {
          try {
            effectiveStaffPhone = await StaffPhoneResolver.getOrFetchStaffPhone();
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

        var callStatusStr = (callLog['callStatus'] as String? ?? '').toUpperCase();
        if (callStatusStr.isEmpty) {
          callStatusStr = isIncoming ? 'MISSED' : 'UNANSWERED';
        } else if (callStatusStr == 'NOT_CONNECTED' || callStatusStr == 'NO_ANSWER') {
          callStatusStr = isIncoming ? 'MISSED' : 'UNANSWERED';
        }

        debugPrint('Auto-uploading call metadata ($boundStr, status=$callStatusStr) for leadId: $leadId at $startTimeStr');
        _currentlyUploadingPaths.add(uniqueKey);

        final repo = sl<LeadsRepository>();
        final result = await repo.uploadLeadAudio(
          leadId,
          null, // No audio file for missed call
          bound: boundStr,
          startTime: startTimeStr,
          endTime: endTimeStr,
          from: fromNum,
          to: toNum,
          duration: '0',
          callDate: dateStr,
          callStatus: callStatusStr,
        );

        result.fold(
          (failure) {
            debugPrint('Auto-upload call metadata failed: ${failure.message}');
            _currentlyUploadingPaths.remove(uniqueKey);
            _uploadedPaths.remove(uniqueKey);
            _uploadedPaths.remove('${uniqueKey}_0');
          },
          (audio) async {
            debugPrint('Successfully uploaded call metadata: ${audio.id}');
            await _markAsUploaded(uniqueKey, 0);
            await CallHistoryStorage.markCallAsSynced(phoneNumber, startTimeMs);
            _currentlyUploadingPaths.remove(uniqueKey);
            uploadedAny = true;
          },
        );
      }

      if (uploadedAny && onUploadSuccess != null) {
        onUploadSuccess();
      }
    } catch (e) {
      debugPrint('Error in autoScanAndUploadLeadRecordings: $e');
      if (onUploadSuccess != null) {
        onUploadSuccess();
      }
    }
  }


  static int? parseTimestampFromFileName(String fileName) {
    try {
      // 1. Try parsing directly from raw fileName FIRST (handles filenames like 8220021569(8220021569)_20260921131348.mp3)
      final rawMatch1 = RegExp(r'(?:^|[^0-9])(20[2-3]\d)[-_]?(\d{2})[-_]?(\d{2})[-_._]?(\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?:$|[^0-9])').firstMatch(fileName);
      if (rawMatch1 != null) {
        final yyyy = int.parse(rawMatch1.group(1)!);
        final mm = int.parse(rawMatch1.group(2)!);
        final dd = int.parse(rawMatch1.group(3)!);
        final hh = int.parse(rawMatch1.group(4)!);
        final mi = int.parse(rawMatch1.group(5)!);
        final ss = int.parse(rawMatch1.group(6)!);
        if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31 && hh >= 0 && hh <= 23 && mi >= 0 && mi <= 59 && ss >= 0 && ss <= 59) {
          return DateTime(yyyy, mm, dd, hh, mi, ss).millisecondsSinceEpoch;
        }
      }

      final cleanName = cleanFileName(fileName);

      // Pattern 1: YYYYMMDD_HHMMSS or YYYYMMDDHHMMSS (e.g. 20260911_110844, 20260911110844)
      final p1 = RegExp(r'(?:^|[^0-9])(20[2-3]\d)[-_]?(\d{2})[-_]?(\d{2})[-_._]?(\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?:$|[^0-9])').firstMatch(cleanName);
      if (p1 != null) {
        final yyyy = int.parse(p1.group(1)!);
        final mm = int.parse(p1.group(2)!);
        final dd = int.parse(p1.group(3)!);
        final hh = int.parse(p1.group(4)!);
        final mi = int.parse(p1.group(5)!);
        final ss = int.parse(p1.group(6)!);
        if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31 && hh >= 0 && hh <= 23 && mi >= 0 && mi <= 59 && ss >= 0 && ss <= 59) {
          return DateTime(yyyy, mm, dd, hh, mi, ss).millisecondsSinceEpoch;
        }
      }

      // Pattern 2: Epoch timestamp in ms (13 digits)
      final p2 = RegExp(r'(?:^|[^0-9])(1\d{12})(?:$|[^0-9])').firstMatch(cleanName);
      if (p2 != null) {
        final val = int.tryParse(p2.group(1)!);
        if (val != null && val > 1500000000000 && val < 2500000000000) {
          return val;
        }
      }

      // Pattern 3: YYMMDD_HHMMSS (e.g. 260911_110844)
      final p3 = RegExp(r'(?:^|[^0-9])(\d{2})(\d{2})(\d{2})[-_]?(\d{2})(\d{2})(\d{2})(?:$|[^0-9])').firstMatch(cleanName);
      if (p3 != null) {
        final yy = int.parse(p3.group(1)!);
        final mm = int.parse(p3.group(2)!);
        final dd = int.parse(p3.group(3)!);
        final hh = int.parse(p3.group(4)!);
        final mi = int.parse(p3.group(5)!);
        final ss = int.parse(p3.group(6)!);
        final yyyy = 2000 + yy;
        if (yyyy >= 2020 && yyyy <= 2040 && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31 && hh >= 0 && hh <= 23 && mi >= 0 && mi <= 59 && ss >= 0 && ss <= 59) {
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
    if (resBound.isEmpty) {
      if (lowerName.contains('inbound') || lowerName.contains('incoming')) {
        resBound = 'IN';
      } else if (lowerName.contains('outbound') || lowerName.contains('outgoing')) {
        resBound = 'OUT';
      } else if (callDetails != null && callDetails['callType'] != null) {
        final ct = callDetails['callType'].toString().toUpperCase();
        resBound = (ct == 'INCOMING' || ct == 'INBOUND') ? 'IN' : 'OUT';
      }
    }
    if (resBound.isEmpty) {
      resBound = 'OUT';
    }
    resBound = (resBound == 'INBOUND' || resBound == 'INCOMING') ? 'IN' : ((resBound == 'OUTBOUND' || resBound == 'OUTGOING') ? 'OUT' : resBound);
    meta['bound'] = resBound;

    // 2. Duration calculation (in seconds)
    int durSec = 0;
    if (duration != null && duration.isNotEmpty) {
      durSec = int.tryParse(duration) ?? 0;
    }
    if (durSec <= 0 && callDetails != null && (callDetails['durationSeconds'] as int? ?? 0) > 0) {
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
        if (fileStartMs == null || fileStartMs <= 0 || (s - fileStartMs).abs() < 120000) {
          startMs = s;
          if (e > 0) endMs = e;
          if (durSec <= 0 && d > 0) durSec = d;
        } else {
          debugPrint('callDetails startTime ($s) mismatched with file timestamp ($fileStartMs). Ignoring mismatched CallLog details.');
        }
      }
    }

    // Priority 2: Use fileStartMs if startMs was not matched from callDetails
    if ((startMs == null || startMs <= 0) && fileStartMs != null && fileStartMs > 0) {
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
      if (callDetails != null && (callDetails['durationSeconds'] as int? ?? 0) > 0) {
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
    meta['duration'] = duration ?? durSec.toString();

    // 4. from & to numbers calculation
    String userPhone = (staffUserPhone != null && staffUserPhone.isNotEmpty) ? staffUserPhone : '';

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

