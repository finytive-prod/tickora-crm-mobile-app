import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/pipeline_model.dart';
import 'package:crm_mobile/screens/leads/lead_details_screen.dart';

class PipelineLeadCard extends StatelessWidget {
  final PipelineLeadItem lead;
  final PipelineStatus status;
  final VoidCallback? onStatusTap;

  const PipelineLeadCard({
    super.key,
    required this.lead,
    required this.status,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LeadDetailsScreen(leadId: lead.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Drag Handle, Name, Priority Badge, Arrow
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        lead.fullName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildPriorityBadge(lead.priority),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textHint),
                  ],
                ),
                const SizedBox(height: 8),

                // Company Name if present
                if (lead.companyName.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.domain_outlined, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lead.companyName,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],

                // Email
                if (lead.email.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.mail_outline, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lead.email,
                          style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],

                // Phone
                if (lead.phone.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lead.phone,
                          style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ] else
                  const SizedBox(height: 6),

                const Divider(color: Color(0xFFF3F4F6), height: 1),
                const SizedBox(height: 8),

                // Bottom Row: Status Tag (Clickable to change status) & Assigned Owner
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Clickable Status Pill for 1-tap status change
                    Flexible(
                      child: InkWell(
                        onTap: onStatusTap,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: status.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: status.color.withValues(alpha: 0.3), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  status.statusName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: status.color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.arrow_drop_down_rounded, size: 14, color: status.color),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Owner Name
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 9,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            child: Text(
                              lead.ownerUsername.isNotEmpty ? lead.ownerUsername[0].toUpperCase() : 'U',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              lead.ownerUsername.isNotEmpty ? lead.ownerUsername : 'Unassigned',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color bg = const Color(0xFFF3F4F6);
    Color fg = const Color(0xFF6B7280);

    final upper = priority.toUpperCase();
    if (upper == 'HIGH') {
      bg = AppColors.secondary;
      fg = AppColors.primary;
    } else if (upper == 'MEDIUM') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
    } else if (upper == 'LOW') {
      bg = const Color(0xFFE0E7FF);
      fg = const Color(0xFF4F46E5);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority.isEmpty ? 'Low' : '${priority[0].toUpperCase()}${priority.substring(1).toLowerCase()}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
