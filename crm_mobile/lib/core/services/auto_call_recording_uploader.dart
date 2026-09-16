import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/call_history_storage.dart';
import 'package:crm_mobile/core/services/direct_call_helper.dart';
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
          .replaceAll(RegExp(r'^\d{7,15}_', caseSensitive: false), '');
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

    // Ignore empty/corrupted fragments under 100 bytes
    if (length < 100) return true;

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
      // If not found on server, allow re-upload regardless of stale local cache
      return false;
    }

    if (_uploadedPaths.contains('${path}_$length')) return true;
    if (_uploadedPaths.contains(fileName) || _uploadedPaths.contains('${fileName}_$length')) return true;
    if (_uploadedPaths.contains(clean) || _uploadedPaths.contains('${clean}_$length')) return true;

    for (final key in _uploadedPaths) {
      if (key.startsWith('${clean}_') || key.startsWith('${fileName}_') || key == clean || key == fileName) {
        return true;
      }
    }

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
    );
    await CallHistoryStorage.addOrUpdateCall(callHistoryEntry);

    try {
      await DirectCallHelper.makeCall(phoneNumber);
    } catch (e) {
      debugPrint('Error placing phone call: $e');
    }

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
        final durationSec = details != null && (details['durationSeconds'] as int? ?? 0) > 0
            ? (details['durationSeconds'] as int)
            : ((endMs - startMs) ~/ 1000);

        final formattedEnd = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(endMs));

        callHistoryEntry = callHistoryEntry.copyWith(
          startTime: startMs,
          endTime: endMs,
          durationSeconds: durationSec,
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

            debugPrint('Auto-uploading call recording: $recordingPath for leadId: $leadId');

            final repo = sl<LeadsRepository>();
            final result = await repo.uploadLeadAudio(leadId, recordingPath);

            result.fold(
              (failure) {
                debugPrint('Auto-upload failed: ${failure.message}');
                if (onUploadSuccess != null) onUploadSuccess();
              },
              (audio) async {
                await _markAsUploaded(recordingPath!, length);
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

    try {
      final service = CallRecordingService();
      final allRecordings = await service.getAllSystemRecordings(phoneNumber, callTimestamp: callTimestamp);

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

        debugPrint('Auto-uploading call recording ($finalLength bytes): $path for leadId: $leadId');
        _currentlyUploadingPaths.add(path);
        _currentlyUploadingPaths.add(cleanName);

        final repo = sl<LeadsRepository>();
        final result = await repo.uploadLeadAudio(leadId, path);

        result.fold(
          (failure) {
            debugPrint('Auto-upload failed for $path: ${failure.message}');
            _currentlyUploadingPaths.remove(path);
            _currentlyUploadingPaths.remove(cleanName);
          },
          (audio) async {
            debugPrint('Successfully uploaded recording: ${audio.id}');
            await _markAsUploaded(path, finalLength);
            _currentlyUploadingPaths.remove(path);
            _currentlyUploadingPaths.remove(cleanName);
          },
        );
      }

      if (onUploadSuccess != null) {
        onUploadSuccess();
      }
    } catch (e) {
      debugPrint('Error in autoScanAndUploadLeadRecordings: $e');
      if (onUploadSuccess != null) {
        onUploadSuccess();
      }
    }
  }
}

