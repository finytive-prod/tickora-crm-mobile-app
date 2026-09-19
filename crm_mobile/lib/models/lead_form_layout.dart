import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/custom_field.dart';

class FixedField extends Equatable {
  final String fieldName;
  final String fieldLabel;
  final String fieldType;
  final bool isRequired;
  final int displayOrder;

  const FixedField({
    required this.fieldName,
    required this.fieldLabel,
    required this.fieldType,
    required this.isRequired,
    required this.displayOrder,
  });

  factory FixedField.fromJson(Map<String, dynamic> json) {
    return FixedField(
      fieldName: json['fieldName'] as String? ?? '',
      fieldLabel: json['fieldLabel'] as String? ?? json['fieldName'] as String? ?? '',
      fieldType: json['fieldType'] as String? ?? 'TEXT',
      isRequired: json['isRequired'] as bool? ?? json['required'] as bool? ?? false,
      displayOrder: json['displayOrder'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [fieldName, fieldLabel, fieldType, isRequired, displayOrder];
}

class LeadFormLayout extends Equatable {
  final List<FixedField> fixedFields;
  final List<CustomField> customFields;

  const LeadFormLayout({
    required this.fixedFields,
    required this.customFields,
  });

  factory LeadFormLayout.fromJson(Map<String, dynamic> json) {
    final fixedList = (json['fixedFields'] as List<dynamic>?)
            ?.map((e) => FixedField.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final customList = (json['customFields'] as List<dynamic>?)
            ?.map((e) => CustomFieldModel.fromJson(e as Map<String, dynamic>))
            .where((f) => f.active)
            .toList() ??
        [];

    fixedList.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    customList.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return LeadFormLayout(
      fixedFields: fixedList,
      customFields: customList,
    );
  }

  @override
  List<Object?> get props => [fixedFields, customFields];
}
