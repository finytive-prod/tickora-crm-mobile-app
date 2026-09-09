import 'package:crm_mobile/models/lead.dart';

class LeadSourceModel extends LeadSource {
  const LeadSourceModel({
    required super.id,
    required super.name,
    required super.category,
    required super.description,
    super.active,
  });

  factory LeadSourceModel.fromJson(Map<String, dynamic> json) {
    return LeadSourceModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      description: json['description'] ?? '',
      active: json['active'] ?? true,
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

  factory LeadStatusModel.fromJson(Map<String, dynamic> json) {
    return LeadStatusModel(
      id: json['id'] ?? '',
      statusName: json['statusName'] ?? '',
      color: json['color'] ?? '',
      isDefault: json['isDefault'] ?? false,
      isClosed: json['isClosed'] ?? false,
      displayOrder: json['displayOrder'] ?? 0,
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
      ownerUserId: json['ownerUserId'],
      ownerUserName: json['ownerUserName'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }
}
