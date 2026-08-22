import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/followups_bloc.dart';
import 'package:crm_mobile/blocs/followups_event.dart';
import 'package:crm_mobile/blocs/followups_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';

class AddFollowUpScreen extends StatelessWidget {
  final String leadId;

  const AddFollowUpScreen({super.key, required this.leadId});

  static Future<bool?> openFromRight(BuildContext context, {required String leadId}) {
    return Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AddFollowUpScreen(leadId: leadId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<FollowUpsBloc>(),
      child: _AddFollowUpView(leadId: leadId),
    );
  }
}

class _AddFollowUpView extends StatefulWidget {
  final String leadId;

  const _AddFollowUpView({required this.leadId});

  @override
  State<_AddFollowUpView> createState() => _AddFollowUpViewState();
}

class _AddFollowUpViewState extends State<_AddFollowUpView> {
  final _formKey = GlobalKey<FormState>();

  bool _enableReminder = true;
  DateTime? _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay? _selectedTime = const TimeOfDay(hour: 11, minute: 47);
  String _repeatCycle = 'NONE';
  final TextEditingController _descriptionController = TextEditingController();

  bool _notifyEmail = true;
  bool _notifySMS = false;
  bool _notifyPush = true;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _submit() {
    if (validateAndScrollToError(_formKey)) {
      final dateStr = _selectedDate != null
          ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
          : DateFormat('yyyy-MM-dd').format(DateTime.now());

      final timeStr = _selectedTime != null
          ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
          : '09:00';

      final body = {
        "enableReminder": _enableReminder,
        "reminderDate": dateStr,
        "reminderTime": timeStr,
        "repeat": _repeatCycle,
        "notifyEmail": _notifyEmail,
        "notifySMS": _notifySMS,
        "notifyPush": _notifyPush,
        "description": _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      };

      context.read<FollowUpsBloc>().add(AddFollowUpEvent(leadId: widget.leadId, data: body));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FollowUpsBloc, FollowUpsState>(
      listener: (context, state) {
        if (state is AddFollowUpSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Follow-up added successfully'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          Navigator.of(context).pop(true);
        } else if (state is AddFollowUpError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is AddFollowUpLoading;

        return Scaffold(
          backgroundColor: AppColors.secondary,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_none_outlined, color: AppColors.primary, size: 24),
                      const SizedBox(width: 10),
                      const Text(
                        'Follow-up Reminder',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textHint, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderEnabled),

                // Form Content
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Enable Follow-up Task Reminder
                          Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: _enableReminder,
                                  activeColor: AppColors.primary,
                                  onChanged: (val) {
                                    setState(() {
                                      _enableReminder = val ?? true;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Enable Follow-up Task Reminder',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Reminder Date & Reminder Time Row
                          Row(
                            children: [
                              // Reminder Date
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Reminder Date',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: _selectDate,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: AppColors.borderEnabled),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _selectedDate != null
                                                  ? DateFormat('dd-MM-yyyy').format(_selectedDate!)
                                                  : 'dd-mm-yyyy',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: _selectedDate != null ? AppColors.textPrimary : AppColors.textHint,
                                              ),
                                            ),
                                            const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textHint),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Reminder Time
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Reminder Time',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: _selectTime,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: AppColors.borderEnabled),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _selectedTime != null
                                                  ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                                                  : '--:--',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: _selectedTime != null ? AppColors.textPrimary : AppColors.textHint,
                                              ),
                                            ),
                                            const Icon(Icons.access_time, size: 18, color: AppColors.textHint),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Repeat Cycle Dropdown
                          RichText(
                            text: const TextSpan(
                              text: '* ',
                              style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                              children: [
                                TextSpan(
                                  text: 'Repeat Cycle',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _repeatCycle,
                            items: const [
                              DropdownMenuItem(value: 'NONE', child: Text('None')),
                              DropdownMenuItem(value: 'DAILY', child: Text('Daily')),
                              DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
                              DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                              DropdownMenuItem(value: 'YEARLY', child: Text('Yearly')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _repeatCycle = val;
                                });
                              }
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.borderEnabled),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.borderEnabled),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.primary),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Description (Optional)
                          const Text(
                            'Description (Optional)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Enter follow-up description',
                              hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.borderEnabled),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.borderEnabled),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.primary),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // NOTIFICATION CHANNELS
                          const Text(
                            'NOTIFICATION CHANNELS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textHint,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              // Email Alert
                              Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: _notifyEmail,
                                      activeColor: AppColors.primary,
                                      onChanged: (val) {
                                        setState(() {
                                          _notifyEmail = val ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Email Alert',
                                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 24),

                              // Push Notification Popup
                              Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: _notifyPush,
                                      activeColor: AppColors.primary,
                                      onChanged: (val) {
                                        setState(() {
                                          _notifyPush = val ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Push Notification Popup',
                                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Action Buttons: Cancel and Add Follow Up
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: const BorderSide(color: AppColors.borderEnabled),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Text(
                                          'Add Follow Up',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
}
