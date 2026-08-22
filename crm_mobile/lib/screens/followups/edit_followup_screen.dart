import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/blocs/followups_bloc.dart';
import 'package:crm_mobile/blocs/followups_event.dart';
import 'package:crm_mobile/blocs/followups_state.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';

class EditFollowUpScreen extends StatelessWidget {
  final FollowUp followUp;
  final LeadDetail leadDetail;

  const EditFollowUpScreen({
    super.key,
    required this.followUp,
    required this.leadDetail,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<FollowUpsBloc>()),
        BlocProvider(
          create: (_) => sl<LeadsBloc>()
            ..add(FetchLeadStatuses())
            ..add(FetchLeadPriorities())
            ..add(const FetchStaffUsers()),
        ),
      ],
      child: EditFollowUpView(followUp: followUp, leadDetail: leadDetail),
    );
  }
}

class EditFollowUpView extends StatefulWidget {
  final FollowUp followUp;
  final LeadDetail leadDetail;

  const EditFollowUpView({
    super.key,
    required this.followUp,
    required this.leadDetail,
  });

  @override
  State<EditFollowUpView> createState() => _EditFollowUpViewState();
}

class _EditFollowUpViewState extends State<EditFollowUpView> {
  // Form keys
  final _leadUpdateFormKey = GlobalKey<FormState>();
  final _completeFormKey = GlobalKey<FormState>();
  final _activityFormKey = GlobalKey<FormState>();

  // Tab 1 (Lead Update) Controllers
  final _leadTaskController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  String? _selectedStatusId;
  String? _selectedPriority;
  String? _selectedAgentId;
  bool _emailAlert = false;
  bool _pushNotification = false;

  // Tab 2 (Complete Follow-up) Controllers
  final _completeRemarksController = TextEditingController();

  // Tab 3 (Activity Log) Controllers
  final _activityRemarksController = TextEditingController();

  DateTime? _selectedDateObj;
  TimeOfDay? _selectedTimeObj;

  @override
  void initState() {
    super.initState();
    // Pre-populate values from current followUp
    _leadTaskController.text = widget.followUp.leadTask;
    _dateController.text = widget.followUp.followUpDate;
    _timeController.text = widget.followUp.followUpTime;

    _selectedStatusId = widget.followUp.leadStatus?.id ?? widget.leadDetail.status?.id;
    _selectedPriority = widget.followUp.priority.isNotEmpty 
        ? widget.followUp.priority.toUpperCase() 
        : widget.leadDetail.priority?.toUpperCase();
    _selectedAgentId = widget.followUp.assignedUser?.id ?? widget.leadDetail.ownerUserId;

    // Parse notification channels
    final reminderStr = widget.followUp.reminder.toLowerCase();
    _emailAlert = reminderStr.contains('email');
    _pushNotification = reminderStr.contains('push');

    _selectedDateObj = DateTime.tryParse(widget.followUp.followUpDate);
    _selectedTimeObj = _parseTime(widget.followUp.followUpTime);
  }

  @override
  void dispose() {
    _leadTaskController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _completeRemarksController.dispose();
    _activityRemarksController.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String timeStr) {
    try {
      final clean = timeStr.trim();
      final parts = clean.split(' ');
      if (parts.length != 2) return null;
      final timeParts = parts[0].split(':');
      if (timeParts.length != 2) return null;
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final period = parts[1].toUpperCase();
      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateObj ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateObj = picked;
        _dateController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimeObj ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTimeObj = picked;
        final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        final minute = picked.minute.toString().padLeft(2, '0');
        final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
        _timeController.text = "${hour.toString().padLeft(2, '0')}:$minute $period";
      });
    }
  }

  void _submitLeadUpdate() {
    if (_leadUpdateFormKey.currentState?.validate() ?? false) {
      final List<String> reminders = [];
      if (_emailAlert) reminders.add("Email");
      if (_pushNotification) reminders.add("Push");

      final updateData = {
        "leadTask": _leadTaskController.text.trim(),
        "statusId": _selectedStatusId,
        "priority": _selectedPriority,
        "assignedUserId": _selectedAgentId,
        "followupDate": _dateController.text,
        "followupTime": _timeController.text,
        "reminder": reminders.isEmpty ? "Email" : reminders.join(', '),
        "remarks": "Rescheduled and updated follow-up details.",
      };

      if (widget.followUp.id != null) {
        context.read<FollowUpsBloc>().add(
              UpdateFollowUp(followupId: widget.followUp.id!, updateData: updateData),
            );
      }
    }
  }

  void _submitCompleteFollowUp() {
    if (_completeFormKey.currentState?.validate() ?? false) {
      final updateData = {
        "completed": true,
        "remarks": _completeRemarksController.text.trim(),
      };

      if (widget.followUp.id != null) {
        context.read<FollowUpsBloc>().add(
              UpdateFollowUp(followupId: widget.followUp.id!, updateData: updateData),
            );
      }
    }
  }

  void _submitActivityLog() {
    if (_activityFormKey.currentState?.validate() ?? false) {
      final updateData = {
        "remarks": _activityRemarksController.text.trim(),
      };

      if (widget.followUp.id != null) {
        context.read<FollowUpsBloc>().add(
              UpdateFollowUp(followupId: widget.followUp.id!, updateData: updateData),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            children: [
              const Text(
                'Edit Follow-up',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                'Manage details, scheduling, and activity logs',
                style: TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
            ],
          ),
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Lead Update'),
              Tab(text: 'Complete'),
              Tab(text: 'Activity Log'),
            ],
          ),
        ),
        body: BlocListener<FollowUpsBloc, FollowUpsState>(
          listener: (context, state) {
            if (state is UpdateFollowUpSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Follow-up updated successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(context, true);
            } else if (state is UpdateFollowUpError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.primary,
                ),
              );
            }
          },
          child: BlocBuilder<FollowUpsBloc, FollowUpsState>(
            builder: (context, state) {
              final isSaving = state is UpdateFollowUpLoading;

              if (isSaving) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text('Saving changes...', style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              return TabBarView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildLeadUpdateTab(),
                  _buildCompleteFollowUpTab(),
                  _buildActivityLogTab(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLeadUpdateTab() {
    return BlocBuilder<LeadsBloc, LeadsState>(
      builder: (context, leadsState) {
        List<LeadStatus> statuses = [];
        List<StaffUser> owners = [];
        List<String> priorities = ['HIGH', 'MEDIUM', 'LOW'];

        if (leadsState is LeadsLoaded) {
          statuses = leadsState.statuses;
          owners = leadsState.owners;
          if (leadsState.priorities.isNotEmpty) {
            priorities = leadsState.priorities.map((p) => p.toUpperCase()).toList();
          }
        }

        // Keep current selections if loaded
        if (statuses.isNotEmpty && _selectedStatusId != null) {
          if (!statuses.any((s) => s.id == _selectedStatusId)) {
            _selectedStatusId = statuses.first.id;
          }
        }
        if (owners.isNotEmpty && _selectedAgentId != null) {
          if (!owners.any((o) => o.userId == _selectedAgentId)) {
            _selectedAgentId = owners.first.userId;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _leadUpdateFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Lead Task / Objective
                

                // 2. Lead Status Dropdown
                CustomDropdownField<String>(
                  label: 'Lead Status',
                  isRequired: true,
                  value: _selectedStatusId,
                  items: statuses.map((s) {
                    return DropdownMenuItem(
                      value: s.id,
                      child: Text(s.statusName, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedStatusId = val),
                ),
                const SizedBox(height: 16),

                // 3. Date & Time Row
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectDate(context),
                        child: AbsorbPointer(
                          child: CustomTextField(
                            label: 'Follow-up Date',
                            isRequired: true,
                            controller: _dateController,
                            suffixIcon: const Icon(Icons.calendar_today, color: AppColors.textHint, size: 18),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectTime(context),
                        child: AbsorbPointer(
                          child: CustomTextField(
                            label: 'Follow-up Time',
                            isRequired: true,
                            controller: _timeController,
                            suffixIcon: const Icon(Icons.access_time, color: AppColors.textHint, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. Notification Channels (Checkboxes)
                const Text(
                  'Notification Channels',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLabel),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: _emailAlert,
                      activeColor: AppColors.primary,
                      onChanged: (val) => setState(() => _emailAlert = val ?? false),
                    ),
                    const Text('Email Alert', style: TextStyle(fontSize: 13, color: AppColors.textLabel)),
                    const SizedBox(width: 24),
                    Checkbox(
                      value: _pushNotification,
                      activeColor: AppColors.primary,
                      onChanged: (val) => setState(() => _pushNotification = val ?? false),
                    ),
                    const Text('Push Notification Popup', style: TextStyle(fontSize: 13, color: AppColors.textLabel)),
                  ],
                ),
                const SizedBox(height: 16),

                // 5. Task Priority Dropdown
                CustomDropdownField<String>(
                  label: 'Task Priority',
                  isRequired: true,
                  value: _selectedPriority,
                  items: priorities.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(p, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedPriority = val),
                ),
                const SizedBox(height: 16),

                // 6. Assigned Agent Dropdown
                CustomDropdownField<String>(
                  label: 'Assigned Agent',
                  isRequired: true,
                  value: _selectedAgentId,
                  items: owners.map((o) {
                    return DropdownMenuItem(
                      value: o.userId,
                      child: Text(o.name, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedAgentId = val),
                ),
                const SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitLeadUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Reschedule & Update',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompleteFollowUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _completeFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Complete Follow-up',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Record a final comment/remarks about the engagement outcome',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Outcome Remarks',
              isRequired: true,
              controller: _completeRemarksController,
              maxLines: 5,
              hintText: 'e.g. Spoke with client. They are interested in bulk CRM setup and asked for a custom pricing proposal.',
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Please enter remarks to mark complete.';
                return null;
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitCompleteFollowUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Completed / Mark Done',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityLogTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _activityFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lead Comment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Add lead comment without changing status',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Comment',
              isRequired: true,
              controller: _activityRemarksController,
              maxLines: 5,
              hintText: 'Enter comment...',
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Please enter a comment to submit.';
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitActivityLog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Submit Comment',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
