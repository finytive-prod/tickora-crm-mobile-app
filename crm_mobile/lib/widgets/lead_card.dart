import 'package:flutter/material.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/services/direct_call_helper.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class LeadCard extends StatelessWidget {
  final String? leadId;
  final String initials;
  final Color avatarColor;
  final Color avatarTextColor;
  final String name;
  final String company;
  final String status;
  final Color statusBgColor;
  final Color statusTextColor;
  final String description;
  final String priority;
  final Color priorityColor;
  final String assignee;
  final String phone;

  const LeadCard({
    super.key,
    this.leadId,
    required this.initials,
    required this.avatarColor,
    required this.avatarTextColor,
    required this.name,
    required this.company,
    required this.status,
    required this.statusBgColor,
    required this.statusTextColor,
    required this.description,
    required this.priority,
    required this.priorityColor,
    required this.assignee,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final hasCompany = company.trim().isNotEmpty && company.trim() != '-';
    final hasPhone = phone.trim().isNotEmpty && phone.trim() != '-';
    final hasDescription = description.trim().isNotEmpty &&
        description.trim() != '-' &&
        description.trim() != 'No description available.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: avatarColor,
                radius: 18,
                child: Text(
                  initials,
                  style: TextStyle(color: avatarTextColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasCompany)
                      Text(
                        company,
                        style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (hasPhone)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          phone,
                          style: const TextStyle(color: AppColors.textHint, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusTextColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (hasPhone) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        if (leadId != null && leadId!.isNotEmpty) {
                          AutoCallRecordingUploader.makeCallAndAutoUpload(
                            context: context,
                            leadId: leadId!,
                            phoneNumber: phone,
                            leadName: name,
                          );
                        } else {
                          await DirectCallHelper.makeCall(phone);
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (hasDescription) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: AppColors.textLabel, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: priorityColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                priority,
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
              const Spacer(),
              Text(
                'Assignee: $assignee',
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
