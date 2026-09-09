import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/lead.dart';

class FollowUpSummary extends Equatable {
  final int today;
  final int upcoming;
  final int missed;
  final int completed;

  const FollowUpSummary({
    required this.today,
    required this.upcoming,
    required this.missed,
    required this.completed,
  });

  @override
  List<Object?> get props => [today, upcoming, missed, completed];
}

class FollowUpAssignedUser extends Equatable {
  final String id;
  final String name;

  const FollowUpAssignedUser({
    required this.id,
    required this.name,
  });

  @override
  List<Object?> get props => [id, name];
}

class FollowUp extends Equatable {
  final String? id;
  final String leadId;
  final String leadName;
  final String companyName;
  final String? phoneNumber;
  final String leadTask;
  final String followUpStatus;
  final String followUpDate;
  final String followUpTime;
  final String? followUpType;
  final String reminder;
  final LeadStatus? leadStatus;
  final String priority;
  final FollowUpAssignedUser? assignedUser;

  const FollowUp({
    this.id,
    required this.leadId,
    required this.leadName,
    required this.companyName,
    this.phoneNumber,
    required this.leadTask,
    required this.followUpStatus,
    required this.followUpDate,
    required this.followUpTime,
    this.followUpType,
    required this.reminder,
    this.leadStatus,
    required this.priority,
    this.assignedUser,
  });

  @override
  List<Object?> get props => [
        id,
        leadId,
        leadName,
        companyName,
        phoneNumber,
        leadTask,
        followUpStatus,
        followUpDate,
        followUpTime,
        followUpType,
        reminder,
        leadStatus,
        priority,
        assignedUser,
      ];
}

class FollowUpResponse extends Equatable {
  final FollowUpSummary summary;
  final List<FollowUp> followUps;
  final int totalElements;
  final int totalPages;
  final int size;
  final int number;
  final int numberOfElements;
  final bool first;
  final bool last;
  final bool empty;

  const FollowUpResponse({
    required this.summary,
    required this.followUps,
    this.totalElements = 0,
    this.totalPages = 0,
    this.size = 10,
    this.number = 0,
    this.numberOfElements = 0,
    this.first = true,
    this.last = true,
    this.empty = false,
  });

  FollowUpResponse copyWith({
    FollowUpSummary? summary,
    List<FollowUp>? followUps,
    int? totalElements,
    int? totalPages,
    int? size,
    int? number,
    int? numberOfElements,
    bool? first,
    bool? last,
    bool? empty,
  }) {
    return FollowUpResponse(
      summary: summary ?? this.summary,
      followUps: followUps ?? this.followUps,
      totalElements: totalElements ?? this.totalElements,
      totalPages: totalPages ?? this.totalPages,
      size: size ?? this.size,
      number: number ?? this.number,
      numberOfElements: numberOfElements ?? this.numberOfElements,
      first: first ?? this.first,
      last: last ?? this.last,
      empty: empty ?? this.empty,
    );
  }

  @override
  List<Object?> get props => [
        summary,
        followUps,
        totalElements,
        totalPages,
        size,
        number,
        numberOfElements,
        first,
        last,
        empty,
      ];
}
