import 'package:equatable/equatable.dart';

class CustomField extends Equatable {
  final String id;
  final String fieldId;
  final String fieldName;
  final String fieldLabel;
  final String label;
  final String fieldType;
  final String type;
  final List<String> options;
  final bool isRequired;
  final int displayOrder;
  final int? minLength;
  final int? maxLength;
  final String? attachmentType;
  final bool active;

  const CustomField({
    required this.id,
    required this.fieldId,
    required this.fieldName,
    required this.fieldLabel,
    required this.label,
    required this.fieldType,
    required this.type,
    required this.options,
    required this.isRequired,
    required this.displayOrder,
    this.minLength,
    this.maxLength,
    this.attachmentType,
    required this.active,
  });

  @override
  List<Object?> get props => [
        id,
        fieldId,
        fieldName,
        fieldLabel,
        label,
        fieldType,
        type,
        options,
        isRequired,
        displayOrder,
        minLength,
        maxLength,
        attachmentType,
        active,
      ];
}

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
