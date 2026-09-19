import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/lead.dart';

class LeadDetailCustomField extends Equatable {
  final String fieldId;
  final String fieldName;
  final String label;
  final String fieldType;
  final dynamic value;

  const LeadDetailCustomField({
    required this.fieldId,
    required this.fieldName,
    required this.label,
    required this.fieldType,
    required this.value,
  });

  @override
  List<Object?> get props => [fieldId, fieldName, label, fieldType, value];
}

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

class LeadDetail extends Equatable {
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
  final int? score;
  final String? priority;
  final String? industry;
  final double? annualRevenue;
  final int? employeeSize;
  final String? website;
  final String? country;
  final String? state;
  final String? city;
  final String? postalCode;
  final String? address;
  final String? description;
  final String? ownerUserId;
  final String? ownerUserName;
  final bool? isConverted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<LeadDetailCustomField> customFields;

  const LeadDetail({
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
    this.score,
    this.priority,
    this.industry,
    this.annualRevenue,
    this.employeeSize,
    this.website,
    this.country,
    this.state,
    this.city,
    this.postalCode,
    this.address,
    this.description,
    this.ownerUserId,
    this.ownerUserName,
    this.isConverted,
    this.createdAt,
    this.updatedAt,
    this.customFields = const [],
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
        score,
        priority,
        industry,
        annualRevenue,
        employeeSize,
        website,
        country,
        state,
        city,
        postalCode,
        address,
        description,
        ownerUserId,
        ownerUserName,
        isConverted,
        createdAt,
        updatedAt,
        customFields,
      ];
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
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'].toString()) 
          : (json['created_at'] != null 
              ? DateTime.tryParse(json['created_at'].toString()) 
              : (json['createdDate'] != null ? DateTime.tryParse(json['createdDate'].toString()) : null)),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.tryParse(json['updatedAt'].toString()) 
          : (json['updated_at'] != null 
              ? DateTime.tryParse(json['updated_at'].toString()) 
              : (json['updatedDate'] != null ? DateTime.tryParse(json['updatedDate'].toString()) : null)),
      customFields: customFields,
    );
  }
}
