import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/models/role_entity.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';
import 'package:crm_mobile/core/utils/validators.dart';

class EditStaffBottomSheet extends StatefulWidget {
  final StaffMember staff;
  final void Function(Map<String, dynamic> data) onSave;

  const EditStaffBottomSheet({
    super.key,
    required this.staff,
    required this.onSave,
  });

  static Future<void> show(BuildContext context, StaffMember staff, void Function(Map<String, dynamic>) onSave) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditStaffBottomSheet(staff: staff, onSave: onSave),
    );
  }

  @override
  State<EditStaffBottomSheet> createState() => _EditStaffBottomSheetState();
}

class _EditStaffBottomSheetState extends State<EditStaffBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _designationController;
  late final TextEditingController _joiningDateController;

  String? _selectedGender;
  String _selectedRole = '';
  
  bool _isLoadingRoles = true;
  List<RoleDropdownItem> _roleDropdownOptions = [];

  final List<String> _genderOptions = ['MALE', 'FEMALE', 'Other'];

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.staff.fullName);
    _usernameController = TextEditingController(text: widget.staff.username);
    _emailController = TextEditingController(text: widget.staff.email);
    _phoneController = TextEditingController(text: widget.staff.phone);
    _designationController = TextEditingController(text: widget.staff.designation ?? '');
    _joiningDateController = TextEditingController(text: widget.staff.joiningDate ?? '');
    _selectedGender = widget.staff.gender;
    if (_selectedGender == null || _selectedGender!.isEmpty || !_genderOptions.contains(_selectedGender)) {
      _selectedGender = _genderOptions.first;
    }
    _selectedRole = widget.staff.primaryRole;
    _fetchRoles();
  }

  Future<void> _fetchRoles() async {
    final repo = sl<SettingsRepository>();
    final result = await repo.getRolesDropdown();
    if (mounted) {
      setState(() {
        _isLoadingRoles = false;
        result.fold(
          (failure) {}, // Handle error if needed
          (roles) {
            _roleDropdownOptions = roles;
            // Ensure selected role exists in the options
            if (_selectedRole.isEmpty || !_roleDropdownOptions.any((r) => r.id == _selectedRole || r.roleName == _selectedRole)) {
              if (_roleDropdownOptions.isNotEmpty) {
                _selectedRole = _roleDropdownOptions.first.id;
              }
            } else {
              // Try to map role name to id if it's currently a name
              final matchedRole = _roleDropdownOptions.firstWhere((r) => r.roleName == _selectedRole || r.id == _selectedRole, orElse: () => _roleDropdownOptions.first);
              _selectedRole = matchedRole.id;
            }
          },
        );
      });
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _joiningDateController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_joiningDateController.text) ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _joiningDateController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  void _handleSave() {
    if (validateAndScrollToError(_formKey)) {
      final data = {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'roleId': _selectedRole,
        'fullName': _fullNameController.text.trim(),
        'designation': _designationController.text.trim().isEmpty ? '-' : _designationController.text.trim(),
        'gender': _selectedGender ?? 'Other',
        'joiningDate': _joiningDateController.text.trim(),
      };
      widget.onSave(data);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Edit Staff Member',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.borderEnabled),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      CustomTextField(
                        label: 'Full Name',
                        isRequired: true,
                        controller: _fullNameController,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Username',
                        isRequired: true,
                        controller: _usernameController,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Email',
                        isRequired: true,
                        keyboardType: TextInputType.emailAddress,
                        controller: _emailController,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Phone',
                        isRequired: true,
                        keyboardType: TextInputType.phone,
                        controller: _phoneController,
                        inputFormatters: AppInputFormatters.phoneFormatters,
                        validator: (val) => AppValidators.validateMobile(val, isRequired: true),
                      ),
                      const SizedBox(height: 16),
                      CustomDropdownField<String>(
                        label: 'Gender',
                        isRequired: true,
                        value: _selectedGender,
                        items: _genderOptions
                            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedGender = val),
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Designation',
                        controller: _designationController,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Joining Date',
                        isRequired: true,
                        controller: _joiningDateController,
                        hintText: 'YYYY-MM-DD',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today, size: 18, color: AppColors.textHint),
                          onPressed: _pickDate,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isLoadingRoles 
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : CustomDropdownField<String>(
                              label: 'Role',
                              isRequired: true,
                              value: _roleDropdownOptions.any((r) => r.id == _selectedRole) ? _selectedRole : null,
                              items: _roleDropdownOptions
                                  .map((r) => DropdownMenuItem(value: r.id, child: Text(r.roleName)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedRole = val);
                                }
                              },
                            ),
                      const SizedBox(height: 24),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Save Changes',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
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
  }
}