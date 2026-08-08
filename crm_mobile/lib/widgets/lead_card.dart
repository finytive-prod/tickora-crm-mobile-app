import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import '../core/theme/app_colors.dart';

class LeadCard extends StatelessWidget {
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: avatarColor,
                radius: 20,
                child: Text(
                  initials,
                  style: TextStyle(color: avatarTextColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    Text(
                      company,
                      style: const TextStyle(color: AppColors.textHint, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusTextColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (phone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 18.0),
                      child: InkWell(
                        onTap: () async {
                          await FlutterPhoneDirectCaller.callNumber(phone);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.phone,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(color: AppColors.textLabel, fontSize: 14),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 12),
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
              const SizedBox(width: 6),
              Text(
                priority,
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'Assignee: $assignee',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
