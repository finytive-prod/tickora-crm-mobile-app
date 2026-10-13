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

  bool get isRealFollowUp {
    if (id == null || id!.trim().isEmpty) return false;
    final status = followUpStatus.trim().toUpperCase();
    final task = leadTask.trim().toUpperCase();
    if (status == 'NO FOLLOW UP' || status == 'NO_FOLLOW_UP' || status == 'NONE') return false;
    if (task == 'NO FOLLOW UP' || task == 'NO_FOLLOW_UP' || task == 'NONE') return false;
    if (followUpDate.trim().isEmpty && followUpTime.trim().isEmpty) return false;
    return true;
  }

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
    String parsedLeadName = '';
    if (json['leadName'] != null && json['leadName'].toString().trim().isNotEmpty) {
      parsedLeadName = json['leadName'].toString().trim();
    } else if (json['name'] != null && json['name'].toString().trim().isNotEmpty) {
      parsedLeadName = json['name'].toString().trim();
    } else if (json['title'] != null && json['title'].toString().trim().isNotEmpty) {
      parsedLeadName = json['title'].toString().trim();
    } else {
      final fn = json['firstName'] ?? (json['lead'] is Map ? json['lead']['firstName'] : null);
      final ln = json['lastName'] ?? (json['lead'] is Map ? json['lead']['lastName'] : null);
      final combined = '${fn ?? ''} ${ln ?? ''}'.trim();
      if (combined.isNotEmpty) {
        parsedLeadName = combined;
      }
    }

    String parsedCompany = json['companyName']?.toString().trim() ?? '';
    if (parsedCompany.isEmpty && json['lead'] is Map) {
      parsedCompany = json['lead']['companyName']?.toString().trim() ?? '';
    }

    String? parsedPhone = json['phoneNumber']?.toString().trim() ?? json['phone']?.toString().trim();
    if ((parsedPhone == null || parsedPhone.isEmpty) && json['lead'] is Map) {
      parsedPhone = json['lead']['phone']?.toString().trim();
    }

    return FollowUpModel(
      id: json['id']?.toString(),
      leadId: json['leadId']?.toString() ?? json['id']?.toString() ?? '',
      leadName: parsedLeadName,
      companyName: parsedCompany,
      phoneNumber: parsedPhone,
      leadTask: (json['leadTask'] != null && json['leadTask'].toString().isNotEmpty)
          ? json['leadTask'].toString()
          : (json['task']?.toString() ?? 'Follow up'),
      followUpStatus: (json['followUpStatus'] != null && json['followUpStatus'].toString().isNotEmpty)
          ? json['followUpStatus'].toString()
          : (json['status']?.toString() ?? 'ADDED_TO_FOLLOW_UP'),
      followUpDate: json['followUpDate']?.toString() ?? json['date']?.toString() ?? '',
      followUpTime: json['followUpTime']?.toString() ?? json['time']?.toString() ?? '',
      followUpType: json['followUpType']?.toString() ?? json['type']?.toString(),
      reminder: json['reminder']?.toString() ?? '',
      leadStatus: json['leadStatus'] != null ? LeadStatusModel.fromJson(json['leadStatus']) : null,
      priority: json['priority']?.toString() ?? 'MEDIUM',
      assignedUser: json['assignedUser'] != null ? FollowUpAssignedUserModel.fromJson(json['assignedUser']) : null,
    );
  }
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
