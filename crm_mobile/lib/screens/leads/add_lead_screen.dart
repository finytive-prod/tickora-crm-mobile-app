import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/validators.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:crm_mobile/models/lead_detail.dart';

class AddLeadScreen extends StatefulWidget {
  final LeadDetail? leadToEdit;
  const AddLeadScreen({super.key, this.leadToEdit});

  @override
  State<AddLeadScreen> createState() => _AddLeadScreenState();
}

class _AddLeadScreenState extends State<AddLeadScreen> {
  final _formKey = GlobalKey<FormState>();
  
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

  void _nextPage() {
    if (_currentPage == 0 && !_formKey.currentState!.validate()) {
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
    if (_formKey.currentState!.validate()) {
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
          setState(() {
            _hasCompletedOptionalSteps = false;
          });
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
          child: BlocBuilder<LeadsBloc, LeadsState>(
            buildWhen: (prev, current) => current is LeadsLoaded,
            builder: (context, state) {
              return PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildLeadDetailsForm(state),
                  _buildFollowUpTab(),
                  _buildCustomFieldsTab(state),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Basic Information & Lead Details'),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(
                label: 'First Name', 
                isRequired: true, 
                controller: _firstNameController,
                inputFormatters: AppInputFormatters.nameFormatters,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Required';
                  return null;
                },
              ),
              CustomTextField(
                label: 'Last Name', 
                controller: _lastNameController,
                inputFormatters: AppInputFormatters.nameFormatters,
              ),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(
                label: 'Phone', 
                isRequired: true, 
                keyboardType: TextInputType.phone, 
                controller: _phoneController,
                inputFormatters: AppInputFormatters.phoneFormatters,
                validator: (val) => AppValidators.validateMobile(val, isRequired: true),
              ),
              CustomTextField(
                label: 'Email', 
                isRequired: true,
                keyboardType: TextInputType.emailAddress, 
                controller: _emailController,
                validator: (val) => AppValidators.validateEmail(val, isRequired: true),
              ),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(
                label: 'Alternate Phone', 
                keyboardType: TextInputType.phone, 
                controller: _altPhoneController,
                inputFormatters: AppInputFormatters.phoneFormatters,
                validator: (val) {
                  if (val != null && val.isNotEmpty) {
                    return AppValidators.validateMobile(val, isRequired: false);
                  }
                  return null;
                },
              ),
              CustomDropdownField<String>(
                label: 'Owner',
                items: ownerItems,
                value: _selectedOwner,
                onChanged: (val) => setState(() => _selectedOwner = val),
              ),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'Company Name', controller: _companyController),
              CustomTextField(label: 'Job Title', controller: _jobTitleController),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomDropdownField<String>(
                label: 'Lead Source', 
                isRequired: true, 
                items: sourceItems,
                value: _selectedSource,
                onChanged: (val) => setState(() => _selectedSource = val),
              ),
              CustomDropdownField<String>(
                label: 'Lead Status', 
                isRequired: true, 
                items: statusItems,
                value: _selectedStatus,
                onChanged: (val) => setState(() => _selectedStatus = val),
              ),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'Score', keyboardType: TextInputType.number, controller: _scoreController),
              CustomDropdownField<String>(
                label: 'Priority',
                items: priorityItems,
                value: _selectedPriority,
                onChanged: (val) => setState(() => _selectedPriority = val),
              ),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'Industry', controller: _industryController),
              CustomTextField(label: 'Annual Revenue', keyboardType: TextInputType.number, controller: _revenueController),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'Employee Size', keyboardType: TextInputType.number, controller: _employeeSizeController),
              CustomTextField(label: 'Website', keyboardType: TextInputType.url, controller: _websiteController),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'Country', controller: _countryController),
              CustomTextField(label: 'State', controller: _stateController),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'City', controller: _cityController),
              CustomTextField(label: 'Postal Code', controller: _postalController),
            ),
            const SizedBox(height: 16),
            _buildRow(
              CustomTextField(label: 'Address', maxLines: 3, controller: _addressController),
              CustomTextField(label: 'Description', maxLines: 3, controller: _descriptionController),
            ),
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
    );
  }

  Widget _buildDynamicField(dynamic field) { 
    
    final type = field.type;
    final isRequired = field.isRequired;
    
    if (type == 'DROPDOWN') {
      List<DropdownMenuItem<String>> items = [];
      for (var opt in field.options) {
        items.add(DropdownMenuItem(value: opt.toString(), child: Text(opt.toString())));
      }
      return CustomDropdownField(
        label: field.label,
        isRequired: isRequired,
        items: items,
        value: _customFieldValues[field.fieldId],
        onChanged: (val) {
          setState(() {
            _customFieldValues[field.fieldId] = val;
          });
        },
        validator: isRequired ? (val) => val == null || val.toString().isEmpty ? 'Required' : null : null,
      );
    } else if (type == 'DATE') {
      final controller = TextEditingController(
        text: _customFieldValues[field.fieldId] != null ? _customFieldValues[field.fieldId].toString() : '',
      );
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
            label: field.label,
            isRequired: isRequired,
            controller: controller,
            validator: isRequired ? (val) => val == null || val.isEmpty ? 'Required' : null : null,
          ),
        ),
      );
    } else if (type == 'ATTACHMENT') {
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
              Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textLabel)),
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
                  // Enforce max file limit
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
          // Show selected files with remove button
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
    } else {
      final controller = TextEditingController(
        text: _customFieldValues[field.fieldId] != null ? _customFieldValues[field.fieldId].toString() : '',
      );
      return CustomTextField(
        label: field.label,
        isRequired: isRequired,
        controller: controller,
        onChanged: (val) {
          _customFieldValues[field.fieldId] = val;
        },
        validator: isRequired ? (val) => val == null || val.isEmpty ? 'Required' : null : null,
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
