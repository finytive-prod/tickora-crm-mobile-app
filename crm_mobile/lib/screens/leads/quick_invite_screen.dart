import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/validators.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';

class QuickInviteScreen extends StatefulWidget {
  final String? initialPhoneNumber;

  const QuickInviteScreen({super.key, this.initialPhoneNumber});

  @override
  State<QuickInviteScreen> createState() => _QuickInviteScreenState();
}

class _QuickInviteScreenState extends State<QuickInviteScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  

  String? _selectedAssignedUser;
  String? _selectedSource;
  String? _selectedStatus;
  final String _selectedPriority = 'MEDIUM';
  bool _submitted = false;

  String? _currentUserId;
  List<StaffUser> _cachedOwners = [];
  List<LeadStatus> _cachedStatuses = [];
  List<LeadSource> _cachedSources = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPhoneNumber != null && widget.initialPhoneNumber!.isNotEmpty) {
      _phoneController.text = widget.initialPhoneNumber!;
    }
    _loadCurrentUser();
    context.read<LeadsBloc>().add(const FetchStaffUsers());
    context.read<LeadsBloc>().add(FetchLeadStatuses());
    context.read<LeadsBloc>().add(FetchLeadSources());
  }

  void _loadCurrentUser() async {
    final prefs = sl<SharedPreferences>();
    _currentUserId = prefs.getString('userId');
    _fetchStaffDirectly();
  }

  void _fetchStaffDirectly() async {
    try {
      final useCase = sl<GetStaffUsersUseCase>();
      final result = await useCase();
      result.fold(
        (_) {},
        (users) {
          if (mounted && users.isNotEmpty) {
            setState(() {
              _cachedOwners = users;
              if (_selectedAssignedUser == null) {
                final regularStaffOwners = users.where((s) {
                  final isCurrentUser = (_currentUserId != null && s.userId == _currentUserId);
                  final lower = s.name.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
                  final isSuperAdmin = lower.contains('superadmin') || lower == 'admin';
                  return !isCurrentUser && !isSuperAdmin;
                }).toList();
                final otherOwners = users.where((s) => !regularStaffOwners.contains(s)).toList();
                final orderedOwners = [...regularStaffOwners, ...otherOwners];
                if (orderedOwners.isNotEmpty) {
                  _selectedAssignedUser = regularStaffOwners.isNotEmpty
                      ? regularStaffOwners.first.userId
                      : orderedOwners.first.userId;
                }
              }
            });
          }
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onCreate() {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
    });

    if (validateAndScrollToError(_formKey)) {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      final Map<String, dynamic> payload = {
        'phone': phone,
        'mobile': phone,
        'mobileNumber': phone,
      };

      if (name.isNotEmpty) {
        payload['firstName'] = name;
        payload['name'] = name;
      }

      if (_selectedAssignedUser != null && _selectedAssignedUser!.isNotEmpty) {
        payload['assignedTo'] = _selectedAssignedUser;
        payload['ownerUserId'] = _selectedAssignedUser;
      }

      if (_selectedSource != null && _selectedSource!.isNotEmpty) {
        payload['leadSourceId'] = _selectedSource;
        payload['sourceId'] = _selectedSource;
      }

      if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
        payload['leadStatusId'] = _selectedStatus;
        payload['statusId'] = _selectedStatus;
      }

      if (_selectedPriority.isNotEmpty) {
        payload['priority'] = _selectedPriority;
      }

      context.read<LeadsBloc>().add(CreateLead(payload));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LeadsBloc, LeadsState>(
      listener: (context, state) {
        if (state is LeadActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lead invited successfully.'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop(true);
        } else if (state is LeadActionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: BlocBuilder<LeadsBloc, LeadsState>(
                  builder: (context, state) {
                    if (state is LeadsLoaded) {
                      if (state.owners.isNotEmpty) _cachedOwners = state.owners;
                      if (state.statuses.isNotEmpty) _cachedStatuses = state.statuses;
                      if (state.sources.isNotEmpty) _cachedSources = state.sources;
                    }

                    List<DropdownMenuItem<String>> assignedItems = [];
                    final ownersToUse = (state is LeadsLoaded && state.owners.isNotEmpty)
                        ? state.owners
                        : _cachedOwners;

                    if (ownersToUse.isNotEmpty) {
                      final regularStaffOwners = ownersToUse.where((s) {
                        final isCurrentUser = (_currentUserId != null && s.userId == _currentUserId);
                        final lower = s.name.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
                        final isSuperAdmin = lower.contains('superadmin') || lower == 'admin';
                        return !isCurrentUser && !isSuperAdmin;
                      }).toList();

                      final otherOwners = ownersToUse.where((s) => !regularStaffOwners.contains(s)).toList();
                      final orderedOwners = [...regularStaffOwners, ...otherOwners];

                      assignedItems = orderedOwners
                          .map((s) => DropdownMenuItem(
                                value: s.userId,
                                child: Text(s.name, overflow: TextOverflow.ellipsis),
                              ))
                          .toList();

                      if (_selectedAssignedUser != null &&
                          !orderedOwners.any((s) => s.userId == _selectedAssignedUser)) {
                        _selectedAssignedUser = null;
                      }

                      if (_selectedAssignedUser == null && orderedOwners.isNotEmpty) {
                        _selectedAssignedUser = regularStaffOwners.isNotEmpty
                            ? regularStaffOwners.first.userId
                            : orderedOwners.first.userId;
                      }
                    }

                    final statusesToUse = (state is LeadsLoaded && state.statuses.isNotEmpty)
                        ? state.statuses
                        : _cachedStatuses;
                    if (_selectedStatus == null && statusesToUse.isNotEmpty) {
                      try {
                        _selectedStatus = statusesToUse.firstWhere((s) => s.isDefault == true).id;
                      } catch (_) {
                        _selectedStatus = statusesToUse.first.id;
                      }
                    }

                    final sourcesToUse = (state is LeadsLoaded && state.sources.isNotEmpty)
                        ? state.sources
                        : _cachedSources;
                    if (_selectedSource == null && sourcesToUse.isNotEmpty) {
                      _selectedSource = sourcesToUse.first.id;
                    }

                    return Form(
                      key: _formKey,
                      autovalidateMode: _submitted
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Title, Subtitle, Close Button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Quick Invite',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Invite a new lead',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 1. Name Field
                          CustomTextField(
                            label: 'Name',
                            hintText: 'Name',
                            controller: _nameController,
                            inputFormatters: AppInputFormatters.nameFormatters,
                          ),
                          const SizedBox(height: 16),

                          // 2. Phone Number Field (Required)
                          CustomTextField(
                            label: 'Phone Number',
                            hintText: 'Phone Number',
                            isRequired: true,
                            keyboardType: TextInputType.phone,
                            controller: _phoneController,
                            inputFormatters: AppInputFormatters.phoneFormatters,
                            validator: (val) => AppValidators.validateMobile(val, isRequired: true),
                          ),
                          const SizedBox(height: 16),

                          

                          // 4. Assigned To Dropdown
                          CustomDropdownField<String>(
                            label: 'Assigned To',
                            hintText: 'Select Staff Member',
                            items: assignedItems,
                            value: _selectedAssignedUser,
                            onChanged: (val) => setState(() => _selectedAssignedUser = val),
                          ),
                          const SizedBox(height: 28),

                          // Action Buttons: Cancel & Invite
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Color(0xFFD32F2F),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              BlocBuilder<LeadsBloc, LeadsState>(
                                builder: (context, state) {
                                  final isLoading = state is LeadActionLoading;
                                  return ElevatedButton(
                                    onPressed: isLoading ? null : _onCreate,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD32F2F),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    ),
                                    child: isLoading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Text(
                                            'Invite',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
