import 'package:flutter/material.dart';

class PipelineStatus {
  final String id;
  final String statusName;
  final int displayOrder;
  final Color color;
  final bool isDefault;
  final bool isClosed;
  final int level;

  PipelineStatus({
    required this.id,
    required this.statusName,
    required this.displayOrder,
    required this.color,
    required this.isDefault,
    required this.isClosed,
    this.level = 2,
  });

  factory PipelineStatus.fromJson(Map<String, dynamic> json) {
    final hexStr = json['color']?.toString() ?? '#3B82F6';
    Color parsedColor = const Color(0xFF3B82F6);
    try {
      final buffer = StringBuffer();
      if (hexStr.length == 6 || hexStr.length == 7) {
        buffer.write('ff');
        buffer.write(hexStr.replaceFirst('#', ''));
        parsedColor = Color(int.parse(buffer.toString(), radix: 16));
      }
    } catch (_) {}

    final statusNameStr = (json['statusName'] ?? json['name'] ?? 'Status').toString().trim();
    final nameLower = statusNameStr.toLowerCase();
    final isDef = json['isDefault'] == true || nameLower == 'fresh';
    final isCls = json['isClosed'] == true;

    int computedLevel = 2;
    final rawLevel = json['level'] ?? json['stage'] ?? json['stageLevel'];
    if (rawLevel != null) {
      final parsed = int.tryParse(rawLevel.toString());
      if (parsed != null && parsed >= 1 && parsed <= 3) {
        computedLevel = parsed;
      }
    } else if (isDef || nameLower == 'fresh' || nameLower == 'new' || nameLower == 'new lead') {
      computedLevel = 1;
    } else if (isCls ||
        nameLower.contains('won') ||
        nameLower.contains('lost') ||
        nameLower.contains('closed') ||
        nameLower.contains('rejected') ||
        nameLower.contains('dropped')) {
      computedLevel = 3;
    }

    int parsedDisplayOrder = 0;
    if (json['displayOrder'] != null) {
      parsedDisplayOrder = int.tryParse(json['displayOrder'].toString()) ?? 0;
    }

    return PipelineStatus(
      id: json['id']?.toString() ?? '',
      statusName: statusNameStr,
      displayOrder: parsedDisplayOrder,
      color: parsedColor,
      isDefault: json['isDefault'] == true || computedLevel == 1,
      isClosed: json['isClosed'] == true || computedLevel == 3,
      level: computedLevel,
    );
  }
}

class PipelineLeadItem {
  final String id;
  final String leadNumber;
  final String firstName;
  final String lastName;
  final String companyName;
  final String email;
  final String phone;
  final String priority;
  final String ownerUserId;
  final String ownerUsername;
  final String createdAt;

  PipelineLeadItem({
    required this.id,
    required this.leadNumber,
    required this.firstName,
    required this.lastName,
    required this.companyName,
    required this.email,
    required this.phone,
    required this.priority,
    required this.ownerUserId,
    required this.ownerUsername,
    required this.createdAt,
  });

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isNotEmpty ? name : (leadNumber.isNotEmpty ? leadNumber : 'Unnamed Lead');
  }

  static String _formatOwnerName(String? input) {
    if (input == null) return 'Unassigned';
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed == '-' || trimmed.toLowerCase() == 'unassigned') {
      return 'Unassigned';
    }
    if (trimmed.contains('@')) {
      final username = trimmed.split('@').first;
      final parts = username.split(RegExp(r'[._\-]'));
      final formatted = parts
          .where((p) => p.trim().isNotEmpty)
          .map((p) => p[0].toUpperCase() + (p.length > 1 ? p.substring(1).toLowerCase() : ''))
          .join(' ');
      if (formatted.isNotEmpty) return formatted;
    }
    return trimmed;
  }

  factory PipelineLeadItem.fromJson(Map<String, dynamic> json) {
    final rawOwner = json['ownerUsername']?.toString() ??
        json['ownerUserName']?.toString() ??
        json['ownerName']?.toString() ??
        json['assignedToName']?.toString() ??
        json['assignedTo']?.toString() ??
        'Unassigned';

    return PipelineLeadItem(
      id: json['id']?.toString() ?? '',
      leadNumber: json['leadNumber']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'MEDIUM',
      ownerUserId: json['ownerUserId']?.toString() ?? '',
      ownerUsername: _formatOwnerName(rawOwner),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class PipelineColumnData {
  final PipelineStatus status;
  final List<PipelineLeadItem> leads;
  final int totalElements;

  PipelineColumnData({
    required this.status,
    required this.leads,
    required this.totalElements,
  });

  factory PipelineColumnData.fromJson(Map<String, dynamic> json) {
    final statusObj = PipelineStatus.fromJson(
      json['status'] is Map<String, dynamic> ? json['status'] : Map<String, dynamic>.from(json['status'] ?? {}),
    );

    final leadsMap = json['leads'] is Map<String, dynamic> ? json['leads'] : Map<String, dynamic>.from(json['leads'] ?? {});
    final List<dynamic> content = leadsMap['content'] is List ? leadsMap['content'] : [];
    final List<PipelineLeadItem> leadItems = content
        .map((e) => PipelineLeadItem.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map)))
        .toList();

    final total = (leadsMap['totalElements'] as num?)?.toInt() ?? leadItems.length;

    return PipelineColumnData(
      status: statusObj,
      leads: leadItems,
      totalElements: total,
    );
  }

  PipelineColumnData copyWith({
    PipelineStatus? status,
    List<PipelineLeadItem>? leads,
    int? totalElements,
  }) {
    return PipelineColumnData(
      status: status ?? this.status,
      leads: leads ?? this.leads,
      totalElements: totalElements ?? this.totalElements,
    );
  }
}
