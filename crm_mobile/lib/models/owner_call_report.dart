import 'package:equatable/equatable.dart';

class OwnerCallReport extends Equatable {
  final String ownerId;
  final String ownerName;
  final int totalCallsCount;
  final String totalDuration;
  final int incomingCalls;
  final String incomingCallsDuration;
  final int outgoingCalls;
  final String outgoingCallsDuration;

  const OwnerCallReport({
    required this.ownerId,
    required this.ownerName,
    required this.totalCallsCount,
    required this.totalDuration,
    required this.incomingCalls,
    required this.incomingCallsDuration,
    required this.outgoingCalls,
    required this.outgoingCallsDuration,
  });

  factory OwnerCallReport.fromJson(Map<String, dynamic> json) {
    return OwnerCallReport(
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? 'Unknown',
      totalCallsCount: (json['totalCallsCount'] as num?)?.toInt() ?? 0,
      totalDuration: json['totalDuration']?.toString() ?? '00:00:00',
      incomingCalls: (json['incomingCalls'] as num?)?.toInt() ?? 0,
      incomingCallsDuration: json['incomingCallsDuration']?.toString() ?? '00:00:00',
      outgoingCalls: (json['outgoingCalls'] as num?)?.toInt() ?? 0,
      outgoingCallsDuration: json['outgoingCallsDuration']?.toString() ?? '00:00:00',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'totalCallsCount': totalCallsCount,
      'totalDuration': totalDuration,
      'incomingCalls': incomingCalls,
      'incomingCallsDuration': incomingCallsDuration,
      'outgoingCalls': outgoingCalls,
      'outgoingCallsDuration': outgoingCallsDuration,
    };
  }

  @override
  List<Object?> get props => [
        ownerId,
        ownerName,
        totalCallsCount,
        totalDuration,
        incomingCalls,
        incomingCallsDuration,
        outgoingCalls,
        outgoingCallsDuration,
      ];
}
