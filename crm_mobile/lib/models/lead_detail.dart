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
