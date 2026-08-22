int _parseInt(dynamic val) {
  if (val == null) return 0;
  if (val is int) return val;
  if (val is double) return val.toInt();
  if (val is num) return val.toInt();
  if (val is String) {
    return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? 0;
  }
  return 0;
}

double _parseDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is double) return val;
  if (val is int) return val.toDouble();
  if (val is num) return val.toDouble();
  if (val is String) {
    return double.tryParse(val) ?? 0.0;
  }
  return 0.0;
}

class SummaryMetrics {
  final int totalLeads;
  final int newLeadsToday;
  final int qualifiedLeads;
  final int lostLeads;
  final int todaysFollowups;
  final int overdueFollowups;
  final double revenueThisMonth;
  final double conversionRate;

  SummaryMetrics({
    this.totalLeads = 0,
    this.newLeadsToday = 0,
    this.qualifiedLeads = 0,
    this.lostLeads = 0,
    this.todaysFollowups = 0,
    this.overdueFollowups = 0,
    this.revenueThisMonth = 0.0,
    this.conversionRate = 0.0,
  });

  factory SummaryMetrics.fromJson(Map<String, dynamic> json) {
    return SummaryMetrics(
      totalLeads: _parseInt(json['totalLeads'] ?? json['total']),
      newLeadsToday: _parseInt(json['newLeadsToday'] ?? json['today']),
      qualifiedLeads: _parseInt(json['qualifiedLeads'] ?? json['qualified']),
      lostLeads: _parseInt(json['lostLeads'] ?? json['lost']),
      todaysFollowups: _parseInt(json['todaysFollowups'] ?? json['todayFollowups']),
      overdueFollowups: _parseInt(json['overdueFollowups'] ?? json['overdue']),
      revenueThisMonth: _parseDouble(json['revenueThisMonth'] ?? json['revenue']),
      conversionRate: _parseDouble(json['conversionRate'] ?? json['conversion']),
    );
  }
}

class StatusDistributionItem {
  final String statusName;
  final int count;

  StatusDistributionItem({required this.statusName, required this.count});

  factory StatusDistributionItem.fromJson(Map<String, dynamic> json) {
    final name = json['statusName'] ?? json['name'] ?? json['status'] ?? json['label'] ?? json['stage'] ?? json['key'] ?? '';
    return StatusDistributionItem(
      statusName: name.toString(),
      count: _parseInt(json['count'] ?? json['value'] ?? json['total'] ?? json['amount']),
    );
  }
}

class SourceDistributionItem {
  final String sourceName;
  final int count;

  SourceDistributionItem({required this.sourceName, required this.count});

  factory SourceDistributionItem.fromJson(Map<String, dynamic> json) {
    final name = json['sourceName'] ?? json['name'] ?? json['source'] ?? json['label'] ?? json['key'] ?? '';
    return SourceDistributionItem(
      sourceName: name.toString(),
      count: _parseInt(json['count'] ?? json['value'] ?? json['total'] ?? json['amount']),
    );
  }
}

class SalesPipelineItem {
  final String stageName;
  final double value;

  SalesPipelineItem({required this.stageName, required this.value});

  factory SalesPipelineItem.fromJson(Map<String, dynamic> json) {
    final name = json['stageName'] ?? json['name'] ?? json['stage'] ?? json['status'] ?? json['label'] ?? '';
    return SalesPipelineItem(
      stageName: name.toString(),
      value: _parseDouble(json['value'] ?? json['count'] ?? json['total'] ?? json['amount']),
    );
  }
}

class ChartsData {
  final List<StatusDistributionItem> statusDistribution;
  final List<SourceDistributionItem> sourceDistribution;
  final List<SalesPipelineItem> salesPipeline;

  ChartsData({
    required this.statusDistribution,
    required this.sourceDistribution,
    required this.salesPipeline,
  });

  factory ChartsData.fromJson(Map<String, dynamic> json) {
    List<StatusDistributionItem> parseStatusList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => StatusDistributionItem.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))).toList();
      }
      return [];
    }

    List<SourceDistributionItem> parseSourceList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => SourceDistributionItem.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))).toList();
      }
      return [];
    }

    List<SalesPipelineItem> parsePipelineList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => SalesPipelineItem.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))).toList();
      }
      return [];
    }

    return ChartsData(
      statusDistribution: parseStatusList(json['statusDistribution'] ?? json['statuses'] ?? json['status']),
      sourceDistribution: parseSourceList(json['sourceDistribution'] ?? json['sources'] ?? json['source']),
      salesPipeline: parsePipelineList(json['salesPipeline'] ?? json['pipeline'] ?? json['stages']),
    );
  }
}

class TrendPoint {
  final String date;
  final int count;

  TrendPoint({required this.date, required this.count});

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    final d = json['date'] ?? json['day'] ?? json['month'] ?? json['year'] ?? json['period'] ?? json['time'] ?? json['label'] ?? '';
    return TrendPoint(
      date: d.toString(),
      count: _parseInt(json['count'] ?? json['value'] ?? json['total'] ?? json['leads']),
    );
  }
}

class LeadTrendData {
  final List<TrendPoint> leadsCreated;
  final List<TrendPoint> leadsWon;

  LeadTrendData({required this.leadsCreated, required this.leadsWon});

  factory LeadTrendData.fromJson(Map<String, dynamic> json) {
    List<TrendPoint> parseList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => TrendPoint.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))).toList();
      }
      return [];
    }

    return LeadTrendData(
      leadsCreated: parseList(json['leadsCreated'] ?? json['created'] ?? json['trend']),
      leadsWon: parseList(json['leadsWon'] ?? json['won'] ?? json['closed']),
    );
  }
}

class DashboardRecentLead {
  final String id;
  final String leadNumber;
  final String firstName;
  final String lastName;
  final String companyName;
  final String email;
  final String phoneNumber;
  final String statusName;
  final String statusColor;
  final String priority;
  final String assignedUser;
  final String createdAt;

  DashboardRecentLead({
    required this.id,
    required this.leadNumber,
    required this.firstName,
    required this.lastName,
    required this.companyName,
    required this.email,
    required this.phoneNumber,
    required this.statusName,
    required this.statusColor,
    required this.priority,
    required this.assignedUser,
    required this.createdAt,
  });

  String get fullName {
    final name = '$firstName $lastName'.trim();
    if (name.isNotEmpty) return name;
    if (companyName.isNotEmpty) return companyName;
    return 'Lead';
  }

  factory DashboardRecentLead.fromJson(Map<String, dynamic> json) {
    final statusObj = json['status'];
    String sName = 'NEW';
    String sColor = '#3B82F6';
    if (statusObj is Map) {
      sName = (statusObj['statusName'] ?? statusObj['name'] ?? 'NEW').toString();
      sColor = (statusObj['color'] ?? '#3B82F6').toString();
    } else if (statusObj != null && statusObj.toString().isNotEmpty) {
      sName = statusObj.toString();
    }

    final assignedObj = json['ownerUserName'] ??
        json['ownerName'] ??
        json['assignedUser'] ??
        json['assignedTo'] ??
        json['assignedToUser'] ??
        json['owner'] ??
        json['assignedUserName'];
    String assigned = 'Unassigned';
    if (assignedObj is Map) {
      assigned = (assignedObj['name'] ?? assignedObj['fullName'] ?? assignedObj['username'] ?? assignedObj['firstName'] ?? 'Unassigned').toString();
    } else if (assignedObj != null && assignedObj.toString().isNotEmpty) {
      assigned = assignedObj.toString();
    }

    String formattedDate = (json['createdAt'] ?? json['createdDate'] ?? json['date'] ?? '').toString();
    if (formattedDate.contains('T')) {
      final datePart = formattedDate.split('T')[0];
      final parts = datePart.split('-');
      if (parts.length == 3) {
        formattedDate = '${parts[2]}-${parts[1]}-${parts[0]}';
      }
    }

    return DashboardRecentLead(
      id: (json['id'] ?? '').toString(),
      leadNumber: (json['leadNumber'] ?? '').toString(),
      firstName: (json['firstName'] ?? json['name'] ?? json['leadName'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      companyName: (json['companyName'] ?? json['company'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phoneNumber: (json['phoneNumber'] ?? json['phone'] ?? json['mobile'] ?? '').toString(),
      statusName: sName,
      statusColor: sColor,
      priority: (json['priority'] ?? 'MEDIUM').toString(),
      assignedUser: assigned,
      createdAt: formattedDate,
    );
  }
}

class DashboardUpcomingFollowup {
  final String id;
  final String leadId;
  final String leadName;
  final String companyName;
  final String phoneNumber;
  final String leadTask;
  final String followUpStatus;
  final String followUpDate;
  final String followUpTime;
  final String followUpType;
  final String assignedUser;

  DashboardUpcomingFollowup({
    required this.id,
    required this.leadId,
    required this.leadName,
    required this.companyName,
    required this.phoneNumber,
    required this.leadTask,
    required this.followUpStatus,
    required this.followUpDate,
    required this.followUpTime,
    required this.followUpType,
    required this.assignedUser,
  });

  factory DashboardUpcomingFollowup.fromJson(Map<String, dynamic> json) {
    return DashboardUpcomingFollowup(
      id: (json['id'] ?? '').toString(),
      leadId: (json['leadId'] ?? '').toString(),
      leadName: (json['leadName'] ?? json['name'] ?? '').toString(),
      companyName: (json['companyName'] ?? '').toString(),
      phoneNumber: (json['phoneNumber'] ?? json['phone'] ?? '').toString(),
      leadTask: (json['leadTask'] ?? json['task'] ?? json['description'] ?? '').toString(),
      followUpStatus: (json['followUpStatus'] ?? json['status'] ?? 'PENDING').toString(),
      followUpDate: (json['followUpDate'] ?? json['date'] ?? '').toString(),
      followUpTime: (json['followUpTime'] ?? json['time'] ?? '').toString(),
      followUpType: (json['followUpType'] ?? json['type'] ?? 'TODAY').toString(),
      assignedUser: (json['assignedUser'] ?? json['assignedTo'] ?? 'Unassigned').toString(),
    );
  }
}

class DashboardRecentActivity {
  final String activityId;
  final String leadName;
  final String actionType;
  final String description;
  final String performedBy;
  final String timestamp;

  DashboardRecentActivity({
    required this.activityId,
    required this.leadName,
    required this.actionType,
    required this.description,
    required this.performedBy,
    required this.timestamp,
  });

  factory DashboardRecentActivity.fromJson(Map<String, dynamic> json) {
    final desc = (json['description'] ??
            json['detail'] ??
            json['details'] ??
            json['message'] ??
            json['title'] ??
            json['activityDescription'] ??
            json['remark'] ??
            json['notes'] ??
            '')
        .toString();

    final actType = (json['actionType'] ??
            json['action'] ??
            json['type'] ??
            json['activityType'] ??
            '')
        .toString();

    final perf = (json['actionBy'] ??
            json['actionByUser'] ??
            json['action_by'] ??
            json['performedBy'] ??
            json['user'] ??
            json['userName'] ??
            json['createdByName'] ??
            json['assignedTo'] ??
            '')
        .toString();

    final lead = (json['leadName'] ??
            json['lead'] ??
            json['name'] ??
            '')
        .toString();

    String ts = (json['timestamp'] ??
            json['createdAt'] ??
            json['date'] ??
            json['time'] ??
            json['createdDate'] ??
            '')
        .toString();
    if (ts.contains('T')) {
      final parts = ts.split('T');
      final d = parts[0].split('-');
      if (d.length == 3) {
        final timePart = parts[1].split('.')[0];
        ts = '${d[2]}-${d[1]}-${d[0]} ${timePart.length > 5 ? timePart.substring(0, 5) : timePart}';
      }
    }

    return DashboardRecentActivity(
      activityId: (json['activityId'] ?? json['id'] ?? '').toString(),
      leadName: lead,
      actionType: actType.isNotEmpty ? actType : (desc.isNotEmpty ? desc : 'UPDATE'),
      description: desc.isNotEmpty ? desc : (lead.isNotEmpty ? 'Updated lead $lead' : 'Updated lead details'),
      performedBy: perf.isNotEmpty ? perf : (lead.isNotEmpty ? lead : 'User'),
      timestamp: ts,
    );
  }
}

class RevenueTargetData {
  final double target;
  final double achieved;
  final double progressPercentage;

  RevenueTargetData({
    this.target = 0.0,
    this.achieved = 0.0,
    this.progressPercentage = 0.0,
  });

  factory RevenueTargetData.fromJson(Map<String, dynamic> json) {
    final tgt = _parseDouble(json['target'] ?? json['revenueTarget']);
    final ach = _parseDouble(json['achieved'] ?? json['revenueAchieved']);
    final pct = json['progressPercentage'] != null
        ? _parseDouble(json['progressPercentage'])
        : (tgt > 0 ? (ach / tgt * 100) : 0.0);

    return RevenueTargetData(
      target: tgt,
      achieved: ach,
      progressPercentage: pct,
    );
  }
}

class DashboardWidgetInfo {
  final String key;
  final String name;

  DashboardWidgetInfo({required this.key, required this.name});

  factory DashboardWidgetInfo.fromJson(Map<String, dynamic> json) {
    return DashboardWidgetInfo(
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}
