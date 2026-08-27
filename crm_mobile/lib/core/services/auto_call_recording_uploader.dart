import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/injection/injection.dart';

class AutoCallRecordingUploader {
  static const String _prefKey = 'uploaded_call_recordings_v5';
  static final Set<String> _uploadedPaths = {};
  static final Set<String> _failedUploads = {};
  static final Set<String> _currentlyUploadingPaths = {};
  static bool _prefsLoaded = false;

  static void clearFailedUploads() {
    _failedUploads.clear();
    _currentlyUploadingPaths.clear();
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

  static Future<void> _markAsUploaded(String path, int length) async {
    await _ensurePrefsLoaded();
    final fileName = path.split('/').last;
    final cleanName = cleanFileName(fileName);

    _uploadedPaths.add('${path}_$length');
    _uploadedPaths.add('${fileName}_$length');
    _uploadedPaths.add('${cleanName}_$length');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _uploadedPaths.toList());
    } catch (e) {
      debugPrint('Error saving uploaded recording prefs: $e');
    }
  }

  static String cleanFileName(String name) {
    var clean = name;
    while (clean.startsWith('REC_')) {
      final parts = clean.split('_');
      if (parts.length >= 4 && (parts[1] == 'INCOMING' || parts[1] == 'OUTGOING')) {
        clean = parts.sublist(3).join('_');
      } else if (parts.length >= 3) {
        clean = parts.sublist(2).join('_');
      } else {
        clean = clean.substring(4);
      }
    }
    return clean;
  }

  static Future<bool> isAlreadyUploaded(String path, int length) async {
    await _ensurePrefsLoaded();

    // Ignore tiny incomplete fragments under 25 KB (< 3 seconds of speech)
    if (length < 25000) return true;

    if (_uploadedPaths.contains('${path}_$length')) return true;

    final fileName = path.split('/').last;
    if (_uploadedPaths.contains('${fileName}_$length')) return true;

    final clean = cleanFileName(fileName);
    if (_uploadedPaths.contains('${clean}_$length')) return true;

    // If an equal or larger version (or within 5 KB tolerance) was uploaded, skip re-uploading
    for (final key in _uploadedPaths) {
      if (key.startsWith('${clean}_') || key.startsWith('${fileName}_')) {
        final parts = key.split('_');
        final prevLength = int.tryParse(parts.last) ?? 0;
        if (prevLength > 0 && (length <= prevLength || (length - prevLength).abs() < 5120)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Initiates a phone call to [phoneNumber] for [leadId] and automatically scans
  /// for the call recording when the call finishes, uploading it directly to the backend.
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

    try {
      await FlutterPhoneDirectCaller.callNumber(phoneNumber);
    } catch (e) {
      debugPrint('Error placing phone call: $e');
    }

    // Schedule post-call scans (3s, 8s, 15s, 30s) so finalized recordings are uploaded quickly after call ends
    for (final delaySec in [3, 8, 15, 30]) {
      Future.delayed(Duration(seconds: delaySec), () {
        autoScanAndUploadLeadRecordings(
          context: context,
          leadId: leadId,
          phoneNumber: phoneNumber,
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
          final length = await file.length();
          if (length > 0) {
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
    VoidCallback? onUploadSuccess,
  }) async {
    if (phoneNumber.isEmpty) return;

    try {
      final service = CallRecordingService();
      final allRecordings = await service.getAllSystemRecordings(phoneNumber);

      bool uploadedAny = false;

      for (final recording in allRecordings) {
        final path = recording['path'] as String?;
        if (path == null || path.isEmpty) continue;

        final file = File(path);
        if (!await file.exists()) continue;
        final length = await file.length();
        if (length <= 0) continue;

        // Perform stability check ONLY if file was modified in the last 4 seconds
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

        if (await isAlreadyUploaded(path, finalLength)) {
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
            uploadedAny = true;
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

