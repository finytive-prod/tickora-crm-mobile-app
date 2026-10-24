import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/staff_personal_number.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';
import 'package:crm_mobile/repositories/staff_personal_numbers_repository.dart';
import 'package:crm_mobile/usecases/get_staff_members_usecase.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';

class BlockNumbersScreen extends StatefulWidget {
  const BlockNumbersScreen({super.key});

  @override
  State<BlockNumbersScreen> createState() => _BlockNumbersScreenState();
}

class _BlockNumbersScreenState extends State<BlockNumbersScreen> {
  final _repository = sl<StaffPersonalNumbersRepository>();
  final _searchController = TextEditingController();

  bool get _canRead => sl<PrivilegeService>().hasPrivilege('BLOCKLIST_READ');
  bool get _canCreate => sl<PrivilegeService>().hasPrivilege('BLOCKLIST_CREATE');
  bool get _canUpdate => sl<PrivilegeService>().hasPrivilege('BLOCKLIST_UPDATE');
  bool get _canDelete => sl<PrivilegeService>().hasPrivilege('BLOCKLIST_DELETE');

  List<StaffPersonalNumber> _numbers = [];
  bool _isLoading = true;
  String? _errorMessage;

  List<StaffUser> _staffList = [];
  String? _currentUserId;
  bool _isLoadingStaff = true;

  @override
  void initState() {
    super.initState();
    if (_canRead) {
      _fetchNumbers();
      _fetchStaffUsers();
    } else {
      _isLoading = false;
      _isLoadingStaff = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStaffUsers({StateSetter? modalSetState}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('userId');
      final currentUserName = prefs.getString('userName') ??
          prefs.getString('fullName') ??
          prefs.getString('name');

      final List<StaffUser> loadedStaff = [];

      // 1. Try GetStaffUsersUseCase (hits identity /users/dropdown, /users/staff, /users)
      if (sl.isRegistered<GetStaffUsersUseCase>()) {
        try {
          final res = await sl<GetStaffUsersUseCase>()();
          res.fold(
            (_) {},
            (users) {
              for (final u in users) {
                if (u.userId.trim().isNotEmpty && u.name.trim().isNotEmpty) {
                  loadedStaff.add(u);
                }
              }
            },
          );
        } catch (_) {}
      }

      // 2. Fallback to GetStaffMembersUseCase if empty (hits /users/staff, /users, /leads/search/global)
      if (loadedStaff.isEmpty && sl.isRegistered<GetStaffMembersUseCase>()) {
        try {
          final res = await sl<GetStaffMembersUseCase>()(
            page: 0,
            size: 1000,
            status: 'ALL',
          );
          res.fold(
            (_) {},
            (members) {
              for (final m in members) {
                if (m.id.trim().isNotEmpty && m.fullName.trim().isNotEmpty) {
                  loadedStaff.add(StaffUser(userId: m.id.trim(), name: m.fullName.trim()));
                }
              }
            },
          );
        } catch (_) {}
      }

      // 3. Fallback to SettingsRepository directly if still empty
      if (loadedStaff.isEmpty && sl.isRegistered<SettingsRepository>()) {
        try {
          final res = await sl<SettingsRepository>().getStaffMembers(
            0,
            1000,
            'ALL',
          );
          res.fold(
            (_) {},
            (members) {
              for (final m in members) {
                if (m.id.trim().isNotEmpty && m.fullName.trim().isNotEmpty) {
                  loadedStaff.add(StaffUser(userId: m.id.trim(), name: m.fullName.trim()));
                }
              }
            },
          );
        } catch (_) {}
      }

      // 4. Ensure current user is at least present
      if (_currentUserId != null && _currentUserId!.trim().isNotEmpty) {
        if (!loadedStaff.any((s) => s.userId == _currentUserId)) {
          loadedStaff.insert(
            0,
            StaffUser(
              userId: _currentUserId!.trim(),
              name: (currentUserName != null && currentUserName.trim().isNotEmpty)
                  ? currentUserName.trim()
                  : 'Current User',
            ),
          );
        }
      }

      // 5. Deduplicate by userId and sort alphabetically
      final seenIds = <String>{};
      final uniqueStaff = <StaffUser>[];
      for (final s in loadedStaff) {
        if (s.userId.isNotEmpty && seenIds.add(s.userId)) {
          uniqueStaff.add(s);
        }
      }
      uniqueStaff.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _staffList = uniqueStaff;
          _isLoadingStaff = false;
        });
      }
      if (modalSetState != null) {
        modalSetState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingStaff = false;
        });
      }
      if (modalSetState != null) {
        modalSetState(() {});
      }
    }
  }

  Future<void> _fetchNumbers({String? query}) async {
    if (!_canRead) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'You do not have permission (BLOCKLIST_READ) to view blocked numbers.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _repository.getStaffPersonalNumbers(
      search: query ?? _searchController.text.trim(),
      isActive: null, // show all or active
    );

    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() {
          _isLoading = false;
          _errorMessage = failure.message;
        });
      },
      (data) {
        setState(() {
          _numbers = data;
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _showAddOrEditModal({StaffPersonalNumber? itemToEdit}) async {
    final isEdit = itemToEdit != null;

    if (isEdit && !_canUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You do not have permission (BLOCKLIST_UPDATE) to edit blocked numbers.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!isEdit && !_canCreate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You do not have permission (BLOCKLIST_CREATE) to block numbers.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_staffList.isEmpty && _isLoadingStaff) {
      await _fetchStaffUsers();
    }

    String? selectedStaffId = itemToEdit?.userId ?? _currentUserId;
    if (selectedStaffId == null ||
        (selectedStaffId.isNotEmpty &&
            !_staffList.any((s) => s.userId == selectedStaffId))) {
      if (_staffList.isNotEmpty) {
        selectedStaffId = _staffList.first.userId;
      }
    }

    final phoneController =
        TextEditingController(text: itemToEdit?.phoneNumber ?? '');
    final nameController =
        TextEditingController(text: itemToEdit?.contactName ?? '');
    final notesController =
        TextEditingController(text: itemToEdit?.notes ?? '');
    bool isActive = itemToEdit?.isActive ?? true;
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.phone_disabled_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEdit
                                      ? 'Edit Blocked Number'
                                      : 'Block Personal Number',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Calls with this number will not be recorded or logged.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Staff Member Dropdown
                      Row(
                        children: [
                          const Text(
                            'Staff Member *',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textLabel,
                            ),
                          ),
                          if (_staffList.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${_staffList.length} staff available)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      _isLoadingStaff && _staffList.isEmpty
                          ? Container(
                              height: 48,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: AppColors.borderEnabled),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Loading staff members...',
                                    style: TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _staffList
                                      .any((s) => s.userId == selectedStaffId)
                                  ? selectedStaffId
                                  : (_staffList.isNotEmpty
                                      ? _staffList.first.userId
                                      : null),
                              decoration: InputDecoration(
                                hintText: 'Select Staff Member',
                                hintStyle: const TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.badge_outlined,
                                  size: 20,
                                  color: AppColors.textSecondary,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.borderEnabled,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.borderEnabled,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              items: _staffList
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.userId,
                                      child: Text(
                                        s.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                setModalState(() {
                                  selectedStaffId = val;
                                });
                              },
                              validator: (val) => (val == null || val.isEmpty)
                                  ? 'Please select a staff member'
                                  : null,
                            ),
                      const SizedBox(height: 14),

                      // Phone Number Field
                      const Text(
                        'Phone Number *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textLabel,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: 'e.g. 9876543210',
                          hintStyle: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.borderEnabled,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.borderEnabled,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter phone number';
                          }
                          final digits = val.replaceAll(RegExp(r'\D'), '');
                          if (digits.length < 5) {
                            return 'Please enter a valid phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Contact Name Field
                      const Text(
                        'Contact / Relation Name *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textLabel,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'e.g. Mother, Home, Personal Doctor',
                          hintStyle: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.borderEnabled,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.borderEnabled,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter a name or relationship label';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Notes Field
                      const Text(
                        'Notes (Optional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textLabel,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              'e.g. Staff personal family number - do not record',
                          hintStyle: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.borderEnabled,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.borderEnabled,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Active Switch (Edit mode)
                      if (isEdit) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Active (Block Recording)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Switch.adaptive(
                              value: isActive,
                              activeTrackColor: AppColors.primary,
                              onChanged: (val) {
                                setModalState(() {
                                  isActive = val;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],

                      const SizedBox(height: 10),

                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;

                                  setModalState(() {
                                    isSaving = true;
                                  });

                                  if (isEdit) {
                                    final result = await _repository
                                        .updateStaffPersonalNumber(
                                      itemToEdit.id,
                                      userId: selectedStaffId,
                                      phoneNumber: phoneController.text.trim(),
                                      contactName: nameController.text.trim(),
                                      notes: notesController.text.trim(),
                                      isActive: isActive,
                                    );

                                    if (!sheetContext.mounted) return;

                                    result.fold(
                                      (fail) {
                                        setModalState(() => isSaving = false);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(fail.message),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      },
                                      (_) {
                                        Navigator.pop(sheetContext);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Blocked number updated successfully!',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _fetchNumbers();
                                      },
                                    );
                                  } else {
                                    final result = await _repository
                                        .createStaffPersonalNumber(
                                      userId: selectedStaffId,
                                      phoneNumber: phoneController.text.trim(),
                                      contactName: nameController.text.trim(),
                                      notes: notesController.text.trim(),
                                      isActive: true,
                                    );

                                    if (!sheetContext.mounted) return;

                                    result.fold(
                                      (fail) {
                                        setModalState(() => isSaving = false);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(fail.message),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      },
                                      (_) {
                                        Navigator.pop(sheetContext);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Number blocked successfully! Call tracking disabled.',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _fetchNumbers();
                                      },
                                    );
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  isEdit ? 'Update Number' : 'Block Number',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(StaffPersonalNumber item) {
    if (!_canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You do not have permission (BLOCKLIST_DELETE) to unblock numbers.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: AppColors.primary,
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'Remove from Blocklist',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to unblock "${item.contactName}" (${item.phoneNumber})? Future calls with this number will be tracked normally.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final result =
                  await _repository.deleteStaffPersonalNumber(item.id);
              if (!mounted) return;

              result.fold(
                (fail) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(fail.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
                (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Number unblocked successfully.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _fetchNumbers();
                },
              );
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Block Numbers',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon:
                const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            tooltip: 'Refresh',
            onPressed: () => _fetchNumbers(),
          ),
        ],
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Block Number',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _showAddOrEditModal(),
            )
          : null,
      body: !_canRead
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Access Restricted',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You do not have permission (BLOCKLIST_READ) to view blocked numbers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
          // Informative banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Personal numbers added here will be blocked from call tracking, auto-recording uploads, and CRM call history.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade900,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by phone number or name...',
                hintStyle:
                    const TextStyle(fontSize: 13, color: AppColors.textHint),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 18,
                          color: AppColors.textHint,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _fetchNumbers(query: '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (val) {
                _fetchNumbers(query: val);
              },
            ),
          ),

          // Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: SpinningLogo(size: 50))
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _fetchNumbers(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      )
                    : _numbers.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.phone_disabled_rounded,
                                      size: 40,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No Blocked Numbers',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Add family or personal numbers to ensure calls with them are completely private and never uploaded.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (_canCreate) ...[
                                    const SizedBox(height: 20),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      onPressed: () => _showAddOrEditModal(),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Block Number'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: () => _fetchNumbers(),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
                              itemCount: _numbers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = _numbers[index];
                                return _buildNumberCard(item);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberCard(StaffPersonalNumber item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isActive ? Colors.grey.shade200 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Icon Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.isActive
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.isActive
                  ? Icons.phone_disabled_rounded
                  : Icons.phone_outlined,
              color: item.isActive ? AppColors.primary : Colors.grey,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.contactName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.isActive
                            ? Colors.red.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.isActive ? 'BLOCKED' : 'INACTIVE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color:
                              item.isActive ? AppColors.primary : Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.phoneNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.staffName != null &&
                    item.staffName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Staff: ${item.staffName!.trim()}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.notes!.trim(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Trailing Actions
          if (_canUpdate || _canDelete)
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: AppColors.textSecondary,
                size: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: (val) {
                if (val == 'edit' && _canUpdate) {
                  _showAddOrEditModal(itemToEdit: item);
                } else if (val == 'delete' && _canDelete) {
                  _confirmDelete(item);
                }
              },
              itemBuilder: (ctx) => [
                if (_canUpdate)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                if (_canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Unblock',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
