import 'package:flutter/services.dart';

class CallRecordingService {
  static const MethodChannel _channel = MethodChannel('com.example.crm_mobile/call_recording');

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

  Future<List<Map<String, dynamic>>> getAllSystemRecordings(String phoneNumber) async {
    try {
      final List<dynamic>? recordings = await _channel.invokeMethod('getAllSystemRecordings', {
        'phoneNumber': phoneNumber,
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

  Future<void> playRecording(String path) async {
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
}
