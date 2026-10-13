import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';

class LeadActivitiesTab extends StatelessWidget {
  final LeadDetailsLoaded state;

  const LeadActivitiesTab({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.auditLogs == null && !state.isAuditLogsLoading && state.auditLogsError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
      });
      return const Center(child: SpinningLogo(size: 40));
    }
    if (state.isAuditLogsLoading && state.auditLogs == null) {
      return const Center(child: SpinningLogo(size: 40));
    }
    if (state.auditLogsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                state.auditLogsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.primary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final logs = state.auditLogs?.content ?? [];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Activity History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.primary),
                tooltip: 'Refresh Activities',
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing activities...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No activities recorded yet.',
                      style: TextStyle(color: AppColors.textHint, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];

                      // Define action icons and colors
                      IconData actionIcon = Icons.info_outline;
                      Color actionColor = Colors.blue;

                      if (log.actionType == 'CREATE') {
                        actionIcon = Icons.add_circle_outline;
                        actionColor = Colors.green;
                      } else if (log.actionType == 'UPDATE') {
                        actionIcon = Icons.edit_outlined;
                        actionColor = Colors.orange;
                      } else if (log.actionType == 'DELETE') {
                        actionIcon = Icons.delete_outline;
                        actionColor = Colors.red;
                      }

                      final timeStr = log.actionAt != null
                          ? DateFormat('MMM dd, yyyy  •  h:mm a').format(log.actionAt!)
                          : 'Just now';

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Timeline line & icon
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: actionColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(actionIcon, color: actionColor, size: 18),
                              ),
                              if (index < logs.length - 1)
                                Container(
                                  width: 2,
                                  height: 50,
                                  color: AppColors.borderEnabled,
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),

                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log.message,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'By ${log.actionByName.trim()}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textHint,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.textHint, shape: BoxShape.circle)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textHint,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
