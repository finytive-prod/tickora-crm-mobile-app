import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:crm_mobile/widgets/in_app_audio_player_modal.dart';

class CallRecordingService {
  static const MethodChannel _channel = MethodChannel('com.example.crm_mobile/call_recording');

  Future<bool> requestPermissionsSequentially() async {
    try {
      final bool result = await _channel.invokeMethod('requestPermissionsSequentially');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request permissions sequentially: '${e.message}'.");
      return false;
    }
  }

  Future<bool> hasStoragePermission() async {
    try {
      final bool result = await _channel.invokeMethod('hasStoragePermission');
      return result;
    } on PlatformException catch (e) {
      print("Failed to check storage permission: '${e.message}'.");
      return false;
    }
  }

  Future<void> openStoragePermissionSettings() async {
    try {
      await _channel.invokeMethod('openStoragePermissionSettings');
    } on PlatformException catch (e) {
      print("Failed to open storage permission settings: '${e.message}'.");
    }
  }

  Future<bool> requestAllFilesAccess() async {
    try {
      final bool result = await _channel.invokeMethod('requestAllFilesAccess');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request all files access: '${e.message}'.");
      return false;
    }
  }


  Future<String?> findLatestSystemRecording({
    required int callTimestamp,
    String phoneNumber = "",
  }) async {
    try {
      final String? path = await _channel.invokeMethod('findLatestSystemRecording', {
        'callTimestamp': callTimestamp,
        'phoneNumber': phoneNumber,
      });
      return path;
    } on PlatformException catch (e) {
      print("Failed to find latest system recording: '${e.message}'.");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllSystemRecordings(String phoneNumber, {int callTimestamp = 0}) async {
    try {
      final List<dynamic>? recordings = await _channel.invokeMethod('getAllSystemRecordings', {
        'phoneNumber': phoneNumber,
        'callTimestamp': callTimestamp,
      });
      if (recordings == null) return [];
      
      return recordings.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return map;
      }).toList();
    } on PlatformException catch (e) {
      print("Failed to get all system recordings: '${e.message}'.");
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestCallDetails({
    required String phoneNumber,
    int callTimestamp = 0,
  }) async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('getLatestCallDetails', {
        'phoneNumber': phoneNumber,
        'callTimestamp': callTimestamp,
      });
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } on PlatformException catch (e) {
      print("Failed to get latest call details: '${e.message}'.");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getSystemCallLogs(String phoneNumber) async {
    try {
      final List<dynamic>? res = await _channel.invokeMethod('getSystemCallLogs', {
        'phoneNumber': phoneNumber,
      });
      if (res != null) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      print("Failed to get system call logs: '${e.message}'.");
      return [];
    }
  }

  /// Gets the device's own phone number from SIM / call log.
  /// Returns the phone number string, or empty string if unavailable.
  Future<String> getDevicePhoneNumber() async {
    try {
      final String? result = await _channel.invokeMethod('getDevicePhoneNumber');
      return result ?? '';
    } on PlatformException catch (e) {
      print("Failed to get device phone number: '${e.message}'.");
      return '';
    }
  }

  Future<void> playRecording(String path, {BuildContext? context, String? title, Function(int)? onDurationFound}) async {
    if (context != null && context.mounted) {
      InAppAudioPlayerModal.show(context, filePath: path, title: title ?? 'Recording', onDurationFound: onDurationFound);
      return;
    }

    try {
      await _channel.invokeMethod('playRecording', {
        'path': path,
      });
    } on PlatformException catch (e) {
      print("Failed to play recording: '${e.message}'.");
    }
  }

  Future<String?> saveToDownloads({
    required String filePath,
    required String fileName,
    String? mimeType,
  }) async {
    try {
      final String? savedPath = await _channel.invokeMethod('saveToDownloads', {
        'filePath': filePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return savedPath;
    } on PlatformException catch (e) {
      print("Failed to save to downloads: '${e.message}'.");
      return null;
    }
  }

  Future<String> detectCallType({
    required String filePath,
    required String fileName,
    required String phoneNumber,
    required int timestamp,
    int callTimestamp = 0,
  }) async {
    try {
      final String? type = await _channel.invokeMethod('detectCallType', {
        'filePath': filePath,
        'fileName': fileName,
        'phoneNumber': phoneNumber,
        'timestamp': timestamp,
        'callTimestamp': callTimestamp,
      });
      return type ?? 'inbound';
    } on PlatformException catch (e) {
      print("Failed to detect call type: '${e.message}'.");
      return 'inbound';
    }
  }

  Future<int> getAudioDuration(String filePath) async {
    try {
      final int ms = await _channel.invokeMethod('getAudioDuration', {'filePath': filePath});
      return ms;
    } on PlatformException catch (e) {
      print("Failed to get audio duration: '${e.message}'.");
      return 0;
    }
  }

  Future<void> playNativeAudio(String path) async {
    try {
      await _channel.invokeMethod('playNativeAudio', {
        'path': path,
      });
    } on PlatformException catch (e) {
      print("Failed to play native audio: '${e.message}'.");
    }
  }
}
