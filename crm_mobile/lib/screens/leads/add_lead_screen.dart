import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/validators.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/lead_form_layout.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/repositories/followups_repository.dart';

class AddLeadScreen extends StatefulWidget {
  final LeadDetail? leadToEdit;
  final String? targetFieldKey;
  final int? initialStep;
  const AddLeadScreen({
    super.key,
    this.leadToEdit,
    this.targetFieldKey,
    this.initialStep,
  });

  @override
  State<AddLeadScreen> createState() => _AddLeadScreenState();
}

class _AddLeadScreenState extends State<AddLeadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();
  final _step4FormKey = GlobalKey<FormState>();
  AutovalidateMode _step1AutovalidateMode = AutovalidateMode.disabled;
  AutovalidateMode _step2AutovalidateMode = AutovalidateMode.disabled;
  AutovalidateMode _step3AutovalidateMode = AutovalidateMode.disabled;
  AutovalidateMode _step4AutovalidateMode = AutovalidateMode.disabled;
  final _stepScrollController = ScrollController();
  final Map<String, TextEditingController> _customFieldControllers = {};

  // Wizard State
  late final PageController _pageController;
  int _currentPage = 0;
  final Set<int> _visitedPages = {};
  bool _hasCompletedOptionalSteps = false;

  // Controllers to capture data
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _scoreController = TextEditingController();
  final _industryController = TextEditingController();
  final _revenueController = TextEditingController();
  final _employeeSizeController = TextEditingController();
  final _websiteController = TextEditingController();
  final _countryController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Follow-up Tab
  final _leadNameController = TextEditingController();
  final _reminderDateController = TextEditingController();
  final _reminderTimeController = TextEditingController();
  final _reminderIntervalController = TextEditingController();
  final _repeatCycleController = TextEditingController();
  final _assignedAgentController = TextEditingController();
  final _agendaController = TextEditingController();
  bool _emailAlert = true;
  bool _pushNotification = true;
  bool _smsAlert = false;
  String _selectedPriorityLevel = 'Medium';

  // Notes & Attachments Tab
  final _notesController = TextEditingController();
  final List<fp.PlatformFile> _followUpFiles = [];

  // Custom Fields Tab (values are loaded dynamically from API)

  String? _selectedSource;
  String? _selectedStatus;
  String? _selectedPriority; // from main form
  String? _selectedOwner;

  // Custom Fields Dynamic Values
  final Map<String, dynamic> _customFieldValues = {};

  bool get _isSingleFieldEdit {
    if (widget.targetFieldKey == null || widget.targetFieldKey!.isEmpty)
      return false;
    final k = widget.targetFieldKey!.toLowerCase().trim();
    if (k == 'followup' ||
        k == 'follow_up' ||
        k == 'schedule' ||
        k == 'schedule_followup') {
      return false;
    }
    return true;
  }

  bool get _isFollowUpOnlyFlow {
    if (widget.targetFieldKey == null) return false;
    final k = widget.targetFieldKey!.toLowerCase().trim();
    return k == 'followup' ||
        k == 'follow_up' ||
        k == 'schedule' ||
        k == 'schedule_followup';
  }

  bool _isFieldEditable(String key) {
    if (!_isSingleFieldEdit) {
      return true; // General edit or full tab edit -> ALL fields editable
    }
    final target = widget.targetFieldKey!.toLowerCase().trim();
    final current = key.toLowerCase().trim();

    if (target == current) return true;

    if (target == 'name' && (current == 'firstname' || current == 'lastname')) {
      return true;
    }
    if (target == 'address' &&
        (current == 'address' ||
            current == 'city' ||
            current == 'state' ||
            current == 'country' ||
            current == 'postalcode')) {
      return true;
    }
    if ((target == 'company' || target == 'companyname') &&
        current == 'companyname') {
      return true;
    }
    if ((target == 'owner' || target == 'owneruserid') &&
        (current == 'owner' || current == 'owneruserid')) {
      return true;
    }
    if ((target == 'status' || target == 'statusid') &&
        (current == 'status' || current == 'statusid'))
      return true;
    if ((target == 'source' || target == 'sourceid') &&
        (current == 'source' || current == 'sourceid'))
      return true;
    if ((target == 'alternatephone' || target == 'altphone') &&
        current == 'alternatephone')
      return true;

    if (target.startsWith('customfield_') &&
        current.startsWith('customfield_')) {
      return target == current;
    }

    return false;
  }

  String _getFieldDisplayName(String key) {
    final k = key.toLowerCase();
    if (k == 'email') return 'Email';
    if (k == 'phone') return 'Phone';
    if (k == 'alternatephone' || k == 'altphone') return 'Alternate Phone';
    if (k == 'website') return 'Website';
    if (k == 'address') return 'Address';
    if (k == 'owneruserid' || k == 'owner') return 'Owner';
    if (k == 'priority') return 'Priority';
    if (k == 'sourceid' || k == 'source') return 'Source';
    if (k == 'description') return 'Description';
    if (k == 'companyname' || k == 'company') return 'Company';
    if (k == 'name' || k == 'firstname' || k == 'lastname') return 'Name';
    if (k.startsWith('customfield_')) return 'Custom Field';
    return 'Field';
  }

  String? _currentUserId;

  void _loadCurrentUser() {
    if (sl.isRegistered<SharedPreferences>()) {
      final prefs = sl<SharedPreferences>();
      _currentUserId = prefs.getString('userId');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();

    int initialPage = widget.initialStep ?? 0;
    if (widget.initialStep == null &&
        widget.targetFieldKey != null &&
        widget.targetFieldKey!.isNotEmpty) {
      final key = widget.targetFieldKey!.toLowerCase();
      if (key.startsWith('customfield') || key.startsWith('cf_')) {
        initialPage = 1;
      } else if (key == 'status' || key == 'statusid' || key == 'lead_status') {
        initialPage = 2;
      } else if (key == 'reminderdate' ||
          key == 'remindertime' ||
          key == 'repeat' ||
          key == 'followup' ||
          key == 'follow_up' ||
          key == 'schedule' ||
          key == 'notes' ||
          key == 'attachment' ||
          key == 'attachments' ||
          key == 'file' ||
          key == 'files') {
        initialPage = 3;
      }
    }
    _currentPage = initialPage;
    _visitedPages.add(initialPage);
    _pageController = PageController(initialPage: initialPage);

    // Fetch dropdown data just in case they aren't loaded yet
    final currentState = context.read<LeadsBloc>().state;
    final isLoaded = currentState is LeadsLoaded;

    if (!isLoaded || currentState.statuses.isEmpty) {
      context.read<LeadsBloc>().add(FetchLeadStatuses());
    }
    if (!isLoaded || currentState.sources.isEmpty) {
      context.read<LeadsBloc>().add(FetchLeadSources());
    }
    if (!isLoaded || currentState.priorities.isEmpty) {
      context.read<LeadsBloc>().add(FetchLeadPriorities());
    }
    if (!isLoaded || currentState.owners.isEmpty) {
      context.read<LeadsBloc>().add(const FetchStaffUsers());
    }
    if (!isLoaded || currentState.fixedFields.isEmpty) {
      context.read<LeadsBloc>().add(FetchCustomFieldsForm());
    }

    void updateLeadName() {
      if (widget.leadToEdit == null) {
        _leadNameController.text =
            '${_firstNameController.text} ${_lastNameController.text}'.trim();
      }
    }

    _firstNameController.addListener(updateLeadName);
    _lastNameController.addListener(updateLeadName);

    if (widget.leadToEdit != null) {
      final l = widget.leadToEdit!;
      _emailAlert = true;
      _pushNotification = true;
      _fetchLeadFollowUp(l.id);
      _firstNameController.text = l.firstName;
      _lastNameController.text = l.lastName;
      _companyController.text = l.companyName;
      _emailController.text = l.email;
      _phoneController.text = l.phone;
      _altPhoneController.text = l.alternatePhone ?? '';
      _scoreController.text = l.score != null ? l.score.toString() : '';
      _industryController.text = l.industry ?? '';
      _revenueController.text = l.annualRevenue != null
          ? l.annualRevenue.toString()
          : '';
      _employeeSizeController.text = l.employeeSize != null
          ? l.employeeSize.toString()
          : '';
      _websiteController.text = l.website ?? '';
      _countryController.text = l.country ?? '';
      _stateController.text = l.state ?? '';
      _cityController.text = l.city ?? '';
      _postalController.text = l.postalCode ?? '';
      _addressController.text = l.address ?? '';
      _descriptionController.text = l.description ?? '';

      _selectedSource = (l.source?.id != null && l.source!.id.isNotEmpty)
          ? l.source!.id
          : (l.source?.name);
      _selectedStatus = (l.status?.id != null && l.status!.id.isNotEmpty)
          ? l.status!.id
          : (l.status?.statusName);
      _selectedPriority = l.priority;
      _selectedOwner = (l.ownerUserId != null && l.ownerUserId!.isNotEmpty)
          ? l.ownerUserId
          : (l.ownerUserName != null && l.ownerUserName!.isNotEmpty
                ? l.ownerUserName
                : null);

      _leadNameController.text = '${l.firstName} ${l.lastName}'.trim();

      for (var cf in l.customFields) {
        _customFieldValues[cf.fieldId.toString()] = cf.value;
        _customFieldValues[cf.fieldId] = cf.value;
      }
    }
  }

  Future<void> _fetchLeadFollowUp(String leadId) async {
    try {
      final repo = sl<FollowUpsRepository>();
      final res = await repo.getLeadFollowUps(leadId);
      res.fold((_) {}, (data) {
        if (!mounted || data.followups.isEmpty) return;
        final f = data.followups.first;
        setState(() {
          if (_reminderDateController.text.isEmpty &&
              f.followUpDate.isNotEmpty) {
            _reminderDateController.text = _formatDateForDisplay(
              f.followUpDate,
            );
          }
          if (_reminderTimeController.text.isEmpty &&
              f.followUpTime.isNotEmpty) {
            _reminderTimeController.text = f.followUpTime;
          }
          if (_agendaController.text.isEmpty && f.leadTask.isNotEmpty) {
            _agendaController.text = f.leadTask;
          }
          final rem = f.reminder.toLowerCase();
          if (rem.isNotEmpty && rem != 'none') {
            _emailAlert = rem.contains('email');
            _pushNotification = rem.contains('push');
            if (!_emailAlert && !_pushNotification) {
              _emailAlert = true;
              _pushNotification = true;
            }
          }
        });
      });
    } catch (_) {}
  }

  String _formatDateForDisplay(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final parsed = DateTime.parse(dateStr);
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  void dispose() {
    for (var c in _customFieldControllers.values) {
      c.dispose();
    }
    _pageController.dispose();
    _stepScrollController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _jobTitleController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _scoreController.dispose();
    _industryController.dispose();
    _revenueController.dispose();
    _employeeSizeController.dispose();
    _websiteController.dispose();
    _countryController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _postalController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _leadNameController.dispose();
    _reminderDateController.dispose();
    _reminderTimeController.dispose();
    _reminderIntervalController.dispose();
    _repeatCycleController.dispose();
    _assignedAgentController.dispose();
    _agendaController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  TextEditingController _getCustomController(
    dynamic fieldId, {
    String defaultText = '',
  }) {
    final key = fieldId.toString();
    if (!_customFieldControllers.containsKey(key)) {
      final initialText = _customFieldValues[fieldId] != null
          ? _customFieldValues[fieldId].toString()
          : defaultText;
      final c = TextEditingController(text: initialText);
      c.addListener(() {
        _customFieldValues[fieldId] = c.text;
      });
      _customFieldControllers[key] = c;
    }
    return _customFieldControllers[key]!;
  }

  void _nextPage() {
    if (_currentPage == 0 && !validateAndScrollToError(_step1FormKey)) {
      setState(() {
        _step1AutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }
    if (_currentPage == 1 &&
        _step2FormKey.currentState != null &&
        !_step2FormKey.currentState!.validate()) {
      setState(() {
        _step2AutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }
    if (_currentPage == 2 &&
        _step3FormKey.currentState != null &&
        !_step3FormKey.currentState!.validate()) {
      setState(() {
        _step3AutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }
    if (_currentPage == 3 &&
        _step4FormKey.currentState != null &&
        !_step4FormKey.currentState!.validate()) {
      setState(() {
        _step4AutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }

    const lastPageIndex = 3;
    if (_currentPage < lastPageIndex) {
      final nextPage = _currentPage + 1;
      setState(() {
        _visitedPages.add(nextPage);
      });
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      if (widget.leadToEdit != null) {
        _onSaveLead();
      } else {
        setState(() {
          _hasCompletedOptionalSteps = true;
          _visitedPages.add(0);
        });
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _previousPage() {
    if (_isFollowUpOnlyFlow) {
      Navigator.pop(context);
      return;
    }
    if (_currentPage > 0) {
      final prevPage = _currentPage - 1;
      setState(() {
        _visitedPages.add(prevPage);
      });
      _pageController.animateToPage(
        prevPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _onSaveLead() {
    bool isStep1Valid = _isFollowUpOnlyFlow
        ? true
        : validateAndScrollToError(_step1FormKey);
    bool isStep2Valid = _isFollowUpOnlyFlow
        ? true
        : (_step2FormKey.currentState == null ||
              _step2FormKey.currentState!.validate());
    bool isStep3Valid = _isFollowUpOnlyFlow
        ? true
        : (_step3FormKey.currentState == null ||
              _step3FormKey.currentState!.validate());
    bool isStep4Valid =
        _step4FormKey.currentState == null ||
        _step4FormKey.currentState!.validate();

    if (!isStep1Valid || !isStep2Valid || !isStep3Valid || !isStep4Valid) {
      setState(() {
        if (!isStep1Valid)
          _step1AutovalidateMode = AutovalidateMode.onUserInteraction;
        if (!isStep2Valid)
          _step2AutovalidateMode = AutovalidateMode.onUserInteraction;
        if (!isStep3Valid)
          _step3AutovalidateMode = AutovalidateMode.onUserInteraction;
        if (!isStep4Valid)
          _step4AutovalidateMode = AutovalidateMode.onUserInteraction;
      });
    }

    if (!isStep1Valid) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields in Step 1'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!isStep2Valid) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields in Step 2'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!isStep3Valid) {
      _pageController.animateToPage(
        2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete Step 3 (Status)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!isStep4Valid) {
      _pageController.animateToPage(
        3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields in Step 4'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final leadData = <String, dynamic>{
      'firstName': _firstNameController.text,
      'lastName': _lastNameController.text,
      'companyName': _companyController.text,
      'jobTitle': _jobTitleController.text,
      'email': _emailController.text,
      'phone': _phoneController.text,
      'alternatePhone': _altPhoneController.text,
      'sourceId': _selectedSource,
      'statusId': _selectedStatus,
      'score': int.tryParse(_scoreController.text) ?? 0,
      'priority': _selectedPriority,
      'industry': _industryController.text,
      'annualRevenue': double.tryParse(_revenueController.text) ?? 0.0,
      'employeeSize': int.tryParse(_employeeSizeController.text) ?? 0,
      'website': _websiteController.text,
      'country': _countryController.text,
      'state': _stateController.text,
      'city': _cityController.text,
      'postalCode': _postalController.text,
      'address': _addressController.text,
      'description': _descriptionController.text,
      'ownerUserId': _selectedOwner,
      'notes': _notesController.text,
    };

    final reminderDateStr = _formatDateForApi(_reminderDateController.text);
    final hasReminderDate = reminderDateStr.isNotEmpty;
    leadData['enableReminder'] = hasReminderDate && (_emailAlert || _pushNotification || _smsAlert);
    if (hasReminderDate) {
      leadData['reminderDate'] = reminderDateStr;
      leadData['reminderTime'] = _formatTimeForApi(_reminderTimeController.text);
      leadData['repeat'] = _mapRepeatCycle(_repeatCycleController.text);
      leadData['notifyEmail'] = _emailAlert;
      leadData['notifySMS'] = _smsAlert;
      leadData['notifyPush'] = _pushNotification;
    } else {
      leadData['reminderDate'] = null;
      leadData['reminderTime'] = null;
    }

    leadData.removeWhere((key, value) => value == null);

    final customFieldsList = <Map<String, dynamic>>[];
    final filePaths = <String>[];

    // 1. Add general follow-up attached files
    for (var file in _followUpFiles) {
      if (file.path != null) {
        filePaths.add(file.path!);
      }
    }

    // 2. Process custom field values
    _customFieldValues.forEach((fieldId, value) {
      if (value is List<fp.PlatformFile>) {
        for (var file in value) {
          customFieldsList.add({'fieldId': fieldId, 'value': file.name});
          if (file.path != null) {
            filePaths.add(file.path!);
          }
        }
      } else if (value is fp.PlatformFile) {
        customFieldsList.add({'fieldId': fieldId, 'value': value.name});
        if (value.path != null) {
          filePaths.add(value.path!);
        }
      } else if (value != null && value.toString().isNotEmpty) {
        customFieldsList.add({'fieldId': fieldId, 'value': value});
      }
    });

    if (customFieldsList.isNotEmpty) {
      leadData['customFields'] = customFieldsList;
    }

    if (widget.leadToEdit != null) {
      context.read<LeadsBloc>().add(
        UpdateLead(
          leadId: widget.leadToEdit!.id,
          leadData: leadData,
          filePaths: filePaths,
        ),
      );
    } else {
      context.read<LeadsBloc>().add(CreateLead(leadData, filePaths: filePaths));
    }
  }

  String _formatDateForApi(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final parts = dateStr.replaceAll(',', '').split(' ');
      if (parts.length == 3) {
        final monthStr = parts[0];
        final dayStr = parts[1].padLeft(2, '0');
        final yearStr = parts[2];
        const months = {
          'Jan': '01',
          'Feb': '02',
          'Mar': '03',
          'Apr': '04',
          'May': '05',
          'Jun': '06',
          'Jul': '07',
          'Aug': '08',
          'Sep': '09',
          'Oct': '10',
          'Nov': '11',
          'Dec': '12',
        };
        final month = months[monthStr] ?? '01';
        return '$yearStr-$month-$dayStr';
      }
    } catch (_) {}
    return dateStr;
  }

  String _formatTimeForApi(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(' ');
      if (parts.length == 2) {
        final timeParts = parts[0].split(':');
        int hours = int.parse(timeParts[0]);
        final minutes = timeParts[1];
        if (parts[1].toUpperCase() == 'PM' && hours < 12) hours += 12;
        if (parts[1].toUpperCase() == 'AM' && hours == 12) hours = 0;
        return '${hours.toString().padLeft(2, '0')}:$minutes';
      }
    } catch (_) {}
    return timeStr;
  }

  String _mapRepeatCycle(String repeat) {
    final lower = repeat.toLowerCase();
    if (lower.contains('daily')) return 'DAILY';
    if (lower.contains('weekly')) return 'WEEKLY';
    if (lower.contains('monthly')) return 'MONTHLY';
    return 'NONE';
  }

  String _getAppBarTitle() {
    if (_isSingleFieldEdit) {
      return 'Edit ${_getFieldDisplayName(widget.targetFieldKey!)}';
    }
    switch (_currentPage) {
      case 0:
        return widget.leadToEdit != null ? 'Edit Lead' : 'New Lead';
      case 1:
        return 'Custom Fields';
      case 2:
        return 'Lead Status';
      case 3:
        return 'Follow-up';
      default:
        return widget.leadToEdit != null ? 'Edit Lead' : 'New Lead';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LeadsBloc, LeadsState>(
      listener: (context, state) {
        if (state is LeadActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        } else if (state is LeadActionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.primary),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          backgroundColor: AppColors.secondary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: _previousPage,
          ),
          title: Text(
            _getAppBarTitle(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!_isSingleFieldEdit && !_isFollowUpOnlyFlow)
                _buildStepProgressHeader(),
              if (_isSingleFieldEdit)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: AppColors.primary.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editing only "${_getFieldDisplayName(widget.targetFieldKey!)}". Other fields are locked.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: BlocBuilder<LeadsBloc, LeadsState>(
                  buildWhen: (prev, current) {
                    if (current is! LeadsLoaded) return false;
                    if (prev is! LeadsLoaded) return true;
                    return prev.statuses != current.statuses ||
                        prev.sources != current.sources ||
                        prev.priorities != current.priorities ||
                        prev.owners != current.owners ||
                        prev.customFields != current.customFields ||
                        prev.fixedFields != current.fixedFields;
                  },
                  builder: (context, state) {
                    return PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) => setState(() {
                        _currentPage = index;
                        _visitedPages.add(index);
                        if (_stepScrollController.hasClients) {
                          _stepScrollController.animateTo(
                            (index * 95.0).clamp(
                              0.0,
                              _stepScrollController.position.maxScrollExtent,
                            ),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          );
                        }
                      }),
                      children: [
                        _visitedPages.contains(0)
                            ? KeepAliveWrapper(
                                child: _buildLeadDetailsForm(state),
                              )
                            : const SizedBox.shrink(),
                        _visitedPages.contains(1)
                            ? KeepAliveWrapper(
                                child: _buildCustomFieldsTab(state),
                              )
                            : const SizedBox.shrink(),
                        _visitedPages.contains(2)
                            ? KeepAliveWrapper(child: _buildStatusTab(state))
                            : const SizedBox.shrink(),
                        _visitedPages.contains(3)
                            ? KeepAliveWrapper(child: _buildFollowUpTab())
                            : const SizedBox.shrink(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildStepProgressHeader() {
    final steps = [
      '1. Lead Details',
      '2. Custom Fields',
      '3. Status',
      '4. Follow-Up',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: SingleChildScrollView(
        controller: _stepScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(steps.length, (index) {
            final isActive = index == _currentPage;
            final isCompleted =
                index < _currentPage || _hasCompletedOptionalSteps;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _visitedPages.add(index);
                });
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: Container(
                margin: EdgeInsets.only(
                  right: index == steps.length - 1 ? 0 : 8,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : (isCompleted
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary
                        : (isCompleted
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.borderEnabled),
                  ),
                ),
                child: Center(
                  child: Text(
                    steps[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? Colors.white
                          : (isCompleted
                                ? AppColors.primary
                                : AppColors.textHint),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderEnabled)),
      ),
      child: SafeArea(child: _getBottomButtons()),
    );
  }

  Widget _getBottomButtons() {
    if (_isSingleFieldEdit) {
      return BlocBuilder<LeadsBloc, LeadsState>(
        builder: (context, state) {
          final isLoading = state is LeadActionLoading;
          return SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : _onSaveLead,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Update ${_getFieldDisplayName(widget.targetFieldKey!)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
            ),
          );
        },
      );
    }

    if (_isFollowUpOnlyFlow) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderEnabled),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 50,
              child: BlocBuilder<LeadsBloc, LeadsState>(
                builder: (context, state) {
                  final isLoading = state is LeadActionLoading;
                  return ElevatedButton(
                    onPressed: isLoading ? null : _onSaveLead,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            widget.leadToEdit != null ? 'Update' : 'Save',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    if (_currentPage == 0) {
      if (_hasCompletedOptionalSteps) {
        return BlocBuilder<LeadsBloc, LeadsState>(
          builder: (context, state) {
            final isLoading = state is LeadActionLoading;
            return SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : _onSaveLead,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.leadToEdit != null
                                ? 'Update Lead'
                                : 'Save Lead',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      } else {
        return SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'Next',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ],
            ),
          ),
        );
      }
    } else {
      final lastPageIndex = 3;
      final isLastStep = _currentPage == lastPageIndex;
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _nextPage,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderEnabled),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  isLastStep
                      ? (widget.leadToEdit != null ? 'Update' : 'Save')
                      : 'Save & Next',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  List<StaffUser> _cachedOwners = [];
  List<LeadStatus> _cachedStatuses = [];
  List<LeadSource> _cachedSources = [];
  List<String> _cachedPriorities = [];

  Widget _buildLeadDetailsForm(LeadsState state) {
    List<DropdownMenuItem<String>> statusItems = [];
    List<DropdownMenuItem<String>> sourceItems = [];
    List<DropdownMenuItem<String>> priorityItems = [];
    List<DropdownMenuItem<String>> ownerItems = [];

    if (state is LeadsLoaded) {
      if (state.statuses.isNotEmpty) _cachedStatuses = state.statuses;
      if (state.sources.isNotEmpty) _cachedSources = state.sources;
      if (state.priorities.isNotEmpty) _cachedPriorities = state.priorities;
      if (state.owners.isNotEmpty) _cachedOwners = state.owners;
    }

    final statusesToUse = (state is LeadsLoaded && state.statuses.isNotEmpty)
        ? state.statuses
        : _cachedStatuses;
    final sourcesToUse = (state is LeadsLoaded && state.sources.isNotEmpty)
        ? state.sources
        : _cachedSources;
    final prioritiesToUse =
        (state is LeadsLoaded && state.priorities.isNotEmpty)
        ? state.priorities
        : _cachedPriorities;
    final ownersToUse = (state is LeadsLoaded && state.owners.isNotEmpty)
        ? state.owners
        : _cachedOwners;

    statusItems = statusesToUse
        .map(
          (s) => DropdownMenuItem(
            value: s.id,
            child: Text(s.statusName, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
    sourceItems = sourcesToUse
        .map(
          (s) => DropdownMenuItem(
            value: s.id,
            child: Text(s.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
    priorityItems = prioritiesToUse
        .map(
          (p) => DropdownMenuItem(
            value: p,
            child: Text(p, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
    final canAssign = sl<PrivilegeService>().canAssignLeads();
    List<StaffUser> orderedOwners;

    if (canAssign) {
      final Set<String> seenIds = {};
      orderedOwners =
          ownersToUse.where((o) {
            if (seenIds.contains(o.userId)) return false;
            seenIds.add(o.userId);
            return true;
          }).toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    } else {
      String assignedId = widget.leadToEdit?.ownerUserId?.trim() ?? '';
      String assignedName = widget.leadToEdit?.ownerUserName?.trim() ?? '';

      if (assignedId.isEmpty && assignedName.isNotEmpty) {
        final match = ownersToUse
            .where(
              (o) => o.name.trim().toLowerCase() == assignedName.toLowerCase(),
            )
            .toList();
        if (match.isNotEmpty) {
          assignedId = match.first.userId;
        } else {
          assignedId = assignedName;
        }
      }

      if (assignedName.isEmpty && assignedId.isNotEmpty) {
        final match = ownersToUse
            .where((o) => o.userId.trim() == assignedId)
            .toList();
        if (match.isNotEmpty) assignedName = match.first.name;
      }

      if (widget.leadToEdit == null) {
        if (assignedId.isEmpty) assignedId = _currentUserId ?? '';
        if (assignedName.isEmpty) {
          assignedName = sl.isRegistered<SharedPreferences>()
              ? (sl<SharedPreferences>().getString('userName') ??
                    'Assigned Staff')
              : 'Assigned Staff';
        }
      }

      if (assignedId.isEmpty)
        assignedId = assignedName.isNotEmpty ? assignedName : 'unassigned';
      if (assignedName.isEmpty) assignedName = 'Unassigned';

      _selectedOwner = assignedId;
      orderedOwners = [StaffUser(userId: assignedId, name: assignedName)];
    }

    ownerItems = orderedOwners
        .map(
          (o) => DropdownMenuItem(
            value: o.userId,
            child: Text(o.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();

    // --- STATUS MATCHING ---
    if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
      bool hasMatch = statusItems.any((item) => item.value == _selectedStatus);
      if (!hasMatch) {
        final targetLower = _selectedStatus!.trim().toLowerCase();
        LeadStatus? matchStatus;
        try {
          matchStatus = statusesToUse.firstWhere(
            (s) =>
                s.id.trim().toLowerCase() == targetLower ||
                s.statusName.trim().toLowerCase() == targetLower,
          );
        } catch (_) {}
        if (matchStatus != null && matchStatus.id.isNotEmpty) {
          _selectedStatus = matchStatus.id;
          hasMatch = true;
        }
      }
      if (!hasMatch) {
        final editStatus = widget.leadToEdit?.status;
        final val = (editStatus != null && editStatus.id.isNotEmpty)
            ? editStatus.id
            : _selectedStatus!;
        final name = (editStatus != null && editStatus.statusName.isNotEmpty)
            ? editStatus.statusName
            : _selectedStatus!;
        _selectedStatus = val;
        if (!statusItems.any((item) => item.value == val)) {
          statusItems.insert(
            0,
            DropdownMenuItem(
              value: val,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          );
        }
      }
    } else if (statusesToUse.isNotEmpty) {
      try {
        _selectedStatus = statusesToUse
            .firstWhere((s) => s.isDefault == true)
            .id;
      } catch (_) {
        _selectedStatus = statusesToUse.first.id;
      }
    }

    // --- SOURCE MATCHING ---
    if (_selectedSource != null && _selectedSource!.isNotEmpty) {
      bool hasMatch = sourceItems.any((item) => item.value == _selectedSource);
      if (!hasMatch) {
        final targetLower = _selectedSource!.trim().toLowerCase();
        LeadSource? matchSource;
        try {
          matchSource = sourcesToUse.firstWhere(
            (s) =>
                s.id.trim().toLowerCase() == targetLower ||
                s.name.trim().toLowerCase() == targetLower,
          );
        } catch (_) {}
        if (matchSource != null && matchSource.id.isNotEmpty) {
          _selectedSource = matchSource.id;
          hasMatch = true;
        }
      }
      if (!hasMatch) {
        final editSource = widget.leadToEdit?.source;
        final val = (editSource != null && editSource.id.isNotEmpty)
            ? editSource.id
            : _selectedSource!;
        final name = (editSource != null && editSource.name.isNotEmpty)
            ? editSource.name
            : _selectedSource!;
        _selectedSource = val;
        if (!sourceItems.any((item) => item.value == val)) {
          sourceItems.insert(
            0,
            DropdownMenuItem(
              value: val,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          );
        }
      }
    } else if (sourcesToUse.isNotEmpty) {
      _selectedSource = sourcesToUse.first.id;
    }

    // --- PRIORITY MATCHING ---
    if (_selectedPriority != null && _selectedPriority!.isNotEmpty) {
      bool hasMatch = priorityItems.any(
        (item) => item.value == _selectedPriority,
      );
      if (!hasMatch) {
        final targetLower = _selectedPriority!.trim().toLowerCase();
        String? matchPriority;
        try {
          matchPriority = prioritiesToUse.firstWhere(
            (p) => p.trim().toLowerCase() == targetLower,
          );
        } catch (_) {}
        if (matchPriority != null && matchPriority.isNotEmpty) {
          _selectedPriority = matchPriority;
          hasMatch = true;
        }
      }
      if (!hasMatch &&
          _selectedPriority != null &&
          _selectedPriority!.isNotEmpty) {
        if (!priorityItems.any((item) => item.value == _selectedPriority)) {
          priorityItems.insert(
            0,
            DropdownMenuItem(
              value: _selectedPriority!,
              child: Text(_selectedPriority!, overflow: TextOverflow.ellipsis),
            ),
          );
        }
      }
    } else if (prioritiesToUse.isNotEmpty) {
      _selectedPriority = prioritiesToUse.first;
    }

    // --- OWNER MATCHING ---
    if (_selectedOwner != null && _selectedOwner!.isNotEmpty) {
      bool hasMatch = ownerItems.any((item) => item.value == _selectedOwner);
      if (!hasMatch) {
        final targetLower = _selectedOwner!.trim().toLowerCase();
        StaffUser? matchOwner;
        try {
          matchOwner = ownersToUse.firstWhere(
            (o) =>
                o.userId.trim().toLowerCase() == targetLower ||
                o.name.trim().toLowerCase() == targetLower,
          );
        } catch (_) {}
        if (matchOwner != null && matchOwner.userId.isNotEmpty) {
          _selectedOwner = matchOwner.userId;
          hasMatch = true;
        }
      }
      if (!hasMatch) {
        final name =
            (widget.leadToEdit?.ownerUserName != null &&
                widget.leadToEdit!.ownerUserName!.isNotEmpty)
            ? widget.leadToEdit!.ownerUserName!
            : _selectedOwner!;
        if (!ownerItems.any((item) => item.value == _selectedOwner)) {
          ownerItems.insert(
            0,
            DropdownMenuItem(
              value: _selectedOwner!,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          );
        }
      }
    } else if (orderedOwners.isNotEmpty && canAssign) {
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        final loggedInStaff = orderedOwners
            .where((o) => o.userId == _currentUserId)
            .toList();
        if (loggedInStaff.isNotEmpty) {
          _selectedOwner = loggedInStaff.first.userId;
        } else {
          _selectedOwner = orderedOwners.first.userId;
        }
      } else {
        _selectedOwner = orderedOwners.first.userId;
      }
    }

    Widget? buildFixedWidget(FixedField ff) {
      final k = ff.fieldName.trim().toLowerCase();
      final label = ff.fieldLabel.trim().isNotEmpty
          ? ff.fieldLabel.trim()
          : ff.fieldName;
      final isEditable = _isFieldEditable(k);
      final req = ff.isRequired && isEditable;

      if (k == 'firstname' || k == 'first_name') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _firstNameController,
          inputFormatters: AppInputFormatters.nameFormatters,
          validator: (val) =>
              (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'lastname' || k == 'last_name') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _lastNameController,
          inputFormatters: AppInputFormatters.nameFormatters,
          validator: (val) =>
              (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'companyname' || k == 'company_name' || k == 'company') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _companyController,
          validator: (val) =>
              (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'jobtitle' || k == 'job_title' || k == 'designation') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _jobTitleController,
          validator: (val) =>
              (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'email') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.emailAddress,
          controller: _emailController,
          validator: (val) => isEditable
              ? AppValidators.validateEmail(val, isRequired: ff.isRequired)
              : null,
        );
      } else if (k == 'phone' || k == 'mobile') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.phone,
          controller: _phoneController,
          inputFormatters: AppInputFormatters.phoneFormatters,
          validator: (val) => isEditable
              ? AppValidators.validateMobile(val, isRequired: ff.isRequired)
              : null,
        );
      } else if (k == 'alternatephone' ||
          k == 'alternate_phone' ||
          k == 'alt_phone') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.phone,
          controller: _altPhoneController,
          inputFormatters: AppInputFormatters.phoneFormatters,
          validator: (val) {
            if (isEditable &&
                (ff.isRequired || (val != null && val.isNotEmpty))) {
              return AppValidators.validateMobile(
                val,
                isRequired: ff.isRequired,
              );
            }
            return null;
          },
        );
      } else if (k == 'sourceid' || k == 'source' || k == 'lead_source') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          enabled: isEditable,
          items: sourceItems,
          value: _selectedSource,
          onChanged: (val) => setState(() => _selectedSource = val),
          validator: (val) =>
              (req && (val == null || val.isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'statusid' || k == 'status' || k == 'lead_status') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          enabled: isEditable,
          items: statusItems,
          value: _selectedStatus,
          onChanged: (val) => setState(() => _selectedStatus = val),
          validator: (val) =>
              (req && (val == null || val.isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'score' || k == 'lead_score') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.number,
          controller: _scoreController,
          validator: (val) =>
              (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'priority' || k == 'lead_priority') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          enabled: isEditable,
          items: priorityItems,
          value: _selectedPriority,
          onChanged: (val) => setState(() => _selectedPriority = val),
        );
      } else if (k == 'industry') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _industryController,
          validator: (val) =>
              (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'annualrevenue' ||
          k == 'annual_revenue' ||
          k == 'revenue') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.number,
          controller: _revenueController,
        );
      } else if (k == 'employeesize' ||
          k == 'employee_size' ||
          k == 'no_of_employees') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.number,
          controller: _employeeSizeController,
        );
      } else if (k == 'website' || k == 'url') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          keyboardType: TextInputType.url,
          controller: _websiteController,
        );
      } else if (k == 'country') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _countryController,
        );
      } else if (k == 'state') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _stateController,
        );
      } else if (k == 'city') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _cityController,
        );
      } else if (k == 'postalcode' ||
          k == 'postal_code' ||
          k == 'zip' ||
          k == 'pincode') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          controller: _postalController,
        );
      } else if (k == 'address') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          maxLines: 3,
          controller: _addressController,
        );
      } else if (k == 'description' || k == 'notes') {
        return CustomTextField(
          label: label,
          isRequired: req,
          enabled: isEditable,
          maxLines: 3,
          controller: _descriptionController,
        );
      } else if (k == 'owneruserid' ||
          k == 'owner' ||
          k == 'assign_to' ||
          k == 'owner_user_id') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          enabled: isEditable && canAssign,
          items: ownerItems,
          value: _selectedOwner,
          onChanged: canAssign
              ? (val) => setState(() => _selectedOwner = val)
              : null,
        );
      }
      return null;
    }

    final List<FixedField> fieldsToShow =
        (state is LeadsLoaded && state.fixedFields.isNotEmpty)
        ? state.fixedFields
        : const [
            FixedField(
              fieldName: 'firstName',
              fieldLabel: 'First Name',
              fieldType: 'TEXT',
              isRequired: true,
              displayOrder: 1,
            ),
            FixedField(
              fieldName: 'lastName',
              fieldLabel: 'Last Name',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 2,
            ),
            FixedField(
              fieldName: 'companyName',
              fieldLabel: 'Company Name',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 3,
            ),
            FixedField(
              fieldName: 'email',
              fieldLabel: 'Email',
              fieldType: 'EMAIL',
              isRequired: true,
              displayOrder: 4,
            ),
            FixedField(
              fieldName: 'phone',
              fieldLabel: 'Phone',
              fieldType: 'PHONE',
              isRequired: true,
              displayOrder: 5,
            ),
            FixedField(
              fieldName: 'alternatePhone',
              fieldLabel: 'Alternate Phone',
              fieldType: 'PHONE',
              isRequired: false,
              displayOrder: 6,
            ),
            FixedField(
              fieldName: 'sourceId',
              fieldLabel: 'Lead Source',
              fieldType: 'DROPDOWN',
              isRequired: true,
              displayOrder: 7,
            ),
            FixedField(
              fieldName: 'statusId',
              fieldLabel: 'Lead Status',
              fieldType: 'DROPDOWN',
              isRequired: true,
              displayOrder: 8,
            ),
            FixedField(
              fieldName: 'score',
              fieldLabel: 'Score',
              fieldType: 'NUMBER',
              isRequired: false,
              displayOrder: 9,
            ),
            FixedField(
              fieldName: 'priority',
              fieldLabel: 'Priority',
              fieldType: 'DROPDOWN',
              isRequired: false,
              displayOrder: 10,
            ),
            FixedField(
              fieldName: 'industry',
              fieldLabel: 'Industry',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 11,
            ),
            FixedField(
              fieldName: 'website',
              fieldLabel: 'Website',
              fieldType: 'URL',
              isRequired: false,
              displayOrder: 12,
            ),
            FixedField(
              fieldName: 'country',
              fieldLabel: 'Country',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 13,
            ),
            FixedField(
              fieldName: 'state',
              fieldLabel: 'State',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 14,
            ),
            FixedField(
              fieldName: 'city',
              fieldLabel: 'City',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 15,
            ),
            FixedField(
              fieldName: 'postalCode',
              fieldLabel: 'Postal Code',
              fieldType: 'TEXT',
              isRequired: false,
              displayOrder: 16,
            ),
            FixedField(
              fieldName: 'address',
              fieldLabel: 'Address',
              fieldType: 'TEXTAREA',
              isRequired: false,
              displayOrder: 17,
            ),
            FixedField(
              fieldName: 'description',
              fieldLabel: 'Description',
              fieldType: 'TEXTAREA',
              isRequired: false,
              displayOrder: 18,
            ),
            FixedField(
              fieldName: 'ownerUserId',
              fieldLabel: 'Assigned To',
              fieldType: 'DROPDOWN',
              isRequired: false,
              displayOrder: 19,
            ),
          ];

    final List<Widget> widgets = [];
    for (var ff in fieldsToShow) {
      final w = buildFixedWidget(ff);
      if (w != null) widgets.add(w);
    }

    final List<Widget> formRows = [];
    for (int i = 0; i < widgets.length; i += 2) {
      if (i + 1 < widgets.length) {
        formRows.add(_buildRow(widgets[i], widgets[i + 1]));
      } else {
        formRows.add(_buildRow(widgets[i], const SizedBox()));
      }
      formRows.add(const SizedBox(height: 16));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step1FormKey,
        autovalidateMode: _step1AutovalidateMode,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Basic Information & Lead Details'),
            const SizedBox(height: 16),
            ...formRows,
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReminderDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      setState(() {
        _reminderDateController.text =
            '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      });
    }
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      setState(() {
        _reminderTimeController.text =
            '${hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $period';
      });
    }
  }

  Future<void> _pickFollowUpFiles() async {
    try {
      final result = await fp.FilePicker.pickFiles(
        allowMultiple: true,
        type: fp.FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _followUpFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick file: $e')));
      }
    }
  }

  Future<void> _pickFollowUpFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo != null && photo.path.isNotEmpty) {
        final file = File(photo.path);
        final size = await file.length();
        final platformFile = fp.PlatformFile(
          name: photo.name,
          path: photo.path,
          size: size,
        );
        setState(() {
          _followUpFiles.add(platformFile);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to capture photo: $e')));
      }
    }
  }

  Future<void> _pickCustomFieldFromCamera(
    dynamic field,
    int maxFiles,
    List<fp.PlatformFile> pickedFiles,
  ) async {
    if (pickedFiles.length >= maxFiles) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Maximum $maxFiles files allowed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (photo != null && photo.path.isNotEmpty) {
        final file = File(photo.path);
        final size = await file.length();
        final platformFile = fp.PlatformFile(
          name: photo.name,
          path: photo.path,
          size: size,
        );
        setState(() {
          final currentFiles = List<fp.PlatformFile>.from(pickedFiles);
          currentFiles.add(platformFile);
          _customFieldValues[field.fieldId] = currentFiles
              .take(maxFiles)
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to capture photo: $e')));
      }
    }
  }

  Future<void> _pickCustomFieldFiles(
    dynamic field,
    int maxFiles,
    List<fp.PlatformFile> pickedFiles,
  ) async {
    if (pickedFiles.length >= maxFiles) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Maximum $maxFiles files allowed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      final result = await fp.FilePicker.pickFiles(
        allowMultiple: true,
        type: fp.FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          final currentFiles = List<fp.PlatformFile>.from(pickedFiles);
          currentFiles.addAll(result.files);
          _customFieldValues[field.fieldId] = currentFiles
              .take(maxFiles)
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick file: $e')));
      }
    }
  }

  Widget _buildFollowUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step4FormKey,
        autovalidateMode: _step4AutovalidateMode,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Follow-Up Schedule'),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Lead Name',
              controller: _leadNameController,
            ),
            const SizedBox(height: 16),
            _buildRow(
              _buildIconTextField(
                'Date',
                Icons.calendar_today_outlined,
                _reminderDateController,
                onTap: _pickReminderDate,
              ),
              _buildIconTextField(
                'Time',
                Icons.access_time,
                _reminderTimeController,
                onTap: _pickReminderTime,
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Notification Channel',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.textLabel,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildCheckbox(
                  'Email',
                  _emailAlert,
                  (v) => setState(() => _emailAlert = v!),
                ),
                const SizedBox(width: 16),
                _buildCheckbox(
                  'Push notification',
                  _pushNotification,
                  (v) => setState(() => _pushNotification = v!),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Notes & Attachments'),
            const SizedBox(height: 16),
            const Text(
              'Add Note',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderEnabled),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write internal activity report here...',
                  hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Files & Attachments',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickFollowUpFiles,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        children: const [
                          Icon(
                            Icons.file_upload_outlined,
                            color: AppColors.primary,
                            size: 30,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Tap to upload files',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'PDF, PNG, JPG, or DOC (Max 10MB)',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _pickFollowUpFromCamera,
                  child: Container(
                    width: 76,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.camera_alt_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Camera',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Snap',
                          style: TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_followUpFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._followUpFiles.asMap().entries.map((entry) {
                final index = entry.key;
                final file = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderEnabled),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${(file.size / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _followUpFiles.removeAt(index)),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTab(LeadsState state) {
    final List<LeadStatus> statusesToUse =
        (state is LeadsLoaded && state.statuses.isNotEmpty)
        ? state.statuses
        : _cachedStatuses;

    final statusItems = statusesToUse.map((s) {
      Color? color;
      if (s.color.isNotEmpty) {
        final hex = s.color.replaceAll('#', '');
        if (hex.length == 6) {
          final parsed = int.tryParse('0xFF$hex');
          if (parsed != null) color = Color(parsed);
        }
      }
      return DropdownMenuItem<String>(
        value: s.id,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color ?? AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.statusName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }).toList();

    if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
      bool hasMatch = statusItems.any((item) => item.value == _selectedStatus);
      if (!hasMatch) {
        final targetLower = _selectedStatus!.trim().toLowerCase();
        LeadStatus? matchStatus;
        try {
          matchStatus = statusesToUse.firstWhere(
            (s) =>
                s.id.trim().toLowerCase() == targetLower ||
                s.statusName.trim().toLowerCase() == targetLower,
          );
        } catch (_) {}
        if (matchStatus != null && matchStatus.id.isNotEmpty) {
          _selectedStatus = matchStatus.id;
          hasMatch = true;
        }
      }
      if (!hasMatch) {
        final editStatus = widget.leadToEdit?.status;
        final val = (editStatus != null && editStatus.id.isNotEmpty)
            ? editStatus.id
            : _selectedStatus!;
        final name = (editStatus != null && editStatus.statusName.isNotEmpty)
            ? editStatus.statusName
            : _selectedStatus!;
        _selectedStatus = val;
        if (!statusItems.any((item) => item.value == val)) {
          statusItems.insert(
            0,
            DropdownMenuItem(
              value: val,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
          );
        }
      }
    } else if (statusesToUse.isNotEmpty) {
      try {
        _selectedStatus = statusesToUse
            .firstWhere((s) => s.isDefault == true)
            .id;
      } catch (_) {
        _selectedStatus = statusesToUse.first.id;
      }
    }

    LeadStatus? currentStatus;
    try {
      currentStatus = statusesToUse.firstWhere((s) => s.id == _selectedStatus);
    } catch (_) {}

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step3FormKey,
        autovalidateMode: _step3AutovalidateMode,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Lead Status'),
            const SizedBox(height: 8),
            const Text(
              'Select the current pipeline status for this lead.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            CustomDropdownField<String>(
              label: 'Lead Status',
              isRequired: true,
              items: statusItems,
              value: _selectedStatus,
              onChanged: (val) => setState(() => _selectedStatus = val),
              validator: (val) => (val == null || val.isEmpty)
                  ? 'Please select a status'
                  : null,
            ),
            const SizedBox(height: 20),
            if (currentStatus != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Status',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentStatus.statusName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomFieldsTab(LeadsState state) {
    if (state is! LeadsLoaded || state.customFields.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No custom fields available.',
            style: TextStyle(color: AppColors.textHint),
          ),
        ),
      );
    }

    final fields = List.of(state.customFields)
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step2FormKey,
        autovalidateMode: _step2AutovalidateMode,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lead Custom Fields',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...fields.map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildDynamicField(field),
              );
            }),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicField(dynamic field) {
    final rawType =
        (field.type != null && field.type.toString().isNotEmpty
                ? field.type.toString()
                : (field.fieldType != null ? field.fieldType.toString() : ''))
            .toUpperCase();
    final isRequired = field.isRequired ?? false;
    final displayLabel =
        (field.fieldLabel != null &&
            field.fieldLabel.toString().trim().isNotEmpty)
        ? field.fieldLabel.toString().trim()
        : (field.label != null && field.label.toString().trim().isNotEmpty
              ? field.label.toString().trim()
              : '');
    final rawLabel = displayLabel.toLowerCase();
    final fieldIdKey = (field.fieldId ?? field.id ?? '').toString();

    if (rawType == 'DROPDOWN' || rawType == 'SELECT') {
      List<DropdownMenuItem<String>> items = [];
      List<dynamic> opts = field.options ?? [];
      for (var opt in opts) {
        if (opt != null) {
          final optStr = opt.toString();
          if (!items.any((item) => item.value == optStr)) {
            items.add(DropdownMenuItem(value: optStr, child: Text(optStr)));
          }
        }
      }
      final rawVal =
          (_customFieldValues[field.fieldId] ?? _customFieldValues[fieldIdKey])
              ?.toString();
      if (rawVal != null &&
          rawVal.isNotEmpty &&
          !items.any((item) => item.value == rawVal)) {
        final matchOpt = opts.cast<dynamic>().firstWhere(
          (o) =>
              o != null &&
              o.toString().trim().toLowerCase() == rawVal.trim().toLowerCase(),
          orElse: () => null,
        );
        if (matchOpt != null) {
          _customFieldValues[field.fieldId] = matchOpt.toString();
          _customFieldValues[fieldIdKey] = matchOpt.toString();
        } else {
          items.insert(0, DropdownMenuItem(value: rawVal, child: Text(rawVal)));
        }
      }
      return CustomDropdownField<String>(
        label: displayLabel,
        isRequired: isRequired,
        items: items,
        value:
            (_customFieldValues[field.fieldId] ??
                    _customFieldValues[fieldIdKey])
                ?.toString(),
        onChanged: (val) {
          setState(() {
            _customFieldValues[field.fieldId] = val;
            _customFieldValues[fieldIdKey] = val;
          });
        },
        validator: isRequired
            ? (val) => val == null || val.toString().isEmpty
                  ? '$displayLabel is required'
                  : null
            : null,
      );
    } else if (rawType == 'MULTI_SELECT') {
      List<dynamic> opts = field.options ?? [];
      final dynamic storedVal =
          _customFieldValues[field.fieldId] ?? _customFieldValues[fieldIdKey];
      final List<String> currentSelected = storedVal is List
          ? List<String>.from(storedVal)
          : (storedVal != null && storedVal.toString().isNotEmpty
                ? storedVal.toString().split(',').map((e) => e.trim()).toList()
                : []);

      return FormField<List<String>>(
        initialValue: currentSelected,
        validator: isRequired
            ? (val) => (val == null || val.isEmpty)
                  ? '$displayLabel is required'
                  : null
            : null,
        builder: (formFieldState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  text: displayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLabel,
                  ),
                  children: [
                    if (isRequired)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: AppColors.primary),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: opts.map((opt) {
                  final optStr = opt.toString();
                  final isSel = currentSelected.contains(optStr);
                  return FilterChip(
                    label: Text(optStr),
                    selected: isSel,
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.primary,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          currentSelected.add(optStr);
                        } else {
                          currentSelected.remove(optStr);
                        }
                        _customFieldValues[field.fieldId] = List<String>.from(
                          currentSelected,
                        );
                        formFieldState.didChange(
                          List<String>.from(currentSelected),
                        );
                      });
                    },
                  );
                }).toList(),
              ),
              if (formFieldState.hasError) ...[
                const SizedBox(height: 4),
                Text(
                  formFieldState.errorText!,
                  style: const TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              ],
            ],
          );
        },
      );
    } else if (rawType == 'RADIO') {
      List<dynamic> opts = field.options ?? [];
      return FormField<String>(
        initialValue: _customFieldValues[field.fieldId]?.toString(),
        validator: isRequired
            ? (val) => (val == null || val.trim().isEmpty)
                  ? '$displayLabel is required'
                  : null
            : null,
        builder: (formFieldState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  text: displayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLabel,
                  ),
                  children: [
                    if (isRequired)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: AppColors.primary),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              ...opts.map((opt) {
                final optStr = opt.toString();
                return RadioListTile<String>(
                  title: Text(optStr, style: const TextStyle(fontSize: 14)),
                  value: optStr,
                  groupValue: _customFieldValues[field.fieldId]?.toString(),
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _customFieldValues[field.fieldId] = val;
                      formFieldState.didChange(val);
                    });
                  },
                );
              }),
              if (formFieldState.hasError) ...[
                const SizedBox(height: 4),
                Text(
                  formFieldState.errorText!,
                  style: const TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              ],
            ],
          );
        },
      );
    } else if (rawType == 'DATE') {
      final controller = _getCustomController(field.fieldId);
      return InkWell(
        onTap: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setState(() {
              final dateString =
                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              _customFieldValues[field.fieldId] = dateString;
              controller.text = dateString;
            });
          }
        },
        child: IgnorePointer(
          child: CustomTextField(
            label: displayLabel,
            isRequired: isRequired,
            controller: controller,
            suffixIcon: const Icon(
              Icons.calendar_today,
              size: 18,
              color: AppColors.textHint,
            ),
            validator: isRequired
                ? (val) => val == null || val.isEmpty
                      ? '$displayLabel is required'
                      : null
                : null,
          ),
        ),
      );
    } else if (rawType == 'DATE_TIME' || rawType == 'DATETIME') {
      final controller = _getCustomController(field.fieldId);
      return InkWell(
        onTap: () async {
          final DateTime? pickedDate = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (pickedDate != null && context.mounted) {
            final TimeOfDay? pickedTime = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (pickedTime != null) {
              setState(() {
                final dateStr =
                    '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
                final timeStr =
                    '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                final fullStr = '$dateStr $timeStr';
                _customFieldValues[field.fieldId] = fullStr;
                controller.text = fullStr;
              });
            }
          }
        },
        child: IgnorePointer(
          child: CustomTextField(
            label: displayLabel,
            isRequired: isRequired,
            controller: controller,
            suffixIcon: const Icon(
              Icons.access_time,
              size: 18,
              color: AppColors.textHint,
            ),
            validator: isRequired
                ? (val) => val == null || val.isEmpty
                      ? '$displayLabel is required'
                      : null
                : null,
          ),
        ),
      );
    } else if (rawType == 'ATTACHMENT' ||
        rawType == 'FILE' ||
        rawType == 'DOCUMENT' ||
        field.attachmentType != null) {
      final rawVal = _customFieldValues[field.fieldId];
      final List<fp.PlatformFile> pickedFiles = rawVal is List<fp.PlatformFile>
          ? rawVal
          : (rawVal is List<dynamic>
                ? rawVal.whereType<fp.PlatformFile>().toList()
                : <fp.PlatformFile>[]);
      final String? existingFileStr = (rawVal is String && rawVal.isNotEmpty)
          ? rawVal
          : null;
      final int maxFiles = (field.maxLength is int
          ? field.maxLength as int
          : 5);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                displayLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textLabel,
                ),
              ),
              if (isRequired)
                const Text(
                  ' *',
                  style: TextStyle(color: AppColors.primary, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () =>
                      _pickCustomFieldFiles(field, maxFiles, pickedFiles),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          color: AppColors.primary,
                          size: 30,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap to upload files (${pickedFiles.length}/$maxFiles)',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'PDF, PNG, JPG, or DOC',
                          style: TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () =>
                    _pickCustomFieldFromCamera(field, maxFiles, pickedFiles),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 76,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.camera_alt_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Camera',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Snap',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (existingFileStr != null && pickedFiles.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderEnabled),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current file: $existingFileStr',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (pickedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...pickedFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(file.size / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          final updatedFiles = List<fp.PlatformFile>.from(
                            pickedFiles,
                          );
                          updatedFiles.removeAt(index);
                          _customFieldValues[field.fieldId] = updatedFiles;
                        });
                      },
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      );
    } else if (rawType == 'EMAIL' ||
        rawLabel.contains('email') ||
        rawLabel.contains('mail')) {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        keyboardType: TextInputType.emailAddress,
        controller: controller,
        validator: (val) =>
            AppValidators.validateEmail(val, isRequired: isRequired),
      );
    } else if (rawType == 'PHONE' ||
        rawType == 'MOBILE' ||
        rawLabel.contains('phone') ||
        rawLabel.contains('mobile') ||
        rawLabel.contains('contact') ||
        rawLabel.contains('tel') ||
        rawLabel.contains('cell') ||
        rawLabel.contains('whatsapp')) {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        keyboardType: TextInputType.phone,
        controller: controller,
        inputFormatters: AppInputFormatters.phoneFormatters,
        validator: (val) =>
            AppValidators.validateMobile(val, isRequired: isRequired),
      );
    } else if (rawType == 'NUMBER') {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        keyboardType: TextInputType.number,
        controller: controller,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: isRequired
            ? (val) => (val == null || val.trim().isEmpty)
                  ? '$displayLabel is required'
                  : null
            : null,
      );
    } else if (rawType == 'TEXTAREA') {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        maxLines: 3,
        controller: controller,
        validator: isRequired
            ? (val) => val == null || val.isEmpty
                  ? '$displayLabel is required'
                  : null
            : null,
      );
    } else {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        controller: controller,
        validator: isRequired
            ? (val) => val == null || val.isEmpty
                  ? '$displayLabel is required'
                  : null
            : null,
      );
    }
  }

  // Helper UI methods
  Widget _buildIconTextField(
    String label,
    IconData icon,
    TextEditingController controller, {
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppColors.textLabel,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderEnabled),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(icon, size: 18, color: AppColors.textHint),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    readOnly: onTap != null,
                    onTap: onTap,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: label == 'Date'
                          ? 'Select date '
                          : label == 'Time'
                          ? 'Select time'
                          : '',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textHint,
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        controller.clear();
                      });
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          color: AppColors.primary,
          margin: const EdgeInsets.only(right: 8),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(Widget child1, Widget child2) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child1),
        const SizedBox(width: 16),
        Expanded(child: child2),
      ],
    );
  }
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
