import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
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
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/screens/leads/lead_details_screen.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';

class QuickInviteScreen extends StatefulWidget {
  final String? initialPhoneNumber;

  const QuickInviteScreen({super.key, this.initialPhoneNumber});

  @override
  State<QuickInviteScreen> createState() => _QuickInviteScreenState();
}

class _QuickInviteScreenState extends State<QuickInviteScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController(text: 'quick call user');
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

  Timer? _searchDebounce;
  bool _isCheckingPhone = false;
  bool _isExistingLead = false;
  String? _existingLeadId;
  String? _existingLeadName;
  String? _existingAssignedTo;
  String? _existingLeadCreatedAt;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
    if (widget.initialPhoneNumber != null && widget.initialPhoneNumber!.isNotEmpty) {
      _phoneController.text = widget.initialPhoneNumber!;
      _checkPhoneNumber(widget.initialPhoneNumber!);
    }
    _loadCurrentUser();
    context.read<LeadsBloc>().add(const FetchStaffUsers());
    context.read<LeadsBloc>().add(FetchLeadStatuses());
    context.read<LeadsBloc>().add(FetchLeadSources());
  }

  String? _formatDateTimeString(String dateStr) {
    if (dateStr.trim().isEmpty) return null;
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('MMM dd, yyyy, hh:mm a').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  void _onPhoneChanged() {
    final text = _phoneController.text.trim();
    _searchDebounce?.cancel();
    if (text.length < 5) {
      if (_isExistingLead || _existingLeadId != null || _isCheckingPhone) {
        setState(() {
          _isExistingLead = false;
          _existingLeadId = null;
          _existingLeadName = null;
          _existingAssignedTo = null;
          _existingLeadCreatedAt = null;
          _isCheckingPhone = false;
        });
      }
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _checkPhoneNumber(text);
    });
  }

  Future<void> _checkPhoneNumber(String phone) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return;

    if (mounted) {
      setState(() {
        _isCheckingPhone = true;
      });
    }

    try {
      final repo = sl<LeadsRepository>();
      final response = await repo.searchLeadByNumber(cleanPhone);

      if (!mounted) return;

      response.fold(
        (failure) {
          setState(() {
            _isCheckingPhone = false;
            _isExistingLead = false;
            _existingLeadId = null;
            _existingLeadName = null;
            _existingAssignedTo = null;
            _existingLeadCreatedAt = null;
          });
        },
        (result) {
          if (mounted) {
            String? parsedDate;
            if (result.createdAt != null && result.createdAt!.isNotEmpty) {
              parsedDate = _formatDateTimeString(result.createdAt!);
            }

            setState(() {
              _isCheckingPhone = false;
              if (result.alreadyMapped && result.leadId != null && result.leadId!.isNotEmpty) {
                _isExistingLead = true;
                _existingLeadId = result.leadId;
                _existingLeadName = result.name;
                _existingAssignedTo = result.assignedToName ?? result.assignedToInfo;
                _existingLeadCreatedAt = parsedDate;
                if (_nameController.text.trim().isEmpty && result.name != null && result.name!.isNotEmpty) {
                  _nameController.text = result.name!;
                }
              } else {
                _isExistingLead = false;
                _existingLeadId = null;
                _existingLeadName = null;
                _existingAssignedTo = null;
                _existingLeadCreatedAt = null;
              }
            });

            if (result.alreadyMapped && result.leadId != null && (_existingLeadCreatedAt == null || _existingLeadCreatedAt!.isEmpty)) {
              final leadId = result.leadId!;
              repo.getLeadDetails(leadId).then((detailRes) {
                detailRes.fold(
                  (_) {},
                  (leadDetail) {
                    if (mounted && _existingLeadId == leadId && leadDetail.createdAt != null) {
                      setState(() {
                        _existingLeadCreatedAt = DateFormat('MMM dd, yyyy, hh:mm a').format(leadDetail.createdAt!.toLocal());
                      });
                    }
                  },
                );
              });
            }
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingPhone = false;
          _isExistingLead = false;
          _existingLeadId = null;
          _existingLeadName = null;
          _existingAssignedTo = null;
          _existingLeadCreatedAt = null;
        });
      }
    }
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
                final currentUserList = users.where((s) => _currentUserId != null && s.userId == _currentUserId).toList();
                if (currentUserList.isNotEmpty) {
                  _selectedAssignedUser = currentUserList.first.userId;
                } else {
                  final sortedOwners = List<StaffUser>.from(users)
                    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  _selectedAssignedUser = sortedOwners.first.userId;
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
    _searchDebounce?.cancel();
    _phoneController.removeListener(_onPhoneChanged);
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

      context.read<LeadsBloc>().add(QuickInviteLead(payload));
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
            SnackBar(content: Text(state.message), backgroundColor: AppColors.primary),
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
                    List<StaffUser> ownersToUse = (state is LeadsLoaded && state.owners.isNotEmpty)
                        ? List.from(state.owners)
                        : List.from(_cachedOwners);

                    if (ownersToUse.isEmpty && _currentUserId != null) {
                      final prefs = sl<SharedPreferences>();
                      final userName = prefs.getString('userName') ?? 'Me';
                      ownersToUse.add(StaffUser(userId: _currentUserId!, name: userName));
                    }

                    final canAssign = sl<PrivilegeService>().canAssignLeads();

                    if (ownersToUse.isNotEmpty) {
                      final currentUserList = ownersToUse.where((s) => _currentUserId != null && s.userId == _currentUserId).toList();
                      
                      // Remove duplicate user IDs and sort alphabetically
                      final Set<String> seenIds = {};
                      List<StaffUser> orderedOwners = ownersToUse.where((s) {
                        if (seenIds.contains(s.userId)) return false;
                        seenIds.add(s.userId);
                        return true;
                      }).toList()
                        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                      if (!canAssign) {
                        String ownerName = '';
                        String ownerId = '';
                        if (_isExistingLead && _existingAssignedTo != null && _existingAssignedTo!.trim().isNotEmpty && _existingAssignedTo!.trim().toLowerCase() != 'unassigned') {
                          ownerName = _existingAssignedTo!.trim();
                          final match = ownersToUse.where((s) => s.name.trim().toLowerCase() == ownerName.toLowerCase()).toList();
                          ownerId = match.isNotEmpty ? match.first.userId : ownerName;
                        } else if (!_isExistingLead) {
                          if (currentUserList.isNotEmpty) {
                            ownerId = currentUserList.first.userId;
                            ownerName = currentUserList.first.name;
                          } else {
                            ownerId = _currentUserId ?? '';
                            ownerName = sl.isRegistered<SharedPreferences>()
                                ? (sl<SharedPreferences>().getString('userName') ?? 'Assigned Staff')
                                : 'Assigned Staff';
                          }
                        } else {
                          ownerName = _existingAssignedTo?.trim() ?? 'Unassigned';
                          ownerId = ownerName;
                        }
                        final singleOwner = StaffUser(userId: ownerId, name: ownerName);
                        orderedOwners = [singleOwner];
                        _selectedAssignedUser = singleOwner.userId;
                      }

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
                        final currentStaff = orderedOwners.where((s) => _currentUserId != null && s.userId == _currentUserId).toList();
                        final defaultUserId = currentStaff.isNotEmpty ? currentStaff.first.userId : orderedOwners.first.userId;
                        // Use Future.microtask to avoid modifying state during build
                        Future.microtask(() {
                          if (mounted && _selectedAssignedUser != defaultUserId) {
                            setState(() {
                              _selectedAssignedUser = defaultUserId;
                            });
                          }
                        });
                        // Also set it locally for the current build to avoid null value
                        _selectedAssignedUser = defaultUserId;
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
                          if (_isCheckingPhone) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: const [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Checking phone number...',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                          if (_isExistingLead && _existingLeadId != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFCD34D)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Lead Already Exists',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF92400E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (_existingLeadName != null && _existingLeadName!.trim().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Text(
                                          'Lead Name: ',
                                          style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w500),
                                        ),
                                        Expanded(
                                          child: Text(
                                            _existingLeadName!.trim(),
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Row(
                                    children: [
                                      const Text(
                                        'Assigned To: ',
                                        style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w500),
                                      ),
                                      Expanded(
                                        child: Text(
                                          (_existingAssignedTo != null && _existingAssignedTo!.trim().isNotEmpty)
                                              ? _existingAssignedTo!.trim()
                                              : 'Unassigned',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Text(
                                        'Created At: ',
                                        style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w500),
                                      ),
                                      Expanded(
                                        child: Text(
                                          (_existingLeadCreatedAt != null && _existingLeadCreatedAt!.trim().isNotEmpty)
                                              ? _existingLeadCreatedAt!.trim()
                                              : '—',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        final leadIdToOpen = _existingLeadId!;
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => LeadDetailsScreen(
                                              leadId: leadIdToOpen,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.visibility_outlined, color: Colors.white, size: 16),
                                      label: const Text(
                                        'View Lead',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // 3. Lead Source Dropdown
                          CustomDropdownField<String>(
                            label: 'Lead Source',
                            hintText: 'Select Lead Source',
                            items: sourcesToUse
                                .map((s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            value: _selectedSource,
                            onChanged: (val) => setState(() => _selectedSource = val),
                          ),
                          const SizedBox(height: 16),

                          // 4. Assigned To Dropdown
                          CustomDropdownField<String>(
                            label: 'Assigned To',
                            hintText: 'Select Staff Member',
                            enabled: canAssign,
                            items: assignedItems,
                            value: _selectedAssignedUser,
                            onChanged: canAssign ? (val) => setState(() => _selectedAssignedUser = val) : null,
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
                              if (!_isExistingLead || _existingLeadId == null) ...[
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
