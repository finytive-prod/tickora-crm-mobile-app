import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/blocs/followups_bloc.dart';
import 'package:crm_mobile/blocs/followups_event.dart';
import 'package:crm_mobile/blocs/followups_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'edit_followup_screen.dart';
import 'add_followup_screen.dart';

class LeadFollowUpDetailsScreen extends StatelessWidget {
  final String leadId;

  const LeadFollowUpDetailsScreen({super.key, required this.leadId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<FollowUpsBloc>()..add(FetchLeadFollowUps(leadId)),
      child: LeadFollowUpDetailsView(leadId: leadId),
    );
  }
}

class LeadFollowUpDetailsView extends StatefulWidget {
  final String leadId;
  const LeadFollowUpDetailsView({super.key, required this.leadId});

  @override
  State<LeadFollowUpDetailsView> createState() => _LeadFollowUpDetailsViewState();
}

class _LeadFollowUpDetailsViewState extends State<LeadFollowUpDetailsView> {
  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return Colors.grey;
  }

  IconData _getReminderIcon(String reminder) {
    final rem = reminder.toLowerCase();
    if (rem.contains('email')) return Icons.email_outlined;
    if (rem.contains('call') || rem.contains('phone')) return Icons.phone_in_talk_outlined;
    if (rem.contains('sms') || rem.contains('message')) return Icons.sms_outlined;
    if (rem.contains('meeting') || rem.contains('event')) return Icons.meeting_room_outlined;
    if (rem.contains('whatsapp')) return Icons.chat_bubble_outline;
    return Icons.notifications_none_outlined;
  }

  Color _getReminderColor(String reminder) {
    final rem = reminder.toLowerCase();
    if (rem.contains('email')) return Colors.indigo;
    if (rem.contains('call') || rem.contains('phone')) return Colors.green;
    if (rem.contains('sms') || rem.contains('message')) return Colors.teal;
    if (rem.contains('meeting') || rem.contains('event')) return Colors.amber.shade800;
    if (rem.contains('whatsapp')) return const Color(0xFF10B981);
    return AppColors.primary;
  }

  void _copyToClipboard(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('$label copied to clipboard!'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Follow-up Details',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          BlocBuilder<FollowUpsBloc, FollowUpsState>(
            builder: (context, state) {
              if (state is LeadFollowUpsLoaded) {
                return IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                  onPressed: () async {
                    final hasPrivilege = sl<PrivilegeService>().hasPrivilege('FOLLOWUP_UPDATE');
                    final hasFollowups = state.leadFollowUps.followups.isNotEmpty;

                    if (!hasPrivilege) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You do not have the FOLLOWUP_UPDATE privilege!')),
                      );
                      return;
                    }

                    if (!hasFollowups) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('There is no follow-up history to edit for this lead!')),
                      );
                      return;
                    }

                    final followupsBloc = context.read<FollowUpsBloc>();
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditFollowUpScreen(
                          followUp: state.leadFollowUps.followups.first,
                          leadDetail: state.leadFollowUps.leadDetails,
                        ),
                      ),
                    );
                    if (result == true && mounted) {
                      followupsBloc.add(FetchLeadFollowUps(widget.leadId));
                    }
                  },
                );
              }
              return const SizedBox();
            },
          ),
        ],
      ),
      body: BlocBuilder<FollowUpsBloc, FollowUpsState>(
        builder: (context, state) {
          if (state is LeadFollowUpsLoading) {
            return const Center(child: SpinningLogo(size: 60));
          } else if (state is LeadFollowUpsError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Go Back'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (state is LeadFollowUpsLoaded) {
            final leadDetails = state.leadFollowUps.leadDetails;
            final followups = state.leadFollowUps.followups;

            final fullName = '${leadDetails.firstName} ${leadDetails.lastName}'.trim();
            final displayName = fullName.isNotEmpty ? fullName : 'Unnamed Lead';
            final statusColor = leadDetails.status?.color != null 
                ? _hexToColor(leadDetails.status!.color) 
                : AppColors.primary;

            final initials = (leadDetails.firstName.isNotEmpty ? leadDetails.firstName[0] : '') +
                             (leadDetails.lastName.isNotEmpty ? leadDetails.lastName[0] : '');
            final displayInitials = initials.isNotEmpty ? initials.toUpperCase() : 'L';

            // Priority badge styling
            Color priorityBgColor = const Color(0xFFF3F4F6);
            Color priorityTextColor = const Color(0xFF4B5563);
            if (leadDetails.priority != null) {
              final priorityUpper = leadDetails.priority!.toUpperCase();
              if (priorityUpper == 'HIGH') {
                priorityBgColor = const Color(0xFFFEE2E2);
                priorityTextColor = const Color(0xFFEF4444);
              } else if (priorityUpper == 'MEDIUM') {
                priorityBgColor = const Color(0xFFFEF3C7);
                priorityTextColor = const Color(0xFFD97706);
              } else if (priorityUpper == 'LOW') {
                priorityBgColor = const Color(0xFFD1FAE5);
                priorityTextColor = const Color(0xFF059669);
              }
            }

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Lead Header Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppColors.borderEnabled),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: statusColor.withOpacity(0.15),
                                child: Text(
                                  displayInitials,
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 20),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      leadDetails.companyName.isNotEmpty ? leadDetails.companyName : 'No Company Details',
                                      style: const TextStyle(color: AppColors.textHint, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      leadDetails.leadNumber,
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: AppColors.borderEnabled),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Status Chip
                              if (leadDetails.status != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    leadDetails.status!.statusName.toUpperCase(),
                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                                  ),
                                ),
                              // Alignment padding
                              const SizedBox(width: 2),
                              // Priority Chip
                              if (leadDetails.priority != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: priorityBgColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${leadDetails.priority!.toUpperCase()} PRIORITY',
                                    style: TextStyle(color: priorityTextColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                                  ),
                                ),
                              // Alignment padding
                              const SizedBox(width: 2),
                              // Score
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Score: ${leadDetails.score ?? 0}',
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Action Buttons (Call, Email, Details)
                  Row(
                    children: [
                      // Call Action
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            if (leadDetails.phone.isNotEmpty) {
                              AutoCallRecordingUploader.makeCallAndAutoUpload(
                                context: context,
                                leadId: leadDetails.id,
                                phoneNumber: leadDetails.phone,
                                leadName: '${leadDetails.firstName} ${leadDetails.lastName}',
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No phone number available for this lead.')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderEnabled),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.phone, color: Colors.green),
                                SizedBox(height: 4),
                                Text(
                                  'Call Lead',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Email Action
                      Expanded(
                        child: InkWell(
                          onTap: () => _copyToClipboard(leadDetails.email, 'Email Address'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderEnabled),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.email_outlined, color: Colors.indigo),
                                SizedBox(height: 4),
                                Text(
                                  'Copy Email',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Copy Phone
                      Expanded(
                        child: InkWell(
                          onTap: () => _copyToClipboard(leadDetails.phone, 'Phone Number'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderEnabled),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.copy, color: Colors.teal),
                                SizedBox(height: 4),
                                Text(
                                  'Copy Phone',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 3. Lead Contact Details Section
                  const Text(
                    'Lead Contact Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppColors.borderEnabled),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildDetailRow(Icons.phone_iphone, 'Phone', leadDetails.phone.isNotEmpty ? leadDetails.phone : 'Not Specified'),
                          const Divider(height: 24, color: AppColors.borderEnabled),
                          _buildDetailRow(Icons.phone_callback, 'Alternate Phone', leadDetails.alternatePhone != null && leadDetails.alternatePhone!.isNotEmpty ? leadDetails.alternatePhone! : 'Not Specified'),
                          const Divider(height: 24, color: AppColors.borderEnabled),
                          _buildDetailRow(Icons.mail_outline, 'Email', leadDetails.email.isNotEmpty ? leadDetails.email : 'Not Specified'),
                          const Divider(height: 24, color: AppColors.borderEnabled),
                          _buildDetailRow(Icons.campaign_outlined, 'Lead Source', leadDetails.source?.name ?? 'Not Specified'),
                          const Divider(height: 24, color: AppColors.borderEnabled),
                          _buildDetailRow(Icons.person_pin_outlined, 'Owner', leadDetails.ownerUserName ?? 'Unassigned'),
                          if (leadDetails.address != null && leadDetails.address!.trim().isNotEmpty) ...[
                            const Divider(height: 24, color: AppColors.borderEnabled),
                            _buildDetailRow(Icons.map_outlined, 'Address', leadDetails.address!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 4. Timeline
                  const Text(
                    'Follow-up History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  
                  if (followups.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'No follow-up history logged.',
                          style: TextStyle(color: AppColors.textHint, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: followups.length,
                      itemBuilder: (context, index) {
                        final followup = followups[index];
                        final isLast = index == followups.length - 1;
                        return _buildTimelineItem(followup, isLast, leadDetails);
                      },
                    ),
                ],
              ),
            );
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textHint, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                softWrap: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(FollowUp item, bool isLast, LeadDetail leadDetails) {
    final reminderColor = _getReminderColor(item.reminder);
    final reminderIcon = _getReminderIcon(item.reminder);

    // Follow-up status color mapping
    Color statusBgColor = Colors.grey.shade100;
    Color statusTextColor = Colors.grey.shade700;
    final fStatus = item.followUpStatus.toUpperCase();
    if (fStatus.contains('ADD') || fStatus.contains('SCHEDULED')) {
      statusBgColor = Colors.blue.shade50;
      statusTextColor = Colors.blue.shade700;
    } else if (fStatus.contains('COMPLETED') || fStatus.contains('DONE')) {
      statusBgColor = Colors.green.shade50;
      statusTextColor = Colors.green.shade700;
    } else if (fStatus.contains('MISSED') || fStatus.contains('PENDING')) {
      statusBgColor = Colors.red.shade50;
      statusTextColor = Colors.red.shade700;
    }

    // FollowUp Priority styling
    Color priorityColor = Colors.grey;
    if (item.priority.toUpperCase() == 'HIGH') priorityColor = Colors.red;
    if (item.priority.toUpperCase() == 'MEDIUM') priorityColor = Colors.orange;
    if (item.priority.toUpperCase() == 'LOW') priorityColor = Colors.green;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline line/dot column
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: reminderColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: reminderColor.withOpacity(0.3), width: 1),
                ),
                child: Icon(reminderIcon, size: 16, color: reminderColor),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : AppColors.borderEnabled,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Followup card details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status & Priority row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.followUpStatus,
                            style: TextStyle(color: statusTextColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.2),
                          ),
                        ),
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
                              '${item.priority} Priority',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            if (sl<PrivilegeService>().hasPrivilege('FOLLOWUP_UPDATE'))
                              InkWell(
                                onTap: () async {
                                  final followupsBloc = context.read<FollowUpsBloc>();
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditFollowUpScreen(
                                        followUp: item,
                                        leadDetail: leadDetails,
                                      ),
                                    ),
                                  );
                                   if (result == true && mounted) {
                                     followupsBloc.add(FetchLeadFollowUps(widget.leadId));
                                   }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.edit, size: 14, color: AppColors.primary),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Date & Time row
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 6),
                        Text(
                          '${item.followUpDate}  |  ${item.followUpTime}',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Reminder row
                    Row(
                      children: [
                        const Icon(Icons.notifications_none, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 6),
                        Text(
                          'Reminder via: ${item.reminder}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Assigned User row
                    if (item.assignedUser != null)
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: AppColors.textHint),
                          const SizedBox(width: 6),
                          Text(
                            'Assigned to: ${item.assignedUser!.name}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    
                    // Task Details Section (if present/not 'no')
                    if (item.leadTask.isNotEmpty && item.leadTask.toLowerCase() != 'no') ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.borderEnabled),
                      const SizedBox(height: 12),
                      const Text(
                        'Task Details / Notes:',
                        style: TextStyle(color: AppColors.textHint, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.leadTask,
                        style: const TextStyle(color: AppColors.textLabel, fontSize: 13, height: 1.3),
                      ),
                    ],
                    // NO FOLLOW UP Action Button
                    if (item.followUpStatus.toUpperCase().contains('NO FOLLOW UP')) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.borderEnabled),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final followupsBloc = context.read<FollowUpsBloc>();
                            final result = await AddFollowUpScreen.openFromRight(context, leadId: widget.leadId);
                            if (result == true && mounted) {
                              followupsBloc.add(FetchLeadFollowUps(widget.leadId));
                            }
                          },
                          icon: const Icon(Icons.add, size: 16, color: Colors.white),
                          label: const Text('Add Follow Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
