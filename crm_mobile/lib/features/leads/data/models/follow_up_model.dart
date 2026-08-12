import '../../domain/entities/follow_up.dart';
import 'lead_model.dart';

class FollowUpSummaryModel extends FollowUpSummary {
  const FollowUpSummaryModel({
    required super.today,
    required super.upcoming,
    required super.missed,
    required super.completed,
  });

  factory FollowUpSummaryModel.fromJson(Map<String, dynamic> json) {
    return FollowUpSummaryModel(
      today: json['today'] ?? 0,
      upcoming: json['upcoming'] ?? 0,
      missed: json['missed'] ?? 0,
      completed: json['completed'] ?? 0,
    );
  }
}

class FollowUpAssignedUserModel extends FollowUpAssignedUser {
  const FollowUpAssignedUserModel({
    required super.id,
    required super.name,
  });

  factory FollowUpAssignedUserModel.fromJson(Map<String, dynamic> json) {
    return FollowUpAssignedUserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

class FollowUpModel extends FollowUp {
  const FollowUpModel({
    super.id,
    required super.leadId,
    required super.leadName,
    required super.companyName,
    required super.leadTask,
    required super.followUpStatus,
    required super.followUpDate,
    required super.followUpTime,
    required super.reminder,
    super.leadStatus,
    required super.priority,
    super.assignedUser,
  });

  factory FollowUpModel.fromJson(Map<String, dynamic> json) {
    return FollowUpModel(
      id: json['id'],
      leadId: json['leadId'] ?? '',
      leadName: json['leadName'] ?? '',
      companyName: json['companyName'] ?? '',
      leadTask: json['leadTask'] ?? '',
      followUpStatus: json['followUpStatus'] ?? '',
      followUpDate: json['followUpDate'] ?? '',
      followUpTime: json['followUpTime'] ?? '',
      reminder: json['reminder'] ?? '',
      leadStatus: json['leadStatus'] != null ? LeadStatusModel.fromJson(json['leadStatus']) : null,
      priority: json['priority'] ?? 'MEDIUM',
      assignedUser: json['assignedUser'] != null ? FollowUpAssignedUserModel.fromJson(json['assignedUser']) : null,
    );
  }
}

class FollowUpResponseModel extends FollowUpResponse {
  const FollowUpResponseModel({
    required super.summary,
    required super.followUps,
  });

  factory FollowUpResponseModel.fromJson(Map<String, dynamic> json) {
    final summary = FollowUpSummaryModel.fromJson(json['summary'] ?? {});
    final List<dynamic> list = json['followUps'] ?? [];
    final followUps = list.map((e) => FollowUpModel.fromJson(e)).toList();

    return FollowUpResponseModel(
      summary: summary,
      followUps: followUps,
    );
  }
}
