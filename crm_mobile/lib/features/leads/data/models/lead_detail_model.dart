import '../../domain/entities/lead_detail.dart';
import 'lead_model.dart';

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
      ownerUserId: json['ownerUserId'],
      ownerUserName: json['ownerUserName'],
      isConverted: json['isConverted'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
      customFields: customFields,
    );
  }
}
