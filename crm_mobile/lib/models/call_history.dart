import 'package:intl/intl.dart';

/// Represents a tracked phone call record containing duration, timestamps, and caller details.
class CallHistory {
  final String id;
  final String phoneNumber; // Target (To) number
  final String? contactName;
  final String callType; // OUTGOING or INCOMING
  final int timestamp; // Initial timestamp in epoch ms
  final int durationSeconds; // Duration of call in seconds
  final int startTime; // Start time (from time) in epoch ms
  final int endTime; // End time (to time) in epoch ms
  final String? appUserId;
  final String? appUserName;
  final String? appUserPhone; // Caller (From) number
  final String? recordingUrl;
  final bool isSynced;

  CallHistory({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    this.callType = 'OUTGOING',
    required this.timestamp,
    this.durationSeconds = 0,
    required this.startTime,
    required this.endTime,
    this.appUserId,
    this.appUserName,
    this.appUserPhone,
    this.recordingUrl,
    this.isSynced = false,
  });

  String get fromNumber => appUserPhone ?? 'Unknown';
  String get toNumber => phoneNumber;

  String get formattedStartTime {
    if (startTime <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(startTime);
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(dt);
  }

  String get formattedEndTime {
    if (endTime <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(endTime);
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(dt);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phoneNumber': phoneNumber,
        'contactName': contactName,
        'callType': callType,
        'timestamp': timestamp,
        'durationSeconds': durationSeconds,
        'startTime': startTime,
        'endTime': endTime,
        'appUserId': appUserId,
        'appUserName': appUserName,
        'appUserPhone': appUserPhone,
        'recordingUrl': recordingUrl,
        'isSynced': isSynced,
      };

  factory CallHistory.fromJson(Map<String, dynamic> json) {
    return CallHistory(
      id: (json['id'] ?? '').toString(),
      phoneNumber: (json['phoneNumber'] ?? json['toNumber'] ?? '').toString(),
      contactName: json['contactName']?.toString(),
      callType: (json['callType'] ?? 'OUTGOING').toString(),
      timestamp: json['timestamp'] is int
          ? json['timestamp']
          : (int.tryParse(json['timestamp']?.toString() ?? '0') ?? 0),
      durationSeconds: json['durationSeconds'] is int
          ? json['durationSeconds']
          : (int.tryParse(json['durationSeconds']?.toString() ?? '0') ?? 0),
      startTime: json['startTime'] is int
          ? json['startTime']
          : (int.tryParse(json['startTime']?.toString() ?? '0') ?? 0),
      endTime: json['endTime'] is int
          ? json['endTime']
          : (int.tryParse(json['endTime']?.toString() ?? '0') ?? 0),
      appUserId: json['appUserId']?.toString(),
      appUserName: json['appUserName']?.toString(),
      appUserPhone: json['appUserPhone']?.toString(),
      recordingUrl: json['recordingUrl']?.toString(),
      isSynced: json['isSynced'] == true,
    );
  }

  CallHistory copyWith({
    String? id,
    String? phoneNumber,
    String? contactName,
    String? callType,
    int? timestamp,
    int? durationSeconds,
    int? startTime,
    int? endTime,
    String? appUserId,
    String? appUserName,
    String? appUserPhone,
    String? recordingUrl,
    bool? isSynced,
  }) {
    return CallHistory(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      callType: callType ?? this.callType,
      timestamp: timestamp ?? this.timestamp,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      appUserId: appUserId ?? this.appUserId,
      appUserName: appUserName ?? this.appUserName,
      appUserPhone: appUserPhone ?? this.appUserPhone,
      recordingUrl: recordingUrl ?? this.recordingUrl,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
