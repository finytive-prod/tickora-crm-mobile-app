import 'package:equatable/equatable.dart';
import 'lead.dart';

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
  final String leadTask;
  final String followUpStatus;
  final String followUpDate;
  final String followUpTime;
  final String reminder;
  final LeadStatus? leadStatus;
  final String priority;
  final FollowUpAssignedUser? assignedUser;

  const FollowUp({
    this.id,
    required this.leadId,
    required this.leadName,
    required this.companyName,
    required this.leadTask,
    required this.followUpStatus,
    required this.followUpDate,
    required this.followUpTime,
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
        leadTask,
        followUpStatus,
        followUpDate,
        followUpTime,
        reminder,
        leadStatus,
        priority,
        assignedUser,
      ];
}

class FollowUpResponse extends Equatable {
  final FollowUpSummary summary;
  final List<FollowUp> followUps;

  const FollowUpResponse({
    required this.summary,
    required this.followUps,
  });

  @override
  List<Object?> get props => [summary, followUps];
}
