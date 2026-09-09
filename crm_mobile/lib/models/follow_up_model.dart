import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/models/lead_model.dart';

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
    super.phoneNumber,
    required super.leadTask,
    required super.followUpStatus,
    required super.followUpDate,
    required super.followUpTime,
    super.followUpType,
    required super.reminder,
    super.leadStatus,
    required super.priority,
    super.assignedUser,
  });

  factory FollowUpModel.fromJson(Map<String, dynamic> json) {
    return FollowUpModel(
      id: json['id'],
      leadId: json['leadId'] ?? json['id'] ?? '',
      leadName: (json['leadName'] != null && json['leadName'].toString().isNotEmpty)
          ? json['leadName']
          : (json['name'] ?? ''),
      companyName: json['companyName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? json['phone'],
      leadTask: (json['leadTask'] != null && json['leadTask'].toString().isNotEmpty)
          ? json['leadTask']
          : (json['task'] ?? 'Follow up'),
      followUpStatus: (json['followUpStatus'] != null && json['followUpStatus'].toString().isNotEmpty)
          ? json['followUpStatus']
          : (json['status'] ?? 'ADDED_TO_FOLLOW_UP'),
      followUpDate: json['followUpDate'] ?? json['date'] ?? '',
      followUpTime: json['followUpTime'] ?? json['time'] ?? '',
      followUpType: json['followUpType'] ?? json['type'],
      reminder: json['reminder']?.toString() ?? '',
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
    super.totalElements,
    super.totalPages,
    super.size,
    super.number,
    super.numberOfElements,
    super.first,
    super.last,
    super.empty,
  });

  factory FollowUpResponseModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> list = json['content'] ?? json['followUps'] ?? [];
    final followUps = list.map((e) => FollowUpModel.fromJson(e)).toList();

    FollowUpSummary summary;
    if (json['summary'] != null && json['summary'] is Map && (json['summary'] as Map).isNotEmpty) {
      summary = FollowUpSummaryModel.fromJson(json['summary']);
    } else {
      int todayCount = 0;
      int upcomingCount = 0;
      int missedCount = 0;
      int completedCount = 0;

      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      for (var f in followUps) {
        final statusUpper = f.followUpStatus.toUpperCase();
        if (statusUpper.contains('COMPLETED')) {
          completedCount++;
        } else if (statusUpper.contains('MISSED')) {
          missedCount++;
        } else if (f.followUpDate.isNotEmpty) {
          if (f.followUpDate.startsWith(todayStr)) {
            todayCount++;
          } else if (f.followUpDate.compareTo(todayStr) > 0) {
            upcomingCount++;
          } else {
            missedCount++;
          }
        } else {
          todayCount++;
        }
      }

      summary = FollowUpSummaryModel(
        today: todayCount,
        upcoming: upcomingCount,
        missed: missedCount,
        completed: completedCount,
      );
    }

    final totalElements = (json['totalElements'] as num?)?.toInt() ?? followUps.length;
    final totalPages = (json['totalPages'] as num?)?.toInt() ?? (totalElements > 0 ? 1 : 0);
    final size = (json['size'] as num?)?.toInt() ?? 10;
    final number = (json['number'] as num?)?.toInt() ?? 0;
    final numberOfElements = (json['numberOfElements'] as num?)?.toInt() ?? followUps.length;
    final first = json['first'] as bool? ?? (number == 0);
    final last = json['last'] as bool? ?? (number >= totalPages - 1);
    final empty = json['empty'] as bool? ?? followUps.isEmpty;

    return FollowUpResponseModel(
      summary: summary,
      followUps: followUps,
      totalElements: totalElements,
      totalPages: totalPages,
      size: size,
      number: number,
      numberOfElements: numberOfElements,
      first: first,
      last: last,
      empty: empty,
    );
  }

  @override
  FollowUpResponseModel copyWith({
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
    return FollowUpResponseModel(
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
}
