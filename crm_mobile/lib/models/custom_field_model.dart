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
    final rawFieldLabel = json['fieldLabel'] as String? ?? json['label'] as String? ?? json['fieldName'] as String? ?? json['name'] as String? ?? '';
    final rawLabel = json['label'] as String? ?? json['fieldLabel'] as String? ?? json['fieldName'] as String? ?? json['name'] as String? ?? '';
    final rawFieldId = json['fieldId'] as String? ?? json['id'] as String? ?? json['_id'] as String? ?? json['fieldName'] as String? ?? '';
    final rawFieldName = json['fieldName'] as String? ?? json['name'] as String? ?? json['fieldId'] as String? ?? '';

    return CustomFieldModel(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      fieldId: rawFieldId,
      fieldName: rawFieldName,
      fieldLabel: rawFieldLabel,
      label: rawLabel,
      fieldType: json['fieldType'] as String? ?? json['type'] as String? ?? '',
      type: json['type'] as String? ?? json['fieldType'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isRequired: json['required'] as bool? ?? json['isRequired'] as bool? ?? false,
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

