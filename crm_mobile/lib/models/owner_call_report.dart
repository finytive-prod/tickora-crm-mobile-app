import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

class CalledLeadReport extends Equatable {
  final String leadId;
  final String leadName;
  final String duration;
  final String callType;
  final String callStatus;
  final String? callHandledBy;
  final String? callDate;
  final String? startTime;
  final String? createdAt;
  final DateTime? callDateTime;

  const CalledLeadReport({
    required this.leadId,
    required this.leadName,
    required this.duration,
    required this.callType,
    required this.callStatus,
    this.callHandledBy,
    this.callDate,
    this.startTime,
    this.createdAt,
    this.callDateTime,
  });

  String get formattedCreatedAt {
    DateTime? dt = callDateTime;
    if (dt == null && createdAt != null && createdAt!.trim().isNotEmpty) {
      dt = DateTime.tryParse(createdAt!.trim());
    }
    if (dt != null) {
      final local = dt.toLocal();
      final raw = createdAt?.trim() ?? '';
      if (!raw.contains(':') && local.hour == 0 && local.minute == 0 && local.second == 0) {
        return DateFormat('dd MMM yyyy').format(local);
      }
      return DateFormat('dd MMM yyyy, hh:mm a').format(local);
    }
    return createdAt?.trim() ?? '';
  }

  factory CalledLeadReport.fromJson(Map<String, dynamic> json) {
    final dateStr = json['callDate']?.toString() ?? json['call_date']?.toString() ?? json['date']?.toString();
    final timeStr = json['startTime']?.toString() ?? json['start_time']?.toString() ?? json['callTime']?.toString() ?? json['call_time']?.toString() ?? json['time']?.toString();
    final createdStr = json['createdAt']?.toString() ?? json['created_at']?.toString() ?? json['timestamp']?.toString();

    DateTime? dt;
    if (createdStr != null && createdStr.isNotEmpty) {
      dt = DateTime.tryParse(createdStr);
    }
    if (dt == null && (dateStr != null && dateStr.isNotEmpty)) {
      if (timeStr != null && timeStr.isNotEmpty && timeStr.contains(':')) {
        dt = DateTime.tryParse('${dateStr.trim()} ${timeStr.trim()}');
        if (dt == null && timeStr.length <= 8) {
          dt = DateTime.tryParse('${dateStr.trim()}T${timeStr.trim()}');
        }
      }
      dt ??= DateTime.tryParse(dateStr.trim());
    }

    return CalledLeadReport(
      leadId: json['leadId']?.toString() ?? '',
      leadName: json['leadName']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '00:00:00',
      callType: json['callType']?.toString() ?? '',
      callStatus: json['callStatus']?.toString() ?? '',
      callHandledBy: json['callHandledBy']?.toString(),
      callDate: dateStr,
      startTime: timeStr,
      createdAt: createdStr,
      callDateTime: dt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'leadId': leadId,
      'leadName': leadName,
      'duration': duration,
      'callType': callType,
      'callStatus': callStatus,
      'callHandledBy': callHandledBy,
      if (callDate != null) 'callDate': callDate,
      if (startTime != null) 'startTime': startTime,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  @override
  List<Object?> get props => [
        leadId,
        leadName,
        duration,
        callType,
        callStatus,
        callHandledBy,
        callDate,
        startTime,
        createdAt,
        callDateTime,
      ];
}

class OwnerCallReport extends Equatable {
  final String ownerId;
  final String ownerName;
  final String? callHandledBy;
  final int totalCallsCount;
  final String totalDuration;
  final int incomingCalls;
  final String incomingCallsDuration;
  final int outgoingCalls;
  final String outgoingCallsDuration;
  final int connectedCallsCount;
  final int notConnectedCallsCount;
  final String? mostTalkedLeadName;
  final String? mostTalkedLeadDuration;
  final int? callTarget;
  final String? callTargetPercentage;
  final String? callTimeTarget;
  final String? callTimeTargetPercentage;
  final List<CalledLeadReport> calledLeads;

  const OwnerCallReport({
    required this.ownerId,
    required this.ownerName,
    this.callHandledBy,
    required this.totalCallsCount,
    required this.totalDuration,
    required this.incomingCalls,
    required this.incomingCallsDuration,
    required this.outgoingCalls,
    required this.outgoingCallsDuration,
    this.connectedCallsCount = 0,
    this.notConnectedCallsCount = 0,
    this.mostTalkedLeadName,
    this.mostTalkedLeadDuration,
    this.callTarget,
    this.callTargetPercentage,
    this.callTimeTarget,
    this.callTimeTargetPercentage,
    this.calledLeads = const [],
  });

  factory OwnerCallReport.fromJson(Map<String, dynamic> json) {
    final leadsList = json['calledLeads'];
    final List<CalledLeadReport> parsedCalledLeads = (leadsList is List)
        ? leadsList
            .whereType<Map<String, dynamic>>()
            .map((e) => CalledLeadReport.fromJson(e))
            .toList()
        : const [];

    // Order calls chronologically newest first so new call logs appear sequentially at the top
    final List<CalledLeadReport> sortedCalledLeads = List<CalledLeadReport>.from(parsedCalledLeads.reversed);
    final bool hasTimestamps = sortedCalledLeads.any((l) => l.callDateTime != null);
    if (hasTimestamps) {
      sortedCalledLeads.sort((a, b) {
        if (a.callDateTime != null && b.callDateTime != null) {
          return b.callDateTime!.compareTo(a.callDateTime!);
        } else if (a.callDateTime != null) {
          return -1;
        } else if (b.callDateTime != null) {
          return 1;
        }
        return 0;
      });
    }

    final List<CalledLeadReport> deduplicatedCalledLeads = [];
    final Set<String> seenLeadCalls = {};
    for (final call in sortedCalledLeads) {
      final leadKey = call.leadId.isNotEmpty ? call.leadId : call.leadName.trim().toLowerCase();
      final dt = call.callDateTime;
      final timeKey = dt != null
          ? (dt.millisecondsSinceEpoch ~/ 1000) * 1000
          : (call.callDate ?? '') + (call.startTime ?? '') + (call.createdAt ?? '');
      final key = '${leadKey}_${call.callType}_${call.duration}_$timeKey';
      if (seenLeadCalls.add(key)) {
        deduplicatedCalledLeads.add(call);
      }
    }

    return OwnerCallReport(
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? 'Unknown',
      callHandledBy: json['callHandledBy']?.toString(),
      totalCallsCount: (json['totalCallsCount'] as num?)?.toInt() ?? 0,
      totalDuration: json['totalDuration']?.toString() ?? '00:00:00',
      incomingCalls: (json['incomingCalls'] as num?)?.toInt() ?? 0,
      incomingCallsDuration: json['incomingCallsDuration']?.toString() ?? '00:00:00',
      outgoingCalls: (json['outgoingCalls'] as num?)?.toInt() ?? 0,
      outgoingCallsDuration: json['outgoingCallsDuration']?.toString() ?? '00:00:00',
      connectedCallsCount: (json['connectedCallsCount'] as num?)?.toInt() ?? 0,
      notConnectedCallsCount: (json['notConnectedCallsCount'] as num?)?.toInt() ?? 0,
      mostTalkedLeadName: json['mostTalkedLeadName']?.toString(),
      mostTalkedLeadDuration: json['mostTalkedLeadDuration']?.toString(),
      callTarget: (json['callTarget'] as num?)?.toInt(),
      callTargetPercentage: json['callTargetPercentage']?.toString(),
      callTimeTarget: json['callTimeTarget']?.toString(),
      callTimeTargetPercentage: json['callTimeTargetPercentage']?.toString(),
      calledLeads: deduplicatedCalledLeads,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'callHandledBy': callHandledBy,
      'totalCallsCount': totalCallsCount,
      'totalDuration': totalDuration,
      'incomingCalls': incomingCalls,
      'incomingCallsDuration': incomingCallsDuration,
      'outgoingCalls': outgoingCalls,
      'outgoingCallsDuration': outgoingCallsDuration,
      'connectedCallsCount': connectedCallsCount,
      'notConnectedCallsCount': notConnectedCallsCount,
      'mostTalkedLeadName': mostTalkedLeadName,
      'mostTalkedLeadDuration': mostTalkedLeadDuration,
      'callTarget': callTarget,
      'callTargetPercentage': callTargetPercentage,
      'callTimeTarget': callTimeTarget,
      'callTimeTargetPercentage': callTimeTargetPercentage,
      'calledLeads': calledLeads.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        ownerId,
        ownerName,
        callHandledBy,
        totalCallsCount,
        totalDuration,
        incomingCalls,
        incomingCallsDuration,
        outgoingCalls,
        outgoingCallsDuration,
        connectedCallsCount,
        notConnectedCallsCount,
        mostTalkedLeadName,
        mostTalkedLeadDuration,
        callTarget,
        callTargetPercentage,
        callTimeTarget,
        callTimeTargetPercentage,
        calledLeads,
      ];
}
