import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/core/utils/validators.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final bool isRequired;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final String? hintText;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final AutovalidateMode? autovalidateMode;

  const CustomTextField({
    super.key,
    required this.label,
    this.isRequired = false,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.controller,
    this.inputFormatters,
    this.suffixIcon,
    this.hintText,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.autovalidateMode,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  late FocusNode _focusNode;
  bool _createdInternalFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _createdInternalFocusNode = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_createdInternalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<TextInputFormatter> effectiveFormatters = [
      AppInputFormatters.denyEmoji,
      ...?widget.inputFormatters,
    ];

    final isInteractive = widget.enabled && !widget.readOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: RichText(
            text: TextSpan(
              text: widget.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textLabel,
              ),
              children: [
                if (widget.isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        ),
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: widget.keyboardType,
          maxLines: widget.maxLines,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          style: TextStyle(
            fontSize: 14,
            color: isInteractive ? AppColors.textPrimary : AppColors.textSecondary,
          ),
          autovalidateMode: widget.autovalidateMode ?? AutovalidateMode.onUserInteraction,
          onChanged: widget.onChanged,
          inputFormatters: effectiveFormatters,
          decoration: InputDecoration(
            hintText: widget.hintText ?? widget.label,
            hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
            suffixIcon: widget.suffixIcon,
            filled: true,
            fillColor: isInteractive ? Colors.white : const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            errorMaxLines: 3,
            errorStyle: const TextStyle(fontSize: 11, height: 1.2),
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
              borderSide: const BorderSide(color: AppColors.borderEnabled),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            // 1. Required check: if value is empty, show required error
            if (widget.isRequired && trimmed.isEmpty) {
              return '${widget.label} is required';
            }
            if (AppValidators.hasEmoji(value)) {
              return '${widget.label} cannot contain emojis';
            }

            // 2. When validator is provided, run full field validation
            if (widget.validator != null) {
              return widget.validator!(value);
            }
            return null;
          },
        ),
      ],
    );
  }
}
