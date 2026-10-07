import 'package:equatable/equatable.dart';

class LeadCallLogResponse extends Equatable {
  final int totalCalls;
  final int totalInboundCalls;
  final int totalOutboundCalls;
  final int totalMissedCalls;
  final int totalDuration;
  final List<LeadCallLog> callHistory;

  const LeadCallLogResponse({
    required this.totalCalls,
    required this.totalInboundCalls,
    required this.totalOutboundCalls,
    required this.totalMissedCalls,
    required this.totalDuration,
    required this.callHistory,
  });

  static int _parseNum(dynamic val, [int fallback = 0]) {
    if (val is num) return val.toInt();
    if (val != null) {
      final parsed = num.tryParse(val.toString());
      if (parsed != null) return parsed.toInt();
    }
    return fallback;
  }

  factory LeadCallLogResponse.fromJson(Map<String, dynamic> json) {
    final historyRaw = json['callHistory'] ??
        json['call_history'] ??
        json['callLogs'] ??
        json['call_logs'] ??
        json['content'] ??
        json['data'];

    List<LeadCallLog> history = [];
    if (historyRaw is List) {
      history = historyRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => LeadCallLog.fromJson(e))
          .toList();
    }

    final totalCallsVal = json.containsKey('totalCalls')
        ? _parseNum(json['totalCalls'])
        : (json.containsKey('total_calls') ? _parseNum(json['total_calls']) : history.length);

    final totalInboundVal = json.containsKey('totalInboundCalls')
        ? _parseNum(json['totalInboundCalls'])
        : (json.containsKey('total_inbound_calls')
            ? _parseNum(json['total_inbound_calls'])
            : history.where((l) {
                final b = l.bound.toUpperCase();
                return b == 'IN' || b == 'INBOUND' || b.startsWith('IN');
              }).length);

    final totalOutboundVal = json.containsKey('totalOutboundCalls')
        ? _parseNum(json['totalOutboundCalls'])
        : (json.containsKey('total_outbound_calls')
            ? _parseNum(json['total_outbound_calls'])
            : history.where((l) {
                final b = l.bound.toUpperCase();
                return b == 'OUT' || b == 'OUTBOUND' || b.startsWith('OUT');
              }).length);

    final totalMissedVal = json.containsKey('totalMissedCalls')
        ? _parseNum(json['totalMissedCalls'])
        : (json.containsKey('total_missed_calls')
            ? _parseNum(json['total_missed_calls'])
            : history.where((l) {
                final st = l.callStatus.toUpperCase();
                return st == 'MISSED' || st == 'REJECTED' || st == 'UNANSWERED' || st == 'NOT_CONNECTED';
              }).length);

    final totalDurationVal = _parseNum(json['totalDuration'] ?? json['total_duration']);

    return LeadCallLogResponse(
      totalCalls: totalCallsVal,
      totalInboundCalls: totalInboundVal,
      totalOutboundCalls: totalOutboundVal,
      totalMissedCalls: totalMissedVal,
      totalDuration: totalDurationVal,
      callHistory: history,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalCalls': totalCalls,
      'totalInboundCalls': totalInboundCalls,
      'totalOutboundCalls': totalOutboundCalls,
      'totalMissedCalls': totalMissedCalls,
      'totalDuration': totalDuration,
      'callHistory': callHistory.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        totalCalls,
        totalInboundCalls,
        totalOutboundCalls,
        totalMissedCalls,
        totalDuration,
        callHistory,
      ];
}

class LeadCallLog extends Equatable {
  final String id;
  final String leadId;
  final String bound;
  final String startTime;
  final String endTime;
  final String fromNumber;
  final String toNumber;
  final String duration;
  final String callDate;
  final String callStatus;
  final String createdAt;

  const LeadCallLog({
    required this.id,
    required this.leadId,
    required this.bound,
    required this.startTime,
    required this.endTime,
    required this.fromNumber,
    required this.toNumber,
    required this.duration,
    required this.callDate,
    required this.callStatus,
    required this.createdAt,
  });

  factory LeadCallLog.fromJson(Map<String, dynamic> json) {
    return LeadCallLog(
      id: json['id']?.toString() ?? '',
      leadId: json['leadId']?.toString() ?? json['lead_id']?.toString() ?? '',
      bound: json['bound']?.toString() ?? json['direction']?.toString() ?? json['callType']?.toString() ?? json['call_type']?.toString() ?? json['type']?.toString() ?? '',
      startTime: json['startTime']?.toString() ?? json['start_time']?.toString() ?? json['startTimeStr']?.toString() ?? '',
      endTime: json['endTime']?.toString() ?? json['end_time']?.toString() ?? json['endTimeStr']?.toString() ?? '',
      fromNumber: json['fromNumber']?.toString() ?? json['from_number']?.toString() ?? json['from']?.toString() ?? '',
      toNumber: json['toNumber']?.toString() ?? json['to_number']?.toString() ?? json['to']?.toString() ?? '',
      duration: json['duration']?.toString() ?? json['durationSeconds']?.toString() ?? json['duration_seconds']?.toString() ?? '',
      callDate: json['callDate']?.toString() ?? json['call_date']?.toString() ?? '',
      callStatus: json['callStatus']?.toString() ?? json['status']?.toString() ?? json['call_status']?.toString() ?? json['callState']?.toString() ?? json['state']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'leadId': leadId,
      'bound': bound,
      'startTime': startTime,
      'endTime': endTime,
      'fromNumber': fromNumber,
      'toNumber': toNumber,
      'duration': duration,
      'callDate': callDate,
      'callStatus': callStatus,
      'createdAt': createdAt,
    };
  }

  @override
  List<Object?> get props => [
        id,
        leadId,
        bound,
        startTime,
        endTime,
        fromNumber,
        toNumber,
        duration,
        callDate,
        callStatus,
        createdAt,
      ];
}

