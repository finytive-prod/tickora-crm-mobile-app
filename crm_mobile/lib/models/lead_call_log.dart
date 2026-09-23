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

  factory LeadCallLogResponse.fromJson(Map<String, dynamic> json) {
    return LeadCallLogResponse(
      totalCalls: json['totalCalls'] ?? 0,
      totalInboundCalls: json['totalInboundCalls'] ?? 0,
      totalOutboundCalls: json['totalOutboundCalls'] ?? 0,
      totalMissedCalls: json['totalMissedCalls'] ?? 0,
      totalDuration: json['totalDuration'] ?? 0,
      callHistory: (json['callHistory'] as List<dynamic>?)
              ?.map((e) => LeadCallLog.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
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
      id: json['id'] ?? '',
      leadId: json['leadId'] ?? '',
      bound: json['bound'] ?? '',
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
      fromNumber: json['fromNumber'] ?? '',
      toNumber: json['toNumber'] ?? '',
      duration: json['duration'] ?? '',
      callDate: json['callDate'] ?? '',
      callStatus: json['callStatus'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
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
