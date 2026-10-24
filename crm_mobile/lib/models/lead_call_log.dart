import 'package:equatable/equatable.dart';

class LeadCallLogResponse extends Equatable {
  final int totalCalls;
  final int totalInboundCalls;
  final int totalOutboundCalls;
  final int totalMissedCalls;
  final int totalUnansweredCalls;
  final int totalDuration;
  final String totalDurationFormatted;
  final int ownerCallCount;
  final int otherCallCount;
  final List<LeadCallLog> callHistory;

  const LeadCallLogResponse({
    required this.totalCalls,
    required this.totalInboundCalls,
    required this.totalOutboundCalls,
    required this.totalMissedCalls,
    this.totalUnansweredCalls = 0,
    required this.totalDuration,
    this.totalDurationFormatted = '00:00:00',
    this.ownerCallCount = 0,
    this.otherCallCount = 0,
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

  static int _parseDurationToSeconds(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    final str = val.toString().trim();
    if (str.isEmpty || str == 'null') return 0;
    if (str.contains(':')) {
      final parts = str.split(':').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^\d]'), '')) ?? 0).toList();
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      } else if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      }
    }
    return num.tryParse(str)?.toInt() ?? 0;
  }

  static String _formatDurationSeconds(int seconds) {
    if (seconds <= 0) return '00:00:00';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final remainingSeconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  factory LeadCallLogResponse.fromJson(Map<String, dynamic> json) {
    final historyRaw = json['callHistory'] ??
        json['call_history'] ??
        json['callLogs'] ??
        json['call_logs'] ??
        json['calls'] ??
        json['history'] ??
        json['logs'] ??
        json['content'] ??
        json['data'];

    List<LeadCallLog> history = [];
    if (historyRaw is List) {
      history = historyRaw
          .whereType<Map>()
          .map((e) => LeadCallLog.fromJson(Map<String, dynamic>.from(e)))
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
                final b = l.bound.toUpperCase();
                final isIn = b == 'IN' || b == 'INBOUND' || b.startsWith('IN');
                final st = l.callStatus.toUpperCase();
                final notConn = st == 'MISSED' || st == 'REJECTED' || st == 'UNANSWERED' || st == 'NOT_CONNECTED' || st == 'NO_ANSWER';
                return isIn && notConn;
              }).length);

    final totalUnansweredVal = json.containsKey('totalUnansweredCalls')
        ? _parseNum(json['totalUnansweredCalls'])
        : (json.containsKey('total_unanswered_calls')
            ? _parseNum(json['total_unanswered_calls'])
            : history.where((l) {
                final b = l.bound.toUpperCase();
                final isOut = b == 'OUT' || b == 'OUTBOUND' || b.startsWith('OUT');
                final st = l.callStatus.toUpperCase();
                final notConn = st == 'MISSED' || st == 'REJECTED' || st == 'UNANSWERED' || st == 'NOT_CONNECTED' || st == 'NO_ANSWER' || st == 'CANCELLED';
                return isOut && notConn;
              }).length);

    // Parse duration whether provided as int seconds, totalDurationSeconds, or "00:00:00" string
    int totalDurationVal = 0;
    if (json.containsKey('totalDurationSeconds') && json['totalDurationSeconds'] != null) {
      totalDurationVal = _parseNum(json['totalDurationSeconds']);
    } else {
      totalDurationVal = _parseDurationToSeconds(json['totalDuration'] ?? json['total_duration']);
    }

    String totalDurationFormattedVal = '';
    if (json.containsKey('totalDurationFormatted') && json['totalDurationFormatted'] != null && json['totalDurationFormatted'].toString().isNotEmpty) {
      totalDurationFormattedVal = json['totalDurationFormatted'].toString();
    } else {
      final rawDur = (json['totalDuration'] ?? json['total_duration'])?.toString() ?? '';
      if (rawDur.contains(':')) {
        totalDurationFormattedVal = rawDur;
      } else {
        totalDurationFormattedVal = _formatDurationSeconds(totalDurationVal);
      }
    }

    final ownerCallCountVal = _parseNum(json['ownerCallCount'] ?? json['owner_call_count']);
    final otherCallCountVal = _parseNum(json['otherCallCount'] ?? json['other_call_count']);

    return LeadCallLogResponse(
      totalCalls: totalCallsVal,
      totalInboundCalls: totalInboundVal,
      totalOutboundCalls: totalOutboundVal,
      totalMissedCalls: totalMissedVal,
      totalUnansweredCalls: totalUnansweredVal,
      totalDuration: totalDurationVal,
      totalDurationFormatted: totalDurationFormattedVal,
      ownerCallCount: ownerCallCountVal,
      otherCallCount: otherCallCountVal,
      callHistory: history,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalCalls': totalCalls,
      'totalInboundCalls': totalInboundCalls,
      'totalOutboundCalls': totalOutboundCalls,
      'totalMissedCalls': totalMissedCalls,
      'totalUnansweredCalls': totalUnansweredCalls,
      'totalDuration': totalDuration,
      'totalDurationFormatted': totalDurationFormatted,
      'totalDurationSeconds': totalDuration,
      'ownerCallCount': ownerCallCount,
      'otherCallCount': otherCallCount,
      'callHistory': callHistory.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        totalCalls,
        totalInboundCalls,
        totalOutboundCalls,
        totalMissedCalls,
        totalUnansweredCalls,
        totalDuration,
        totalDurationFormatted,
        ownerCallCount,
        otherCallCount,
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
      startTime: json['startTime']?.toString() ?? json['start_time']?.toString() ?? json['startTimeStr']?.toString() ?? json['callStartTime']?.toString() ?? json['call_start_time']?.toString() ?? '',
      endTime: json['endTime']?.toString() ?? json['end_time']?.toString() ?? json['endTimeStr']?.toString() ?? json['callEndTime']?.toString() ?? json['call_end_time']?.toString() ?? '',
      fromNumber: json['fromNumber']?.toString() ?? json['from_number']?.toString() ?? json['from']?.toString() ?? json['callerNumber']?.toString() ?? json['caller_number']?.toString() ?? json['caller']?.toString() ?? '',
      toNumber: json['toNumber']?.toString() ?? json['to_number']?.toString() ?? json['to']?.toString() ?? json['receiverNumber']?.toString() ?? json['receiver_number']?.toString() ?? json['receiver']?.toString() ?? '',
      duration: json['duration']?.toString() ?? json['durationFormatted']?.toString() ?? json['durationSeconds']?.toString() ?? json['duration_seconds']?.toString() ?? '',
      callDate: json['callDate']?.toString() ?? json['call_date']?.toString() ?? json['date']?.toString() ?? '',
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

