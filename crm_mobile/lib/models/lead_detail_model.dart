import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/lead_model.dart';

class LeadDetailCustomFieldModel extends LeadDetailCustomField {
  const LeadDetailCustomFieldModel({
    required super.fieldId,
    required super.fieldName,
    required super.label,
    required super.fieldType,
    required super.value,
  });

  factory LeadDetailCustomFieldModel.fromJson(Map<String, dynamic> json) {
    return LeadDetailCustomFieldModel(
      fieldId: json['fieldId'] ?? '',
      fieldName: json['fieldName'] ?? '',
      label: json['label'] ?? '',
      fieldType: json['fieldType'] ?? '',
      value: json['value'],
    );
  }
}

class LeadDetailModel extends LeadDetail {
  const LeadDetailModel({
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
    super.score,
    super.priority,
    super.industry,
    super.annualRevenue,
    super.employeeSize,
    super.website,
    super.country,
    super.state,
    super.city,
    super.postalCode,
    super.address,
    super.description,
    super.ownerUserId,
    super.ownerUserName,
    super.isConverted,
    super.createdAt,
    super.updatedAt,
    super.customFields,
  });

  factory LeadDetailModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> list = json['customFields'] ?? [];
    final customFields = list.map((e) => LeadDetailCustomFieldModel.fromJson(e)).toList();

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

    return LeadDetailModel(
      id: json['id'] ?? '',
      leadNumber: json['leadNumber'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      companyName: json['companyName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      alternatePhone: json['alternatePhone'],
      source: json['source'] != null ? LeadSourceModel.fromJson(json['source']) : null,
      status: json['status'] != null ? LeadStatusModel.fromJson(json['status']) : null,
      score: json['score'] is int ? json['score'] : (json['score'] != null ? int.tryParse(json['score'].toString()) : null),
      priority: json['priority'],
      industry: json['industry'],
      annualRevenue: json['annualRevenue'] is double 
          ? json['annualRevenue'] 
          : (json['annualRevenue'] != null ? double.tryParse(json['annualRevenue'].toString()) : null),
      employeeSize: json['employeeSize'] is int 
          ? json['employeeSize'] 
          : (json['employeeSize'] != null ? int.tryParse(json['employeeSize'].toString()) : null),
      website: json['website'] ?? '',
      country: json['country'] ?? '',
      state: json['state'] ?? '',
      city: json['city'] ?? '',
      postalCode: json['postalCode'] ?? '',
      address: json['address'] ?? '',
      description: json['description'] ?? '',
      ownerUserId: ownerUserId,
      ownerUserName: ownerUserName,
      isConverted: json['isConverted'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
      customFields: customFields,
    );
  }
}
