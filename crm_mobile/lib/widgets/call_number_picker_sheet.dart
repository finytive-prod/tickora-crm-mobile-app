import 'package:flutter/material.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/services/direct_call_helper.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

/// Represents a selectable phone number option for a CRM lead.
class LeadPhoneOption {
  final String label;
  final String phoneNumber;
  final bool isAlternate;

  const LeadPhoneOption({
    required this.label,
    required this.phoneNumber,
    this.isAlternate = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeadPhoneOption &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          phoneNumber == other.phoneNumber &&
          isAlternate == other.isAlternate;

  @override
  int get hashCode => Object.hash(label, phoneNumber, isAlternate);
}

/// Normalizes a phone number string for equality/deduplication comparison.
///
/// Strips formatting characters and compares the last 10 digits when available
/// so formatted variants such as `+91 98765 43210` and `9876543210` match.
String normalizePhoneComparisonKey(String rawPhone) {
  final trimmed = rawPhone.trim();
  if (trimmed.isEmpty) return '';

  final lower = trimmed.toLowerCase();
  if (lower == '-' ||
      lower == 'n/a' ||
      lower == 'null' ||
      lower == 'none' ||
      lower == 'not specified') {
    return '';
  }

  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3) return '';
  if (digits.length >= 10) {
    return digits.substring(digits.length - 10);
  }
  return digits;
}

/// Returns true when [rawPhone] contains a dialable phone number.
bool isUsablePhoneNumber(String? rawPhone) {
  if (rawPhone == null) return false;
  return normalizePhoneComparisonKey(rawPhone).isNotEmpty;
}

/// Extracts phone/mobile options from [LeadDetailCustomField] entries.
List<LeadPhoneOption> extractLeadDetailCustomPhoneOptions(
  Iterable<LeadDetailCustomField> customFields,
) {
  final options = <LeadPhoneOption>[];
  for (final cf in customFields) {
    final valStr = (cf.value ?? '').toString().trim();
    if (!isUsablePhoneNumber(valStr)) continue;

    final type = cf.fieldType.toLowerCase();
    final name = cf.fieldName.toLowerCase();
    final label = cf.label.toLowerCase();
    final isPhoneField =
        type == 'phone' ||
        type == 'mobile' ||
        type == 'tel' ||
        name.contains('phone') ||
        name.contains('mobile') ||
        label.contains('phone') ||
        label.contains('mobile');
    if (!isPhoneField) continue;

    final displayLabel = cf.label.trim().isNotEmpty
        ? cf.label.trim()
        : (cf.fieldName.trim().isNotEmpty
              ? cf.fieldName.trim()
              : 'Additional Number');
    options.add(
      LeadPhoneOption(
        label: displayLabel,
        phoneNumber: valStr,
        isAlternate: true,
      ),
    );
  }
  return options;
}

/// Builds a deduplicated ordered list of selectable phone options for a lead.
List<LeadPhoneOption> buildDistinctLeadPhoneOptions({
  String? primaryPhone,
  String? alternatePhone,
  Iterable<LeadPhoneOption> extraOptions = const [],
}) {
  final seenKeys = <String>{};
  final result = <LeadPhoneOption>[];

  void addIfDistinct(
    String label,
    String? rawNumber, {
    required bool isAlternate,
  }) {
    if (!isUsablePhoneNumber(rawNumber)) return;
    final trimmed = rawNumber!.trim();
    final key = normalizePhoneComparisonKey(trimmed);
    if (key.isEmpty) return;
    if (seenKeys.add(key)) {
      result.add(
        LeadPhoneOption(
          label: label,
          phoneNumber: trimmed,
          isAlternate: isAlternate,
        ),
      );
    }
  }

  addIfDistinct('Primary Number', primaryPhone, isAlternate: false);
  addIfDistinct('Alternate Number', alternatePhone, isAlternate: true);

  for (final extra in extraOptions) {
    addIfDistinct(
      extra.label,
      extra.phoneNumber,
      isAlternate: extra.isAlternate,
    );
  }

  return result;
}

/// Shows a confirmation dialog asking the user which mobile number to call.
///
/// Returns the selected phone number string, or `null` if cancelled.
Future<String?> showCallNumberPicker({
  required BuildContext context,
  required List<LeadPhoneOption> options,
  String leadName = '',
  String? preferredPhone,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => CallNumberPickerDialog(
      leadName: leadName,
      options: options,
      preferredPhone: preferredPhone,
    ),
  );
}

/// Dialog prompting the user to select and confirm which lead number to call.
class CallNumberPickerDialog extends StatelessWidget {
  final String leadName;
  final List<LeadPhoneOption> options;
  final String? preferredPhone;

  const CallNumberPickerDialog({
    super.key,
    required this.leadName,
    required this.options,
    this.preferredPhone,
  });

  @override
  Widget build(BuildContext context) {
    final cleanName = leadName.trim();
    final pref = preferredPhone;
    final preferredKey = pref != null
        ? normalizePhoneComparisonKey(pref)
        : '';

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_rounded,
              color: Color(0xFF059669),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Select Number to Call',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cleanName.isNotEmpty
                ? '$cleanName has multiple mobile numbers. Confirm which number to call:'
                : 'This lead has multiple mobile numbers. Confirm which number to call:',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ...options.map((option) {
            final isPreferred =
                preferredKey.isNotEmpty &&
                normalizePhoneComparisonKey(option.phoneNumber) == preferredKey;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PhoneOptionTile(
                option: option,
                isHighlighted: isPreferred,
                onTap: () => Navigator.of(context).pop(option.phoneNumber),
              ),
            );
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneOptionTile extends StatelessWidget {
  final LeadPhoneOption option;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _PhoneOptionTile({
    required this.option,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isHighlighted
          ? AppColors.primary.withValues(alpha: 0.06)
          : const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted
                  ? AppColors.primary
                  : const Color(0xFFE5E7EB),
              width: isHighlighted ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                option.isAlternate
                    ? Icons.phone_android_rounded
                    : Icons.phone_rounded,
                size: 20,
                color: isHighlighted
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.phoneNumber,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF059669),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared coordinator for confirming and placing calls to CRM leads.
class LeadCallHelper {
  static bool _isCallFlowActive = false;

  /// Resolves available mobile numbers for a lead, prompts for confirmation when
  /// two or more distinct numbers exist, and places the selected call.
  static Future<void> initiateLeadCall({
    required BuildContext context,
    required String? leadId,
    String? primaryPhone,
    String? alternatePhone,
    Iterable<LeadPhoneOption> extraOptions = const [],
    String leadName = '',
    String? preferredPhone,
    VoidCallback? onBeforeDial,
    Future<void> Function(String selectedNumber)? onDial,
  }) async {
    if (_isCallFlowActive) return;
    _isCallFlowActive = true;

    try {
      final cleanLeadId = (leadId ?? '').trim();
      final combinedExtras = <LeadPhoneOption>[...extraOptions];

      String? resolvedPrimary = primaryPhone;
      String? resolvedAlternate = alternatePhone;

      // Include any previously cached numbers for this lead (e.g. from LeadDetail).
      if (cleanLeadId.isNotEmpty) {
        final cached = AutoCallRecordingUploader.getCachedLeadPhoneRecord(
          cleanLeadId,
        );
        if (cached != null) {
          if (!isUsablePhoneNumber(resolvedPrimary) &&
              isUsablePhoneNumber(cached.primaryPhone)) {
            resolvedPrimary = cached.primaryPhone;
          }
          if (!isUsablePhoneNumber(resolvedAlternate) &&
              isUsablePhoneNumber(cached.alternatePhone)) {
            resolvedAlternate = cached.alternatePhone;
          }
          for (final extra in cached.extraPhones) {
            combinedExtras.add(
              LeadPhoneOption(
                label: 'Alternate Number',
                phoneNumber: extra,
                isAlternate: true,
              ),
            );
          }
        }
      }

      var options = buildDistinctLeadPhoneOptions(
        primaryPhone: resolvedPrimary,
        alternatePhone: resolvedAlternate,
        extraOptions: combinedExtras,
      );

      // Summary endpoints (/leads/filter, /followups) may omit alternatePhone.
      // Check LeadDetail once per leadId when no alternate number is known yet.
      if (cleanLeadId.isNotEmpty &&
          !isUsablePhoneNumber(resolvedAlternate) &&
          options.length <= 1 &&
          !AutoCallRecordingUploader.hasResolvedLeadDetailPhones(cleanLeadId)) {
        final detailPhones = await _tryFetchLeadDetailPhones(cleanLeadId);
        if (detailPhones.isNotEmpty) {
          options = buildDistinctLeadPhoneOptions(
            primaryPhone: resolvedPrimary,
            alternatePhone: resolvedAlternate,
            extraOptions: [...combinedExtras, ...detailPhones],
          );
        }
      }

      if (!context.mounted) return;

      if (options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No phone number available for this lead.'),
          ),
        );
        return;
      }

      final String? chosenNumber;
      if (options.length == 1) {
        chosenNumber = options.first.phoneNumber;
      } else {
        chosenNumber = await showCallNumberPicker(
          context: context,
          options: options,
          leadName: leadName,
          preferredPhone: preferredPhone,
        );
      }

      if (chosenNumber == null || chosenNumber.trim().isEmpty) return;

      onBeforeDial?.call();

      if (onDial != null) {
        await onDial(chosenNumber);
      } else if (cleanLeadId.isNotEmpty) {
        if (!context.mounted) return;
        AutoCallRecordingUploader.makeCallAndAutoUpload(
          context: context,
          leadId: cleanLeadId,
          phoneNumber: chosenNumber,
          leadName: leadName,
        );
      } else {
        await DirectCallHelper.makeCall(chosenNumber);
      }
    } finally {
      _isCallFlowActive = false;
    }
  }

  static Future<List<LeadPhoneOption>> _tryFetchLeadDetailPhones(
    String leadId,
  ) async {
    try {
      if (!sl.isRegistered<LeadsRepository>()) {
        return const [];
      }
      final result = await sl<LeadsRepository>()
          .getLeadDetails(leadId)
          .timeout(const Duration(seconds: 2));
      return result.fold((_) => const [], (detail) {
        final customOptions = extractLeadDetailCustomPhoneOptions(
          detail.customFields,
        );
        AutoCallRecordingUploader.registerLeadPhones(
          leadId: detail.id.isNotEmpty ? detail.id : leadId,
          primaryPhone: detail.phone,
          alternatePhone: detail.alternatePhone,
          extraPhones: customOptions.map((o) => o.phoneNumber),
          hasDetailResolution: true,
        );
        return buildDistinctLeadPhoneOptions(
          primaryPhone: detail.phone,
          alternatePhone: detail.alternatePhone,
          extraOptions: customOptions,
        );
      });
    } catch (_) {
      return const [];
    }
  }
}
