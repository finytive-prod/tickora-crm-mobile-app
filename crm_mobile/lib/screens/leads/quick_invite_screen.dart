import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/validators.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';

class QuickInviteScreen extends StatefulWidget {
  const QuickInviteScreen({super.key});

  @override
  State<QuickInviteScreen> createState() => _QuickInviteScreenState();
}

class _QuickInviteScreenState extends State<QuickInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _messageController = TextEditingController();

  String? _selectedSource;
  String? _selectedStatus;

  final Map<String, dynamic> _customFieldValues = {};

  @override
  void initState() {
    super.initState();
    context.read<LeadsBloc>().add(FetchCustomFieldsForm());
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _altPhoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onCreate() {
    if (validateAndScrollToError(_formKey)) {
      final Map<String, dynamic> leadData = {
        'firstName': _firstNameController.text,
        'lastName': _lastNameController.text,
        'email': _emailController.text,
        'phone': _mobileController.text,
        'alternatePhone': _altPhoneController.text,
        'sourceId': _selectedSource,
        'statusId': _selectedStatus,
        'invitationMessage': _messageController.text,
      };

      final customFieldsList = <Map<String, dynamic>>[];
      _customFieldValues.forEach((fieldId, value) {
        if (value != null && value.toString().isNotEmpty) {
          customFieldsList.add({
            'fieldId': fieldId,
            'value': value,
          });
        }
      });

      if (customFieldsList.isNotEmpty) {
        leadData['customFields'] = customFieldsList;
      }

      context.read<LeadsBloc>().add(CreateLead(leadData));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LeadsBloc, LeadsState>(
      listener: (context, state) {
        if (state is LeadActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lead invited successfully.'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
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
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Invite New Lead',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: BlocBuilder<LeadsBloc, LeadsState>(
              buildWhen: (prev, current) => current is LeadsLoaded,
              builder: (context, state) {
                List<DropdownMenuItem<String>> statusItems = [];
                List<DropdownMenuItem<String>> sourceItems = [];
                List<dynamic> customFields = [];

                if (state is LeadsLoaded) {
                  statusItems = state.statuses
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.statusName, overflow: TextOverflow.ellipsis)))
                      .toList();
                  sourceItems = state.sources
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)))
                      .toList();
                  customFields = List.of(state.customFields)
                      .where((f) => f.isRequired == true)
                      .toList()
                    ..sort((a, b) => (a.displayOrder ?? 0).compareTo(b.displayOrder ?? 0));
                  
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
                }

                return Form(
                  key: _formKey,
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(Icons.email_outlined, 'Invitation Details'),
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
                      label: 'Mobile No.', 
                      isRequired: true, 
                      keyboardType: TextInputType.phone, 
                      controller: _mobileController,
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
                    CustomTextField(label: 'Alternate Phone', keyboardType: TextInputType.phone, controller: _altPhoneController, inputFormatters: AppInputFormatters.phoneFormatters),
                    CustomDropdownField<String>(
                      label: 'Lead Source', 
                      isRequired: true, 
                      items: sourceItems,
                      value: _selectedSource,
                      onChanged: (val) => setState(() => _selectedSource = val),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRow(
                    CustomDropdownField<String>(
                      label: 'Lead Status', 
                      isRequired: true, 
                      items: statusItems,
                      value: _selectedStatus,
                      onChanged: (val) => setState(() => _selectedStatus = val),
                    ),
                    const SizedBox(),
                  ),
                  const SizedBox(height: 32),
                  
                  _buildSectionTitle(Icons.chat_bubble_outline, 'Custom Message'),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Invitation Message (Optional)',
                    maxLines: 4,
                    controller: _messageController,
                  ),
                  
                  if (customFields.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildSectionTitle(Icons.list_alt, 'Custom Fields'),
                    const SizedBox(height: 16),
                    ...customFields.map((field) {
                      final controller = TextEditingController(
                        text: _customFieldValues[field.fieldId]?.toString() ?? '',
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: CustomTextField(
                          label: field.label,
                          isRequired: field.isRequired,
                          controller: controller,
                          onChanged: (val) {
                            _customFieldValues[field.fieldId] = val;
                          },
                          validator: field.isRequired ? (val) => val == null || val.isEmpty ? 'Required' : null : null,
                        ),
                      );
                    }),
                  ],
                  
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: BlocBuilder<LeadsBloc, LeadsState>(
                      builder: (context, state) {
                        final isLoading = state is LeadActionLoading;
                        return ElevatedButton(
                          onPressed: isLoading ? null : _onCreate,
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
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text('Create Lead', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                    SizedBox(width: 8),
                                    Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    ),
  ),
);
}

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          color: Colors.purple,
          margin: const EdgeInsets.only(right: 8),
        ),
        Icon(icon, size: 20, color: AppColors.textPrimary),
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
