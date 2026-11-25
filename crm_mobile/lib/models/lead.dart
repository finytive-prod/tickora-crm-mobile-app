import 'package:equatable/equatable.dart';

class LeadSource extends Equatable {
  final String id;
  final String name;
  final String category;
  final String description;
  final bool active;

  const LeadSource({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.active = true,
  });

  @override
  List<Object?> get props => [id, name, category, description, active];
}

class LeadSourceModel extends LeadSource {
  const LeadSourceModel({
    required super.id,
    required super.name,
    required super.category,
    required super.description,
    super.active,
  });

  factory LeadSourceModel.fromJson(dynamic json) {
    if (json is String) {
      return LeadSourceModel(
        id: json,
        name: json,
        category: '',
        description: '',
        active: true,
      );
    }
    if (json is Map<String, dynamic>) {
      return LeadSourceModel(
        id: json['id'] ?? '',
        name: json['name'] ?? json['sourceName'] ?? '',
        category: json['category'] ?? '',
        description: json['description'] ?? '',
        active: json['active'] ?? true,
      );
    }
    return const LeadSourceModel(
      id: '',
      name: '',
      category: '',
      description: '',
      active: true,
    );
  }
}

class LeadStatus extends Equatable {
  final String id;
  final String statusName;
  final String color;
  final bool isDefault;
  final bool isClosed;
  final int displayOrder;
  final int level;
  final bool isActive;

  const LeadStatus({
    required this.id,
    required this.statusName,
    required this.color,
    required this.isDefault,
    required this.isClosed,
    required this.displayOrder,
    this.level = 2,
    this.isActive = true,
  });

  @override
  List<Object?> get props => [id, statusName, color, isDefault, isClosed, displayOrder, level, isActive];
}

class LeadStatusModel extends LeadStatus {
  const LeadStatusModel({
    required super.id,
    required super.statusName,
    required super.color,
    required super.isDefault,
    required super.isClosed,
    required super.displayOrder,
    super.level,
    super.isActive,
  });

  factory LeadStatusModel.fromJson(dynamic json) {
    if (json is String) {
      return LeadStatusModel(
        id: json,
        statusName: json,
        color: '#6B7280',
        isDefault: false,
        isClosed: false,
        displayOrder: 0,
        level: 2,
        isActive: true,
      );
    }
    if (json is Map<String, dynamic>) {
      final statusNameStr = (json['statusName'] ?? json['name'] ?? '').toString().trim();
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

      return LeadStatusModel(
        id: json['id']?.toString() ?? '',
        statusName: statusNameStr,
        color: (json['color'] ?? json['colorCode'] ?? json['color_code'] ?? '#6B7280').toString(),
        isDefault: json['isDefault'] == true || computedLevel == 1,
        isClosed: json['isClosed'] == true || computedLevel == 3,
        displayOrder: parsedDisplayOrder,
        level: computedLevel,
        isActive: json['isActive'] ?? true,
      );
    }
    return const LeadStatusModel(
      id: '',
      statusName: '',
      color: '#6B7280',
      isDefault: false,
      isClosed: false,
      displayOrder: 0,
      level: 2,
      isActive: true,
    );
  }
}

class Lead extends Equatable {
  final String id;
  final String leadNumber;
  final String firstName;
  final String lastName;
  final String companyName;
  final String email;
  final String phone;
  final String? alternatePhone;
  final LeadSource? source;
  final LeadStatus? status;
  final String? priority;
  final String? ownerUserId;
  final String? ownerUserName;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final String? callStatus;

  const Lead({
    required this.id,
    required this.leadNumber,
    required this.firstName,
    required this.lastName,
    required this.companyName,
    required this.email,
    required this.phone,
    this.alternatePhone,
    this.source,
    this.status,
    this.priority,
    this.ownerUserId,
    this.ownerUserName,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.callStatus,
  });

  @override
  List<Object?> get props => [
        id,
        leadNumber,
        firstName,
        lastName,
        companyName,
        email,
        phone,
        alternatePhone,
        source,
        status,
        priority,
        ownerUserId,
        ownerUserName,
        createdBy,
        createdByName,
        createdAt,
        callStatus,
      ];
}

class LeadModel extends Lead {
  const LeadModel({
    required super.id,
    required super.leadNumber,
    required super.firstName,
    required super.lastName,
    required super.companyName,
    required super.email,
    required super.phone,
    super.alternatePhone,
    super.source,
    super.status,
    super.priority,
    super.ownerUserId,
    super.ownerUserName,
    super.createdBy,
    super.createdByName,
    super.createdAt,
    super.callStatus,
  });

  static String? _extractAlternatePhoneFromJson(
    Map<String, dynamic> json,
    String primaryPhone,
  ) {
    const directKeys = [
      'alternatePhone',
      'altPhone',
      'alternativePhone',
      'alternate_phone',
      'alt_phone',
      'secondaryPhone',
      'secondaryMobile',
    ];
    for (final key in directKeys) {
      final raw = json[key]?.toString().trim() ?? '';
      if (raw.isNotEmpty && raw != '-' && raw.toLowerCase() != 'null') {
        return raw;
      }
    }

    final rawCustomFields = json['customFields'];
    if (rawCustomFields is List) {
      final primaryDigits = primaryPhone.replaceAll(RegExp(r'\D'), '');
      final primaryKey = primaryDigits.length >= 10
          ? primaryDigits.substring(primaryDigits.length - 10)
          : primaryDigits;

      String? fallbackPhoneCustomField;
      for (final item in rawCustomFields) {
        if (item is! Map) continue;
        final value = (item['value'] ?? item['fieldValue'])?.toString().trim() ?? '';
        if (value.isEmpty || value == '-') continue;
        final valDigits = value.replaceAll(RegExp(r'\D'), '');
        if (valDigits.length < 3) continue;
        final valKey = valDigits.length >= 10
            ? valDigits.substring(valDigits.length - 10)
            : valDigits;
        if (primaryKey.isNotEmpty && valKey == primaryKey) continue;

        final type = (item['fieldType'] ?? '').toString().toLowerCase();
        final name = (item['fieldName'] ?? '').toString().toLowerCase();
        final label = (item['label'] ?? item['fieldLabel'] ?? '').toString().toLowerCase();
        final isAltKey =
            name.contains('alternate') ||
            name.contains('altphone') ||
            name.contains('alt_phone') ||
            name.contains('secondary') ||
            label.contains('alternate') ||
            label.contains('secondary');
        if (isAltKey) return value;

        final isPhoneType =
            type == 'phone' ||
            type == 'mobile' ||
            type == 'tel' ||
            name.contains('phone') ||
            name.contains('mobile') ||
            label.contains('phone') ||
            label.contains('mobile');
        if (isPhoneType && fallbackPhoneCustomField == null) {
          fallbackPhoneCustomField = value;
        }
      }
      if (fallbackPhoneCustomField != null) {
        return fallbackPhoneCustomField;
      }
    }
    return null;
  }

  factory LeadModel.fromJson(Map<String, dynamic> json) {
    String fName = json['firstName'] ?? '';
    String lName = json['lastName'] ?? '';
    if (fName.isEmpty && lName.isEmpty && json['name'] != null && json['name'].toString().isNotEmpty) {
      final parts = json['name'].toString().trim().split(' ');
      fName = parts.isNotEmpty ? parts.first : '';
      lName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    final phone = (json['phone'] != null && json['phone'].toString().isNotEmpty)
        ? json['phone'].toString()
        : (json['phoneNumber']?.toString() ?? '');
    final alternatePhone = _extractAlternatePhoneFromJson(json, phone);

    String? ownerUserId;
    void trySetOwnerUserId(dynamic val) {
      if (ownerUserId != null && ownerUserId!.isNotEmpty) return;
      if (val == null) return;
      if (val is String && val.trim().isNotEmpty) {
        ownerUserId = val.trim();
      } else if (val is Map && (val['id'] != null || val['userId'] != null)) {
        final idVal = (val['id'] ?? val['userId'])?.toString();
        if (idVal != null && idVal.trim().isNotEmpty) {
          ownerUserId = idVal.trim();
        }
      }
    }

    trySetOwnerUserId(json['ownerUserId']);
    trySetOwnerUserId(json['owner_user_id']);
    trySetOwnerUserId(json['ownerId']);
    trySetOwnerUserId(json['owner_id']);
    trySetOwnerUserId(json['assignedToId']);
    trySetOwnerUserId(json['assigned_to_id']);
    trySetOwnerUserId(json['assignedUserId']);
    trySetOwnerUserId(json['assigned_user_id']);
    trySetOwnerUserId(json['staffId']);
    trySetOwnerUserId(json['staff_id']);
    trySetOwnerUserId(json['userId']);
    trySetOwnerUserId(json['user_id']);
    trySetOwnerUserId(json['assignedTo']);
    trySetOwnerUserId(json['assigned_to']);
    trySetOwnerUserId(json['ownerUser']);
    trySetOwnerUserId(json['owner_user']);
    trySetOwnerUserId(json['owner']);

    String? ownerUserName;
    void trySetOwnerUserName(dynamic val) {
      if (ownerUserName != null && ownerUserName!.isNotEmpty) return;
      if (val == null) return;
      if (val is String) {
        final str = val.trim();
        if (str.isNotEmpty) {
          final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(str);
          if (!isUuid) {
            ownerUserName = str;
          }
        }
      } else if (val is Map) {
        final nameVal = (val['name'] ?? val['fullName'] ?? val['firstName'] ?? val['userName'] ?? val['username'] ?? val['email'])?.toString();
        if (nameVal != null && nameVal.trim().isNotEmpty) {
          ownerUserName = nameVal.trim();
        }
      }
    }

    trySetOwnerUserName(json['ownerUserName']);
    trySetOwnerUserName(json['owner_user_name']);
    trySetOwnerUserName(json['ownerName']);
    trySetOwnerUserName(json['owner_name']);
    trySetOwnerUserName(json['assignedToName']);
    trySetOwnerUserName(json['assigned_to_name']);
    trySetOwnerUserName(json['assignedToInfo']);
    trySetOwnerUserName(json['assigneeName']);
    trySetOwnerUserName(json['assignee_name']);
    trySetOwnerUserName(json['assignee']);
    trySetOwnerUserName(json['staffName']);
    trySetOwnerUserName(json['staff_name']);
    trySetOwnerUserName(json['staff']);
    trySetOwnerUserName(json['assignedTo']);
    trySetOwnerUserName(json['assigned_to']);
    trySetOwnerUserName(json['ownerUser']);
    trySetOwnerUserName(json['owner_user']);
    trySetOwnerUserName(json['owner']);
    trySetOwnerUserName(json['ownerEmail']);
    trySetOwnerUserName(json['owner_email']);
    trySetOwnerUserName(json['assignedToEmail']);
    trySetOwnerUserName(json['assigned_to_email']);
    trySetOwnerUserName(json['ownerDisplayName']);
    trySetOwnerUserName(json['owner_display_name']);
    trySetOwnerUserName(json['leadOwner']);
    trySetOwnerUserName(json['lead_owner']);
    trySetOwnerUserName(json['assignedUser']);
    trySetOwnerUserName(json['assigned_user']);
    trySetOwnerUserName(json['allocatedTo']);
    trySetOwnerUserName(json['allocated_to']);

    if (ownerUserName == null || ownerUserName!.isEmpty) {
      if (json['assignedTo'] is String && json['assignedTo'].toString().trim().isNotEmpty) {
        ownerUserName = json['assignedTo'].toString().trim();
      } else if (json['assigned_to'] is String && json['assigned_to'].toString().trim().isNotEmpty) {
        ownerUserName = json['assigned_to'].toString().trim();
      } else if (json['owner'] is String && json['owner'].toString().trim().isNotEmpty) {
        ownerUserName = json['owner'].toString().trim();
      }
    }

    String? createdBy = (json['createdBy'] ??
            json['created_by'] ??
            json['creatorId'] ??
            json['creator_id'])
        ?.toString();
    String? createdByName;
    void trySetCreatedByName(dynamic val) {
      if (createdByName != null && createdByName!.isNotEmpty) return;
      if (val == null) return;
      if (val is String) {
        final str = val.trim();
        if (str.isNotEmpty) {
          final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(str);
          if (!isUuid) {
            createdByName = str;
          }
        }
      } else if (val is Map) {
        final nameVal = (val['name'] ?? val['fullName'] ?? val['firstName'] ?? val['userName'] ?? val['username'] ?? val['email'])?.toString();
        if (nameVal != null && nameVal.trim().isNotEmpty) {
          createdByName = nameVal.trim();
        }
      }
    }

    trySetCreatedByName(json['createdByName']);
    trySetCreatedByName(json['created_by_name']);
    trySetCreatedByName(json['creatorName']);
    trySetCreatedByName(json['creator_name']);
    trySetCreatedByName(json['createdByUser']);
    trySetCreatedByName(json['created_by_user']);
    trySetCreatedByName(json['creator']);
    trySetCreatedByName(json['createdBy']);
    trySetCreatedByName(json['created_by']);
    trySetCreatedByName(json['creatorEmail']);
    trySetCreatedByName(json['creator_email']);
    trySetCreatedByName(json['creatorDisplayName']);
    trySetCreatedByName(json['creator_display_name']);
    trySetCreatedByName(json['leadCreator']);
    trySetCreatedByName(json['lead_creator']);
    trySetCreatedByName(json['author']);
    trySetCreatedByName(json['addedBy']);
    trySetCreatedByName(json['added_by']);

    DateTime? parseDateTime(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is num) {
        final val = raw.toInt();
        if (val > 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val);
        } else if (val > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val * 1000);
        }
      }
      final str = raw.toString().trim();
      if (str.isEmpty || str == 'null' || str == '-') return null;
      final numParsed = int.tryParse(str);
      if (numParsed != null) {
        if (numParsed > 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(numParsed);
        } else if (numParsed > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(numParsed * 1000);
        }
      }
      return DateTime.tryParse(str);
    }

    final parsedCreatedAt = parseDateTime(
      json['createdAt'] ??
          json['created_at'] ??
          json['createdDate'] ??
          json['created_date'] ??
          json['createDate'] ??
          json['create_date'] ??
          json['createdTime'] ??
          json['created_time'] ??
          json['created_on'] ??
          json['createdOn'] ??
          json['addedDate'] ??
          json['added_date'] ??
          json['addedOn'] ??
          json['added_on'] ??
          json['creationDate'] ??
          json['creation_date'] ??
          json['creationTime'] ??
          json['creation_time'] ??
          json['leadDate'] ??
          json['lead_date'] ??
          json['timestamp'] ??
          json['date'],
    );

    final callStatus = (json['callStatus'] ??
            json['call_status'] ??
            json['lastCallStatus'] ??
            json['last_call_status'] ??
            json['latestCallStatus'] ??
            json['latest_call_status'] ??
            json['callState'] ??
            json['call_state'] ??
            json['callResult'] ??
            json['call_result'] ??
            json['lastCallResult'] ??
            json['last_call_result'] ??
            json['disposition'] ??
            json['statusCall'])
        ?.toString();

    LeadStatus? parsedStatus;
    if (json['status'] != null) {
      parsedStatus = LeadStatusModel.fromJson(json['status']);
    } else {
      final statusNameCandidate = (json['statusName'] ??
              json['status_name'] ??
              json['leadStatus'] ??
              json['leadStatusName'] ??
              json['lead_status'] ??
              json['lead_status_name'] ??
              '')
          .toString()
          .trim();
      final statusIdCandidate = (json['statusId'] ??
              json['status_id'] ??
              json['leadStatusId'] ??
              json['lead_status_id'] ??
              '')
          .toString()
          .trim();
      final statusColorCandidate = (json['statusColor'] ??
              json['status_color'] ??
              json['color'] ??
              '#6B7280')
          .toString()
          .trim();

      if (statusNameCandidate.isNotEmpty || statusIdCandidate.isNotEmpty) {
        parsedStatus = LeadStatus(
          id: statusIdCandidate.isNotEmpty ? statusIdCandidate : statusNameCandidate,
          statusName: statusNameCandidate.isNotEmpty ? statusNameCandidate : statusIdCandidate,
          color: statusColorCandidate.isNotEmpty ? statusColorCandidate : '#6B7280',
          isDefault: false,
          isClosed: false,
          displayOrder: 0,
        );
      }
    }

    return LeadModel(
      id: json['id'] ?? '',
      leadNumber: json['leadNumber'] ?? '',
      firstName: fName,
      lastName: lName,
      companyName: json['companyName'] ?? json['company'] ?? '',
      email: json['email'] ?? '',
      phone: phone,
      alternatePhone: alternatePhone,
      source: json['source'] != null ? LeadSourceModel.fromJson(json['source']) : null,
      status: parsedStatus,
      priority: (json['priority'] ?? json['leadPriority'] ?? json['lead_priority'])?.toString(),
      ownerUserId: ownerUserId,
      ownerUserName: ownerUserName,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: parsedCreatedAt,
      callStatus: callStatus,
    );
  }
}
