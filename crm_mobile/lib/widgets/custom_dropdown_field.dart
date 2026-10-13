import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class CustomDropdownField<T> extends StatelessWidget {
  final String label;
  final bool isRequired;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final String? hintText;
  final void Function(T?)? onChanged;
  final String? Function(T?)? validator;
  final AutovalidateMode? autovalidateMode;
  final bool enabled;

  const CustomDropdownField({
    super.key,
    required this.label,
    required this.items,
    this.isRequired = false,
    this.value,
    this.hintText,
    this.onChanged,
    this.validator,
    this.autovalidateMode,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final uniqueItems = <DropdownMenuItem<T>>[];
    final seenValues = <T?>{};
    for (var item in items) {
      if (item.value != null && seenValues.add(item.value)) {
        uniqueItems.add(item);
      }
    }
    final effectiveValue = uniqueItems.any((item) => item.value == value) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: RichText(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textLabel,
              ),
              children: [
                if (isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
        DropdownButtonFormField<T>(
          isExpanded: true,
          autovalidateMode: autovalidateMode ?? AutovalidateMode.onUserInteraction,
          value: effectiveValue,
          hint: hintText != null ? Text(hintText!, style: const TextStyle(color: AppColors.textHint, fontSize: 14)) : null,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textHint),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.borderEnabled),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.borderEnabled),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          items: items,
          onChanged: enabled ? onChanged : null,
          validator: enabled
              ? (validator ??
                  (val) {
                    if (isRequired && val == null) {
                      return 'Required';
                    }
                    return null;
                  })
              : (_) => null,
        ),
      ],
    );
  }
}
