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
