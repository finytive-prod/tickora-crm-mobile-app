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
import 'package:file_picker/file_picker.dart' as fp;
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/lead_form_layout.dart';

class AddLeadScreen extends StatefulWidget {
  final LeadDetail? leadToEdit;
  const AddLeadScreen({super.key, this.leadToEdit});

  @override
  State<AddLeadScreen> createState() => _AddLeadScreenState();
}

class _AddLeadScreenState extends State<AddLeadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _customFieldControllers = {};
  
  // Wizard State
  final PageController _pageController = PageController();
  int _currentPage = 0;
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
  bool _emailAlert = false;
  bool _pushNotification = false;
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

  @override
  void initState() {
    super.initState();
    // Fetch dropdown data just in case they aren't loaded yet
    context.read<LeadsBloc>().add(FetchLeadStatuses());
    context.read<LeadsBloc>().add(FetchLeadSources());
    context.read<LeadsBloc>().add(FetchLeadPriorities());
    context.read<LeadsBloc>().add(const FetchStaffUsers());
    context.read<LeadsBloc>().add(FetchCustomFieldsForm());

    void updateLeadName() {
      if (widget.leadToEdit == null) {
        _leadNameController.text = '${_firstNameController.text} ${_lastNameController.text}'.trim();
      }
    }
    
    _firstNameController.addListener(updateLeadName);
    _lastNameController.addListener(updateLeadName);

    if (widget.leadToEdit != null) {
      final l = widget.leadToEdit!;
      _firstNameController.text = l.firstName;
      _lastNameController.text = l.lastName;
      _companyController.text = l.companyName;
      _emailController.text = l.email;
      _phoneController.text = l.phone;
      _altPhoneController.text = l.alternatePhone ?? '';
      _scoreController.text = (l.score ?? 0).toString();
      _industryController.text = l.industry ?? '';
      _revenueController.text = (l.annualRevenue ?? 0.0).toString();
      _employeeSizeController.text = (l.employeeSize ?? 0).toString();
      _websiteController.text = l.website ?? '';
      _countryController.text = l.country ?? '';
      _stateController.text = l.state ?? '';
      _cityController.text = l.city ?? '';
      _postalController.text = l.postalCode ?? '';
      _addressController.text = l.address ?? '';
      _descriptionController.text = l.description ?? '';
      
      _selectedSource = l.source?.id;
      _selectedStatus = l.status?.id;
      _selectedPriority = l.priority;
      _selectedOwner = l.ownerUserId;
      
      _leadNameController.text = '${l.firstName} ${l.lastName}'.trim();
      
      for (var cf in l.customFields) {
        _customFieldValues[cf.fieldId] = cf.value;
      }
    }
  }

  @override
  void dispose() {
    for (var c in _customFieldControllers.values) {
      c.dispose();
    }
    _pageController.dispose();
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

  TextEditingController _getCustomController(dynamic fieldId, {String defaultText = ''}) {
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
      return;
    }
    if (_currentPage == 1 && _step2FormKey.currentState != null && !_step2FormKey.currentState!.validate()) {
      return;
    }
    if (_currentPage == 2 && _step3FormKey.currentState != null && !_step3FormKey.currentState!.validate()) {
      return;
    }

    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      setState(() {
        _hasCompletedOptionalSteps = true;
      });
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _onSaveLead() {
    bool isStep1Valid = validateAndScrollToError(_step1FormKey);
    bool isStep2Valid = _step2FormKey.currentState == null || _step2FormKey.currentState!.validate();
    bool isStep3Valid = _step3FormKey.currentState == null || _step3FormKey.currentState!.validate();

    if (!isStep1Valid) {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields in Step 1'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!isStep2Valid) {
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields in Step 2'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!isStep3Valid) {
      _pageController.animateToPage(2, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required custom fields in Step 3'), backgroundColor: Colors.orange),
      );
      return;
    }
      final leadData = {
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
        'enableReminder': _emailAlert || _pushNotification || _smsAlert,
        'reminderDate': _formatDateForApi(_reminderDateController.text),
        'reminderTime': _formatTimeForApi(_reminderTimeController.text),
        'repeat': _mapRepeatCycle(_repeatCycleController.text),
        'notifyEmail': _emailAlert,
        'notifySMS': _smsAlert,
        'notifyPush': _pushNotification,
      };

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
          // FILE/DOCUMENT custom field — multiple files
          // For each file: add filename to customFields value, add path to filePaths
          for (var file in value) {
            customFieldsList.add({
              'fieldId': fieldId,
              'value': file.name, // filename goes into JSON
            });
            if (file.path != null) {
              filePaths.add(file.path!); // actual file goes into FormData 'files'
            }
          }
        } else if (value is fp.PlatformFile) {
          // FILE/DOCUMENT custom field — single file
          customFieldsList.add({
            'fieldId': fieldId,
            'value': value.name,
          });
          if (value.path != null) {
            filePaths.add(value.path!);
          }
        } else if (value != null && value.toString().isNotEmpty) {
          // Non-file custom field (DROPDOWN, TEXT, DATE, etc.)
          customFieldsList.add({
            'fieldId': fieldId,
            'value': value,
          });
        }
      });

      if (customFieldsList.isNotEmpty) {
        leadData['customFields'] = customFieldsList;
      }

      if (widget.leadToEdit != null) {
        context.read<LeadsBloc>().add(UpdateLead(
          leadId: widget.leadToEdit!.id,
          leadData: leadData,
          filePaths: filePaths,
        ));
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
        const months = {'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04', 'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08', 'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'};
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
    switch (_currentPage) {
      case 0: return widget.leadToEdit != null ? 'Edit Lead' : 'New Lead';
      case 1: return 'Follow-up & Notes';
      case 2: return 'Custom Fields';
      default: return widget.leadToEdit != null ? 'Edit Lead' : 'New Lead';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LeadsBloc, LeadsState>(
      listener: (context, state) {
        if (state is LeadActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        } else if (state is LeadActionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildStepProgressHeader(),
              Expanded(
                child: BlocBuilder<LeadsBloc, LeadsState>(
                  buildWhen: (prev, current) => current is LeadsLoaded,
                  builder: (context, state) {
                    return PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) => setState(() => _currentPage = index),
                      children: [
                        KeepAliveWrapper(child: _buildLeadDetailsForm(state)),
                        KeepAliveWrapper(child: _buildFollowUpTab()),
                        KeepAliveWrapper(child: _buildCustomFieldsTab(state)),
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
    final steps = ['1. Lead Details', '2. Follow-Up', '3. Custom Fields'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentPage;
          final isCompleted = index < _currentPage || _hasCompletedOptionalSteps;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: Container(
                margin: EdgeInsets.only(right: index == steps.length - 1 ? 0 : 8),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : (isCompleted ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary
                        : (isCompleted ? AppColors.primary.withValues(alpha: 0.3) : AppColors.borderEnabled),
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
                          : (isCompleted ? AppColors.primary : AppColors.textHint),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          );
        }),
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
      child: SafeArea(
        child: _getBottomButtons(),
      ),
    );
  }

  Widget _getBottomButtons() {
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: isLoading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(widget.leadToEdit != null ? 'Update Lead' : 'Save Lead', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: Colors.white, size: 20),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('Next', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ],
            ),
          ),
        );
      }
    } else {
      final isLastStep = _currentPage == 2;
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _nextPage,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderEnabled),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Skip', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  isLastStep ? 'Save' : 'Save & Next', 
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLeadDetailsForm(LeadsState state) {
    List<DropdownMenuItem<String>> statusItems = [];
    List<DropdownMenuItem<String>> sourceItems = [];
    List<DropdownMenuItem<String>> priorityItems = [];
    List<DropdownMenuItem<String>> ownerItems = [];

    if (state is LeadsLoaded) {
      statusItems = state.statuses
          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.statusName, overflow: TextOverflow.ellipsis)))
          .toList();
      sourceItems = state.sources
          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)))
          .toList();
      priorityItems = state.priorities
          .map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)))
          .toList();
      ownerItems = state.owners
          .map((o) => DropdownMenuItem(value: o.userId, child: Text(o.name, overflow: TextOverflow.ellipsis)))
          .toList();

      if (_selectedStatus == null && state.statuses.isNotEmpty) {
        try {
          _selectedStatus = state.statuses.firstWhere((s) => s.isDefault).id;
        } catch (_) {
          _selectedStatus = state.statuses.first.id;
        }
      }
      if (_selectedSource == null && state.sources.isNotEmpty) {
        _selectedSource = state.sources.first.id;
      }
      if (_selectedPriority == null && state.priorities.isNotEmpty) {
        _selectedPriority = state.priorities.first;
      }
      if (_selectedOwner == null && state.owners.isNotEmpty) {
        _selectedOwner = state.owners.first.userId;
      }
    }

    Widget? buildFixedWidget(FixedField ff) {
      final k = ff.fieldName.trim().toLowerCase();
      final label = ff.fieldLabel.trim().isNotEmpty ? ff.fieldLabel.trim() : ff.fieldName;
      final req = ff.isRequired;

      if (k == 'firstname' || k == 'first_name') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _firstNameController,
          inputFormatters: AppInputFormatters.nameFormatters,
          validator: (val) => (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'lastname' || k == 'last_name') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _lastNameController,
          inputFormatters: AppInputFormatters.nameFormatters,
          validator: (val) => (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'companyname' || k == 'company_name' || k == 'company') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _companyController,
          validator: (val) => (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'jobtitle' || k == 'job_title' || k == 'designation') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _jobTitleController,
          validator: (val) => (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'email') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.emailAddress,
          controller: _emailController,
          validator: (val) => AppValidators.validateEmail(val, isRequired: req),
        );
      } else if (k == 'phone' || k == 'mobile') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.phone,
          controller: _phoneController,
          inputFormatters: AppInputFormatters.phoneFormatters,
          validator: (val) => AppValidators.validateMobile(val, isRequired: req),
        );
      } else if (k == 'alternatephone' || k == 'alternate_phone' || k == 'alt_phone') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.phone,
          controller: _altPhoneController,
          inputFormatters: AppInputFormatters.phoneFormatters,
          validator: (val) {
            if (req || (val != null && val.isNotEmpty)) {
              return AppValidators.validateMobile(val, isRequired: req);
            }
            return null;
          },
        );
      } else if (k == 'sourceid' || k == 'source' || k == 'lead_source') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          items: sourceItems,
          value: _selectedSource,
          onChanged: (val) => setState(() => _selectedSource = val),
          validator: (val) => (req && (val == null || val.isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'statusid' || k == 'status' || k == 'lead_status') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          items: statusItems,
          value: _selectedStatus,
          onChanged: (val) => setState(() => _selectedStatus = val),
          validator: (val) => (req && (val == null || val.isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'score' || k == 'lead_score') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.number,
          controller: _scoreController,
          validator: (val) => (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'priority' || k == 'lead_priority') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          items: priorityItems,
          value: _selectedPriority,
          onChanged: (val) => setState(() => _selectedPriority = val),
        );
      } else if (k == 'industry') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _industryController,
          validator: (val) => (req && (val == null || val.trim().isEmpty)) ? 'Required' : null,
        );
      } else if (k == 'annualrevenue' || k == 'annual_revenue' || k == 'revenue') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.number,
          controller: _revenueController,
        );
      } else if (k == 'employeesize' || k == 'employee_size' || k == 'no_of_employees') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.number,
          controller: _employeeSizeController,
        );
      } else if (k == 'website' || k == 'url') {
        return CustomTextField(
          label: label,
          isRequired: req,
          keyboardType: TextInputType.url,
          controller: _websiteController,
        );
      } else if (k == 'country') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _countryController,
        );
      } else if (k == 'state') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _stateController,
        );
      } else if (k == 'city') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _cityController,
        );
      } else if (k == 'postalcode' || k == 'postal_code' || k == 'zip' || k == 'pincode') {
        return CustomTextField(
          label: label,
          isRequired: req,
          controller: _postalController,
        );
      } else if (k == 'address') {
        return CustomTextField(
          label: label,
          isRequired: req,
          maxLines: 3,
          controller: _addressController,
        );
      } else if (k == 'description' || k == 'notes') {
        return CustomTextField(
          label: label,
          isRequired: req,
          maxLines: 3,
          controller: _descriptionController,
        );
      } else if (k == 'owneruserid' || k == 'owner' || k == 'assign_to' || k == 'owner_user_id') {
        return CustomDropdownField<String>(
          label: label,
          isRequired: req,
          items: ownerItems,
          value: _selectedOwner,
          onChanged: (val) => setState(() => _selectedOwner = val),
        );
      }
      return null;
    }

    final List<FixedField> fieldsToShow = (state is LeadsLoaded && state.fixedFields.isNotEmpty)
        ? state.fixedFields
        : const [
            FixedField(fieldName: 'firstName', fieldLabel: 'First Name', fieldType: 'TEXT', isRequired: true, displayOrder: 1),
            FixedField(fieldName: 'lastName', fieldLabel: 'Last Name', fieldType: 'TEXT', isRequired: false, displayOrder: 2),
            FixedField(fieldName: 'companyName', fieldLabel: 'Company Name', fieldType: 'TEXT', isRequired: false, displayOrder: 3),
            FixedField(fieldName: 'email', fieldLabel: 'Email', fieldType: 'EMAIL', isRequired: true, displayOrder: 4),
            FixedField(fieldName: 'phone', fieldLabel: 'Phone', fieldType: 'PHONE', isRequired: true, displayOrder: 5),
            FixedField(fieldName: 'alternatePhone', fieldLabel: 'Alternate Phone', fieldType: 'PHONE', isRequired: false, displayOrder: 6),
            FixedField(fieldName: 'sourceId', fieldLabel: 'Lead Source', fieldType: 'DROPDOWN', isRequired: true, displayOrder: 7),
            FixedField(fieldName: 'statusId', fieldLabel: 'Lead Status', fieldType: 'DROPDOWN', isRequired: true, displayOrder: 8),
            FixedField(fieldName: 'score', fieldLabel: 'Score', fieldType: 'NUMBER', isRequired: false, displayOrder: 9),
            FixedField(fieldName: 'priority', fieldLabel: 'Priority', fieldType: 'DROPDOWN', isRequired: false, displayOrder: 10),
            FixedField(fieldName: 'industry', fieldLabel: 'Industry', fieldType: 'TEXT', isRequired: false, displayOrder: 11),
            FixedField(fieldName: 'website', fieldLabel: 'Website', fieldType: 'URL', isRequired: false, displayOrder: 12),
            FixedField(fieldName: 'country', fieldLabel: 'Country', fieldType: 'TEXT', isRequired: false, displayOrder: 13),
            FixedField(fieldName: 'state', fieldLabel: 'State', fieldType: 'TEXT', isRequired: false, displayOrder: 14),
            FixedField(fieldName: 'city', fieldLabel: 'City', fieldType: 'TEXT', isRequired: false, displayOrder: 15),
            FixedField(fieldName: 'postalCode', fieldLabel: 'Postal Code', fieldType: 'TEXT', isRequired: false, displayOrder: 16),
            FixedField(fieldName: 'address', fieldLabel: 'Address', fieldType: 'TEXTAREA', isRequired: false, displayOrder: 17),
            FixedField(fieldName: 'description', fieldLabel: 'Description', fieldType: 'TEXTAREA', isRequired: false, displayOrder: 18),
            FixedField(fieldName: 'ownerUserId', fieldLabel: 'Assigned To', fieldType: 'DROPDOWN', isRequired: false, displayOrder: 19),
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
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      setState(() {
        _reminderDateController.text = '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
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
        _reminderTimeController.text = '${hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $period';
      });
    }
  }

  Future<void> _pickFollowUpFiles() async {
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
  }

  Widget _buildFollowUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step2FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomTextField(label: 'Lead Name', controller: _leadNameController),
            const SizedBox(height: 16),
            _buildRow(
              _buildIconTextField('Date', Icons.calendar_today_outlined, _reminderDateController, onTap: _pickReminderDate),
              _buildIconTextField('Time', Icons.access_time, _reminderTimeController, onTap: _pickReminderTime),
            ),
            const SizedBox(height: 16),
            
            const Text('Notification Channel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textLabel)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildCheckbox('Email', _emailAlert, (v) => setState(() => _emailAlert = v!)),
                const SizedBox(width: 16),
                _buildCheckbox('Push', _pushNotification, (v) => setState(() => _pushNotification = v!)),
                const SizedBox(width: 16),
                _buildCheckbox('SMS', _smsAlert, (v) => setState(() => _smsAlert = v!)),
              ],
            ),
            const SizedBox(height: 16),
            
            const SizedBox(height: 24),
            const Text('Add Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
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
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Write internal activity report here...', hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Files & Attachments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickFollowUpFiles,
              child: Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                   color: Colors.white, 
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Icon(Icons.file_upload_outlined, color: AppColors.primary, size: 32),
                    const SizedBox(height: 8),
                    const Text('Tap to upload files', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    const Text('PDF, PNG, JPG, or DOC (Max 10MB)', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                  ],
                ),
              ),
            ),
            // Show attached files list
            if (_followUpFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._followUpFiles.asMap().entries.map((entry) {
                final index = entry.key;
                final file = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderEnabled),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(file.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                            Text('${(file.size / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _followUpFiles.removeAt(index)),
                        child: const Icon(Icons.close, size: 18, color: Colors.red),
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



  Widget _buildCustomFieldsTab(LeadsState state) {
    if (state is! LeadsLoaded || state.customFields.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text('No custom fields available.', style: TextStyle(color: AppColors.textHint)),
      ));
    }

    final fields = List.of(state.customFields)..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _step3FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lead Custom Fields', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
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
    final rawType = (field.type != null && field.type.toString().isNotEmpty ? field.type.toString() : (field.fieldType != null ? field.fieldType.toString() : '')).toUpperCase();
    final isRequired = field.isRequired ?? false;
    final displayLabel = (field.fieldLabel != null && field.fieldLabel.toString().trim().isNotEmpty)
        ? field.fieldLabel.toString().trim()
        : (field.label != null && field.label.toString().trim().isNotEmpty ? field.label.toString().trim() : '');
    final rawLabel = displayLabel.toLowerCase();

    if (rawType == 'DROPDOWN' || rawType == 'SELECT') {
      List<DropdownMenuItem<String>> items = [];
      List<dynamic> opts = field.options ?? [];
      for (var opt in opts) {
        items.add(DropdownMenuItem(value: opt.toString(), child: Text(opt.toString())));
      }
      return CustomDropdownField(
        label: displayLabel,
        isRequired: isRequired,
        items: items,
        value: _customFieldValues[field.fieldId]?.toString(),
        onChanged: (val) {
          setState(() {
            _customFieldValues[field.fieldId] = val;
          });
        },
        validator: isRequired ? (val) => val == null || val.toString().isEmpty ? '$displayLabel is required' : null : null,
      );
    } else if (rawType == 'MULTI_SELECT') {
      List<dynamic> opts = field.options ?? [];
      final List<String> currentSelected = _customFieldValues[field.fieldId] is List
          ? List<String>.from(_customFieldValues[field.fieldId])
          : (_customFieldValues[field.fieldId] != null && _customFieldValues[field.fieldId].toString().isNotEmpty
              ? _customFieldValues[field.fieldId].toString().split(',').map((e) => e.trim()).toList()
              : []);

      return FormField<List<String>>(
        initialValue: currentSelected,
        validator: isRequired
            ? (val) => (val == null || val.isEmpty) ? '$displayLabel is required' : null
            : null,
        builder: (formFieldState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  text: displayLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLabel),
                  children: [
                    if (isRequired) const TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
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
                        _customFieldValues[field.fieldId] = List<String>.from(currentSelected);
                        formFieldState.didChange(List<String>.from(currentSelected));
                      });
                    },
                  );
                }).toList(),
              ),
              if (formFieldState.hasError) ...[
                const SizedBox(height: 4),
                Text(formFieldState.errorText!, style: const TextStyle(color: Colors.red, fontSize: 11)),
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
            ? (val) => (val == null || val.trim().isEmpty) ? '$displayLabel is required' : null
            : null,
        builder: (formFieldState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  text: displayLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLabel),
                  children: [
                    if (isRequired) const TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
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
                Text(formFieldState.errorText!, style: const TextStyle(color: Colors.red, fontSize: 11)),
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
              final dateString = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
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
            suffixIcon: const Icon(Icons.calendar_today, size: 18, color: AppColors.textHint),
            validator: isRequired ? (val) => val == null || val.isEmpty ? '$displayLabel is required' : null : null,
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
                final dateStr = '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
                final timeStr = '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
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
            suffixIcon: const Icon(Icons.access_time, size: 18, color: AppColors.textHint),
            validator: isRequired ? (val) => val == null || val.isEmpty ? '$displayLabel is required' : null : null,
          ),
        ),
      );
    } else if (rawType == 'ATTACHMENT' || rawType == 'FILE' || rawType == 'DOCUMENT' || field.attachmentType != null) {
      final List<fp.PlatformFile> pickedFiles =
          _customFieldValues[field.fieldId] is List<fp.PlatformFile>
              ? _customFieldValues[field.fieldId] as List<fp.PlatformFile>
              : [];
      final int maxFiles = field.maxLength ?? 5;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(displayLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textLabel)),
              if (isRequired) const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              if (pickedFiles.length >= maxFiles) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Maximum $maxFiles files allowed'), backgroundColor: Colors.orange),
                );
                return;
              }
              fp.FilePickerResult? result = await fp.FilePicker.pickFiles(
                allowMultiple: true,
                type: fp.FileType.custom,
                allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
              );
              if (result != null && result.files.isNotEmpty) {
                setState(() {
                  final currentFiles = List<fp.PlatformFile>.from(pickedFiles);
                  currentFiles.addAll(result.files);
                  _customFieldValues[field.fieldId] = currentFiles.take(maxFiles).toList();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                 color: Colors.white, 
                 borderRadius: BorderRadius.circular(8),
                 border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.file_upload_outlined, color: AppColors.primary, size: 32),
                  const SizedBox(height: 8),
                  Text('Tap to upload files (${pickedFiles.length}/$maxFiles)', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('PDF, PNG, JPG, or DOC', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                ],
              ),
            ),
          ),
          if (pickedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...pickedFiles.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          Text('${(file.size / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          final updatedFiles = List<fp.PlatformFile>.from(pickedFiles);
                          updatedFiles.removeAt(index);
                          _customFieldValues[field.fieldId] = updatedFiles;
                        });
                      },
                      child: const Icon(Icons.close, size: 18, color: Colors.red),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      );
    } else if (rawType == 'EMAIL' || rawLabel.contains('email') || rawLabel.contains('mail')) {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        keyboardType: TextInputType.emailAddress,
        controller: controller,
        validator: (val) => AppValidators.validateEmail(val, isRequired: isRequired),
      );
    } else if (rawType == 'PHONE' || rawType == 'MOBILE' || rawLabel.contains('phone') || rawLabel.contains('mobile') || rawLabel.contains('contact') || rawLabel.contains('tel') || rawLabel.contains('cell') || rawLabel.contains('whatsapp')) {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        keyboardType: TextInputType.phone,
        controller: controller,
        inputFormatters: AppInputFormatters.phoneFormatters,
        validator: (val) => AppValidators.validateMobile(val, isRequired: isRequired),
      );
    } else if (rawType == 'NUMBER') {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        keyboardType: TextInputType.number,
        controller: controller,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: isRequired ? (val) => (val == null || val.trim().isEmpty) ? '$displayLabel is required' : null : null,
      );
    } else if (rawType == 'TEXTAREA') {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        maxLines: 3,
        controller: controller,
        validator: isRequired ? (val) => val == null || val.isEmpty ? '$displayLabel is required' : null : null,
      );
    } else {
      final controller = _getCustomController(field.fieldId);
      return CustomTextField(
        label: displayLabel,
        isRequired: isRequired,
        controller: controller,
        validator: isRequired ? (val) => val == null || val.isEmpty ? '$displayLabel is required' : null : null,
      );
    }
  }

  // Helper UI methods
  Widget _buildIconTextField(String label, IconData icon, TextEditingController controller, {VoidCallback? onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textLabel)),
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
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Icon(icon, size: 18, color: AppColors.textHint)),
                Expanded(
                  child: TextField(
                    controller: controller,
                    readOnly: onTap != null,
                    onTap: onTap,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: label == 'Date' ? 'Select date' : label == 'Time' ? 'Select time' : '',
                      hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            activeColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
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

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
