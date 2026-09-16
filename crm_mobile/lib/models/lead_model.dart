import 'package:crm_mobile/models/lead.dart';

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

class LeadStatusModel extends LeadStatus {
  const LeadStatusModel({
    required super.id,
    required super.statusName,
    required super.color,
    required super.isDefault,
    required super.isClosed,
    required super.displayOrder,
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
      );
    }
    if (json is Map<String, dynamic>) {
      return LeadStatusModel(
        id: json['id'] ?? '',
        statusName: json['statusName'] ?? json['name'] ?? '',
        color: json['color'] ?? '#6B7280',
        isDefault: json['isDefault'] ?? false,
        isClosed: json['isClosed'] ?? false,
        displayOrder: json['displayOrder'] ?? 0,
      );
    }
    return const LeadStatusModel(
      id: '',
      statusName: '',
      color: '#6B7280',
      isDefault: false,
      isClosed: false,
      displayOrder: 0,
    );
  }
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
    super.createdAt,
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
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }
}
