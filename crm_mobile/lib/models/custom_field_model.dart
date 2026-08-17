import 'package:crm_mobile/models/custom_field.dart';

class CustomFieldModel extends CustomField {
  const CustomFieldModel({
    required super.id,
    required super.fieldId,
    required super.fieldName,
    required super.fieldLabel,
    required super.label,
    required super.fieldType,
    required super.type,
    required super.options,
    required super.isRequired,
    required super.displayOrder,
    super.minLength,
    super.maxLength,
    super.attachmentType,
    required super.active,
  });

  factory CustomFieldModel.fromJson(Map<String, dynamic> json) {
    return CustomFieldModel(
      id: json['id'] as String? ?? '',
      fieldId: json['fieldId'] as String? ?? '',
      fieldName: json['fieldName'] as String? ?? '',
      fieldLabel: json['fieldLabel'] as String? ?? '',
      label: json['label'] as String? ?? json['fieldLabel'] as String? ?? '',
      fieldType: json['fieldType'] as String? ?? '',
      type: json['type'] as String? ?? json['fieldType'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isRequired: json['required'] as bool? ?? false,
      displayOrder: json['displayOrder'] as int? ?? 0,
      minLength: json['minLength'] as int?,
      maxLength: json['maxLength'] as int?,
      attachmentType: json['attachmentType'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fieldId': fieldId,
      'fieldName': fieldName,
      'fieldLabel': fieldLabel,
      'label': label,
      'fieldType': fieldType,
      'type': type,
      'options': options,
      'required': isRequired,
      'displayOrder': displayOrder,
      'minLength': minLength,
      'maxLength': maxLength,
      'attachmentType': attachmentType,
      'active': active,
    };
  }
}

