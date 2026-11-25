import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/role_entity.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';
import 'package:crm_mobile/core/utils/validators.dart';

class AddStaffBottomSheet extends StatefulWidget {
  final Future<String?> Function(Map<String, dynamic> data) onSave;

  const AddStaffBottomSheet({
    super.key,
    required this.onSave,
  });

  static Future<bool?> show(
    BuildContext context,
    Future<String?> Function(Map<String, dynamic> data) onSave,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddStaffBottomSheet(onSave: onSave),
    );
  }

  @override
  State<AddStaffBottomSheet> createState() => _AddStaffBottomSheetState();
}

class _AddStaffBottomSheetState extends State<AddStaffBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _joiningDateController = TextEditingController();
  final TextEditingController _callTargetController = TextEditingController(text: '50');
  final TextEditingController _callTimeTargetController = TextEditingController(text: '08:00:00');

  String? _selectedGender;
  String? _selectedRole;
  String? _selectedManagerId;
  bool _isDefault = false;
  // bool _redirect = true;
  
  bool _isLoadingRoles = true;
  bool _isSubmitting = false;
  String? _serverError;
  List<RoleDropdownItem> _roleDropdownOptions = [];
  List<StaffUser> _managers = [];

  final List<String> _genderOptions = ['FEMALE', 'MALE', 'OTHER'];

  @override
  void initState() {
    super.initState();
    _selectedGender = _genderOptions.first;
    final now = DateTime.now();
    _joiningDateController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _fetchRoles();
    _fetchManagers();
  }

  Future<void> _fetchRoles() async {
    try {
      final repo = sl<SettingsRepository>();
      final result = await repo.getRolesDropdown();
      if (mounted) {
        result.fold(
          (failure) {
            _roleDropdownOptions = const [
              RoleDropdownItem(id: 'TELE_CALLER', roleName: 'Tele Caller', roleCode: 'TELE_CALLER'),
              RoleDropdownItem(id: '8780edfe-2c9d-4f23-ad3d-ca2a605e5bf9', roleName: 'Admin', roleCode: 'ADMIN'),
              RoleDropdownItem(id: '5f2231c9-1f54-4c43-9f68-7d74f5f46d01', roleName: 'Staff', roleCode: 'STAFF'),
              RoleDropdownItem(id: 'a013a3c8-1e2b-48e6-9074-0815e5a56b82', roleName: 'Manager', roleCode: 'MANAGER'),
              RoleDropdownItem(id: '108e1635-4825-45ec-8284-f7ea4b4d3e7d', roleName: 'Assistant Manager', roleCode: 'ASSISTENT_MANAGER'),
            ];
          },
          (roles) {
            _roleDropdownOptions = roles;
          },
        );
        if (_roleDropdownOptions.isNotEmpty) {
          final firstRole = _roleDropdownOptions.first;
          _selectedRole = firstRole.roleCode.isNotEmpty ? firstRole.roleCode : firstRole.id;
        }
      }
    } catch (e) {
      if (_roleDropdownOptions.isEmpty) {
        _roleDropdownOptions = const [
          RoleDropdownItem(id: 'TELE_CALLER', roleName: 'Tele Caller', roleCode: 'TELE_CALLER'),
          RoleDropdownItem(id: '8780edfe-2c9d-4f23-ad3d-ca2a605e5bf9', roleName: 'Admin', roleCode: 'ADMIN'),
          RoleDropdownItem(id: '5f2231c9-1f54-4c43-9f68-7d74f5f46d01', roleName: 'Staff', roleCode: 'STAFF'),
        ];
        _selectedRole = _roleDropdownOptions.first.roleCode.isNotEmpty
            ? _roleDropdownOptions.first.roleCode
            : _roleDropdownOptions.first.id;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoles = false;
        });
      }
    }
  }

  Future<void> _fetchManagers() async {
    try {
      if (sl.isRegistered<GetStaffUsersUseCase>()) {
        final res = await sl<GetStaffUsersUseCase>()();
        res.fold(
          (_) {},
          (users) {
            if (mounted) {
              setState(() {
                _managers = users;
              });
            }
          },
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _joiningDateController.dispose();
    _callTargetController.dispose();
    _callTimeTargetController.dispose();
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

  void _handleSave() async {
    if (_isSubmitting) return;

    final emailError = AppValidators.validateEmail(_emailController.text, isRequired: true);
    final phoneError = AppValidators.validateMobile(_phoneController.text, isRequired: true, fieldName: 'Phone number');
    if (emailError != null || phoneError != null || !validateAndScrollToError(_formKey)) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serverError = null;
    });

    final name = _fullNameController.text.trim();
    final nameParts = name.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : name;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final phone = _phoneController.text.trim();
    final managerId = (_selectedManagerId != null && _selectedManagerId!.isNotEmpty) ? _selectedManagerId : null;
    final role = _selectedRole ?? 'STAFF';

    final data = <String, dynamic>{
      'fullName': name,
      'firstName': firstName,
      'lastName': lastName,
      'email': _emailController.text.trim().toLowerCase(),
      'phone': phone,
      'phoneNumber': phone,
      'gender': _selectedGender ?? _genderOptions.first,
      'joiningDate': _joiningDateController.text.trim(),
      'designation': _designationController.text.trim().isEmpty ? null : _designationController.text.trim(),
      'roleId': role,
      'role': role,
      'reportingManagerId': managerId,
      'reportingTo': managerId,
      'callTarget': int.tryParse(_callTargetController.text.trim()) ?? 50,
      'callTimeTarget': _callTimeTargetController.text.trim().isEmpty ? '08:00:00' : _callTimeTargetController.text.trim(),
      // 'redirect': _redirect,
      'isDefault': _isDefault,
      'password': '',
    };

    final error = await widget.onSave(data);

    if (mounted) {
      if (error == null) {
        // Success: pop bottom sheet returning true to trigger list refresh
        Navigator.of(context).pop(true);
      } else {
        // Failure: stay inside form, show error message banner
        setState(() {
          _isSubmitting = false;
          _serverError = error;
        });
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final effectiveBottomPadding = bottomInset > 0
        ? bottomInset + 12.0
        : (safeBottom > 0 ? safeBottom + 16.0 : 20.0);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: effectiveBottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle Bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Add Member',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Enter basic, work, and organization details',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.borderEnabled),

            // Form Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _autovalidateMode,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Server Error Alert Banner
                      if (_serverError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderEnabled),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _serverError!,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Section 1: Basic Information
                      _buildSectionHeader('Basic Information'),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: 'Full Name',
                        isRequired: true,
                        hintText: 'Full Name',
                        controller: _fullNameController,
                        inputFormatters: AppInputFormatters.noEmojiFormatters,
                        validator: (val) => AppValidators.validateText(val, fieldName: 'Full Name', isRequired: true),
                      ),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: 'Email Address',
                        isRequired: true,
                        hintText: 'Email Address',
                        keyboardType: TextInputType.emailAddress,
                        controller: _emailController,
                        inputFormatters: AppInputFormatters.noEmojiFormatters,
                        validator: (val) => AppValidators.validateEmail(val, isRequired: true),
                      ),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: 'Phone Number',
                        isRequired: true,
                        hintText: 'Phone Number',
                        keyboardType: TextInputType.phone,
                        controller: _phoneController,
                        inputFormatters: AppInputFormatters.phoneFormatters,
                        validator: (val) => AppValidators.validateMobile(val, isRequired: true, fieldName: 'Phone number'),
                      ),
                      const SizedBox(height: 14),

                      CustomDropdownField<String>(
                        label: 'Gender',
                        isRequired: true,
                        value: _selectedGender,
                        items: _genderOptions
                            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedGender = val),
                        validator: (val) => (val == null || val.isEmpty) ? 'Gender is required' : null,
                      ),
                      const SizedBox(height: 22),

                      // Section 2: Work Information
                      _buildSectionHeader('Work Information'),
                      const SizedBox(height: 14),

                      _isLoadingRoles
                          ? const Center(child: Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2)))
                          : CustomDropdownField<String>(
                              label: 'Role',
                              isRequired: true,
                              value: (_selectedRole != null &&
                                      _roleDropdownOptions.any((r) => (r.roleCode.isNotEmpty ? r.roleCode : r.id) == _selectedRole))
                                  ? _selectedRole
                                  : (_roleDropdownOptions.isNotEmpty
                                      ? (_roleDropdownOptions.first.roleCode.isNotEmpty
                                          ? _roleDropdownOptions.first.roleCode
                                          : _roleDropdownOptions.first.id)
                                      : null),
                              items: _roleDropdownOptions
                                  .map((r) => DropdownMenuItem(
                                        value: r.roleCode.isNotEmpty ? r.roleCode : r.id,
                                        child: Text(r.roleName),
                                      ))
                                  .toList(),
                              onChanged: (val) => setState(() => _selectedRole = val),
                              validator: (val) => (val == null || val.isEmpty) ? 'Role is required' : null,
                            ),
                      const SizedBox(height: 14),

                      GestureDetector(
                        onTap: _pickDate,
                        child: AbsorbPointer(
                          child: CustomTextField(
                            label: 'Date of Joining',
                            isRequired: true,
                            controller: _joiningDateController,
                            suffixIcon: const Icon(Icons.calendar_today, size: 20, color: AppColors.textSecondary),
                            validator: (val) => (val == null || val.trim().isEmpty) ? 'Date of Joining is required' : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: 'Designation',
                        hintText: 'Designation',
                        controller: _designationController,
                        inputFormatters: AppInputFormatters.noEmojiFormatters,
                      ),
                      const SizedBox(height: 14),

                      CustomDropdownField<String>(
                        label: 'Reporting Manager',
                        isRequired: false,
                        hintText: 'Select Reporting Manager (Optional)',
                        value: _selectedManagerId ?? '',
                        items: [
                          const DropdownMenuItem(value: '', child: Text('None (No Reporting Manager)')),
                          ..._managers.map((m) => DropdownMenuItem(value: m.userId, child: Text(m.name))),
                        ],
                        onChanged: (val) => setState(() => _selectedManagerId = (val != null && val.isNotEmpty) ? val : null),
                      ),
                      const SizedBox(height: 22),

                      // Section 3: Call Targets & Settings
                      _buildSectionHeader('Call Target & Time'),
                      const SizedBox(height: 14),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CustomTextField(
                              label: 'Call Target',
                              hintText: '50',
                              keyboardType: TextInputType.number,
                              controller: _callTargetController,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              label: 'Call Time Target',
                              hintText: '08:00:00',
                              controller: _callTimeTargetController,
                              inputFormatters: AppInputFormatters.noEmojiFormatters,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Make Default Staff Checkbox
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _isDefault,
                              activeColor: AppColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) => setState(() => _isDefault = val ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Make Default Staff',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Redirect Toggle Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Redirect',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          // Switch.adaptive(
                          //   value: _redirect,
                          //   activeTrackColor: AppColors.primary,
                          //   activeThumbColor: Colors.white,
                          //   onChanged: (val) => setState(() => _redirect = val),
                          // ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Bottom Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _handleSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text('Save Member', style: TextStyle(fontWeight: FontWeight.bold)),
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
  }
}
