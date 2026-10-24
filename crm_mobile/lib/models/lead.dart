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
      final isDef = json['isDefault'] == true || (json['statusName'] ?? json['name'] ?? '').toString().toLowerCase() == 'fresh';
      final isCls = json['isClosed'] == true;
      int computedLevel = 2;
      if (json['level'] != null) {
        computedLevel = (json['level'] as num).toInt();
      } else if (isDef) {
        computedLevel = 1;
      } else if (isCls) {
        computedLevel = 3;
      }

      return LeadStatusModel(
        id: json['id']?.toString() ?? '',
        statusName: json['statusName']?.toString() ?? json['name']?.toString() ?? '',
        color: json['color']?.toString() ?? '#6B7280',
        isDefault: json['isDefault'] == true,
        isClosed: json['isClosed'] == true,
        displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
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

  factory LeadModel.fromJson(Map<String, dynamic> json) {
    String fName = json['firstName'] ?? '';
    String lName = json['lastName'] ?? '';
    if (fName.isEmpty && lName.isEmpty && json['name'] != null && json['name'].toString().isNotEmpty) {
      final parts = json['name'].toString().trim().split(' ');
      fName = parts.isNotEmpty ? parts.first : '';
      lName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    final phone = (json['phone'] != null && json['phone'].toString().isNotEmpty)
        ? json['phone']
        : (json['phoneNumber'] ?? '');

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
    trySetOwnerUserId(json['ownerId']);
    trySetOwnerUserId(json['assignedToId']);
    trySetOwnerUserId(json['assignedUserId']);
    trySetOwnerUserId(json['staffId']);
    trySetOwnerUserId(json['userId']);
    trySetOwnerUserId(json['assignedTo']);
    trySetOwnerUserId(json['ownerUser']);
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
        final nameVal = (val['name'] ?? val['fullName'] ?? val['firstName'] ?? val['userName'] ?? val['username'])?.toString();
        if (nameVal != null && nameVal.trim().isNotEmpty) {
          ownerUserName = nameVal.trim();
        }
      }
    }

    trySetOwnerUserName(json['ownerUserName']);
    trySetOwnerUserName(json['ownerName']);
    trySetOwnerUserName(json['assignedToName']);
    trySetOwnerUserName(json['assignedToInfo']);
    trySetOwnerUserName(json['assigneeName']);
    trySetOwnerUserName(json['assignee']);
    trySetOwnerUserName(json['staffName']);
    trySetOwnerUserName(json['staff']);
    trySetOwnerUserName(json['assignedTo']);
    trySetOwnerUserName(json['ownerUser']);
    trySetOwnerUserName(json['owner']);

    if (ownerUserName == null || ownerUserName!.isEmpty) {
      if (json['assignedTo'] is String && json['assignedTo'].toString().trim().isNotEmpty) {
        ownerUserName = json['assignedTo'].toString().trim();
      } else if (json['owner'] is String && json['owner'].toString().trim().isNotEmpty) {
        ownerUserName = json['owner'].toString().trim();
      }
    }

    String? createdBy = json['createdBy']?.toString();
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
        final nameVal = (val['name'] ?? val['fullName'] ?? val['firstName'] ?? val['userName'] ?? val['username'])?.toString();
        if (nameVal != null && nameVal.trim().isNotEmpty) {
          createdByName = nameVal.trim();
        }
      }
    }

    trySetCreatedByName(json['createdByName']);
    trySetCreatedByName(json['creatorName']);
    trySetCreatedByName(json['createdByUser']);
    trySetCreatedByName(json['creator']);

    final callStatus = json['callStatus']?.toString() ??
        json['call_status']?.toString() ??
        json['lastCallStatus']?.toString() ??
        json['latestCallStatus']?.toString();

    return LeadModel(
      id: json['id'] ?? '',
      leadNumber: json['leadNumber'] ?? '',
      firstName: fName,
      lastName: lName,
      companyName: json['companyName'] ?? '',
      email: json['email'] ?? '',
      phone: phone,
      source: json['source'] != null ? LeadSourceModel.fromJson(json['source']) : null,
      status: json['status'] != null ? LeadStatusModel.fromJson(json['status']) : null,
      priority: json['priority'],
      ownerUserId: ownerUserId,
      ownerUserName: ownerUserName,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'].toString()) 
          : (json['created_at'] != null 
              ? DateTime.tryParse(json['created_at'].toString()) 
              : (json['createdDate'] != null ? DateTime.tryParse(json['createdDate'].toString()) : null)),
      callStatus: callStatus,
    );
  }
}
