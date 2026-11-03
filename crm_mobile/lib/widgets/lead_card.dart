import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/services/direct_call_helper.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class LeadCard extends StatelessWidget {
  final String? leadId;
  final String? leadNumber;
  final String initials;
  final Color avatarColor;
  final Color avatarTextColor;
  final String name;
  final String company;
  final String? email;
  final String? source;
  final String status;
  final Color statusBgColor;
  final Color statusTextColor;
  final String description;
  final String priority;
  final Color priorityColor;
  final String assignee;
  final String phone;
  final String? createdByName;
  final DateTime? createdAt;
  final String? callStatus;

  const LeadCard({
    super.key,
    this.leadId,
    this.leadNumber,
    required this.initials,
    this.avatarColor = const Color(0xFFFDE8E1),
    this.avatarTextColor = const Color(0xFFD97706),
    required this.name,
    required this.company,
    this.email,
    this.source,
    required this.status,
    required this.statusBgColor,
    required this.statusTextColor,
    this.description = '',
    required this.priority,
    required this.priorityColor,
    required this.assignee,
    required this.phone,
    this.createdByName,
    this.createdAt,
    this.callStatus,
  });

  String? get _formattedCreatedAt {
    if (createdAt == null) return null;
    return DateFormat('MMM dd, yyyy, hh:mm a').format(createdAt!.toLocal());
  }

  String _formatCallStatus(String statusStr) {
    final s = statusStr.trim();
    if (s.isEmpty) return '';

    final words = s.replaceAll('_', ' ').split(' ');
    final capitalized = words
        .map((w) {
          if (w.isEmpty) return '';
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .where((w) => w.isNotEmpty)
        .join(' ');

    return capitalized;
  }

  Color _getCallStatusColor(String statusStr) {
    final s = statusStr.trim().toUpperCase();
    if (s == 'MISSED') {
      return Colors.red;
    }
    if (s == 'NOT_CONNECTED' || s == 'UNANSWERED' || s == 'REJECTED') {
      return Colors.orange;
    }
    if (s == 'CONNECTED' ||
        s == 'ANSWERED' ||
        s == 'INCOMING' ||
        s == 'OUTGOING') {
      return Colors.green;
    }
    return AppColors.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final hasCompany = company.trim().isNotEmpty && company.trim() != '-';
    final hasPhone = phone.trim().isNotEmpty && phone.trim() != '-';

    final hasCreator =
        createdByName != null && createdByName!.trim().isNotEmpty;
    final creatorNameStr = hasCreator
        ? createdByName!.trim()
        : (priority.trim().isNotEmpty ? priority : '-');
    final assigneeNameStr = assignee.trim().isNotEmpty
        ? assignee.trim()
        : 'Unassigned';
    final createdAtStr = _formattedCreatedAt;

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
                backgroundColor: const Color(0xFFFDE8E1),
                radius: 18,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasCompany)
                      Text(
                        company,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (hasPhone)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          phone,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        // Call Action
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
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: hasCreator ? 'By: ' : '',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          TextSpan(
                            text: creatorNameStr,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (createdAtStr != null && createdAtStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        createdAtStr,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: 'Owner: ',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          TextSpan(
                            text: assigneeNameStr,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                    if (callStatus != null &&
                        callStatus!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          text: 'Call Status: ',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: _formatCallStatus(callStatus!),
                              style: TextStyle(
                                color: _getCallStatusColor(callStatus!),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
