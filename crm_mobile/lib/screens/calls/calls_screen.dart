import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/owner_call_report.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/screens/leads/lead_details_screen.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;
  
  List<StaffUser> _staffList = [];
  String? _selectedStaffUserId; // null or empty means All Staffs

  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedQuickFilter = 'Today';

  List<OwnerCallReport> _allReports = [];
  List<OwnerCallReport> _filteredReports = [];
  final Set<String> _expandedOwnerIds = {};
  bool _isStaffReportLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyQuickDateFilter('Today', fetch: false);
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoSync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerAutoSync();
    }
  }

  void _triggerAutoSync() {
    if (!mounted) return;
    AutoCallRecordingUploader.syncRecentCallsIfAvailable(
      onUploadSuccess: () {
        if (mounted) {
          _fetchCallReport();
        }
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _applyQuickDateFilter(String filter, {bool fetch = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _selectedQuickFilter = filter;
      if (filter == 'Today') {
        _startDate = today;
        _endDate = today;
      } else if (filter == 'Yesterday') {
        final yesterday = today.subtract(const Duration(days: 1));
        _startDate = yesterday;
        _endDate = yesterday;
      } else if (filter == 'Last Week') {
        _startDate = today.subtract(const Duration(days: 7));
        _endDate = today;
      } else if (filter == 'Last Month') {
        _startDate = today.subtract(const Duration(days: 30));
        _endDate = today;
      } else if (filter == 'All Time') {
        _startDate = null;
        _endDate = null;
      } else if (filter == 'Custom') {
        // Keep current custom start and end dates
      }
    });

    if (fetch) {
      _fetchCallReport();
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _loadInitialData() async {
    await _handleRefresh();
  }

  Future<void> _handleRefresh() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    await _fetchStaffUsers();
    await _fetchCallReport();
  }

  Future<void> _fetchStaffUsers() async {
    try {
      final useCase = sl<GetStaffUsersUseCase>();
      final result = await useCase();
      result.fold(
        (_) {},
        (users) {
          if (mounted) {
            setState(() {
              _staffList = users;
              _selectDefaultStaffUser();
            });
          }
        },
      );
    } catch (_) {}
  }

  void _selectDefaultStaffUser() {
    if (_selectedStaffUserId != null && _selectedStaffUserId!.isNotEmpty) {
      return;
    }

    if (!sl.isRegistered<SharedPreferences>()) return;
    final prefs = sl<SharedPreferences>();
    final currentUserId = prefs.getString('userId')?.trim();
    final currentUserName = prefs.getString('userName')?.trim().toLowerCase();

    StaffUser? matched;

    if (currentUserId != null && currentUserId.isNotEmpty) {
      for (final staff in _staffList) {
        if (staff.userId.trim() == currentUserId) {
          matched = staff;
          break;
        }
      }
    }

    if (matched == null && currentUserName != null && currentUserName.isNotEmpty) {
      for (final staff in _staffList) {
        if (staff.name.trim().toLowerCase() == currentUserName) {
          matched = staff;
          break;
        }
      }
    }

    if (matched != null && matched.userId.isNotEmpty) {
      _selectedStaffUserId = matched.userId;
    }
  }

  Future<void> _fetchCallReport({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final repo = sl<LeadsRepository>();
      final startStr = _startDate != null ? _formatDate(_startDate!) : null;
      final endStr = _endDate != null ? _formatDate(_endDate!) : null;

      // 1. Fetch Global Report across all staff with ownerIds: []
      final globalResult = await repo.getOwnerCallReport(
        ownerIds: [],
        startDate: startStr,
        endDate: endStr,
      );

      if (!mounted) return;

      globalResult.fold(
        (failure) {
          setState(() {
            _isLoading = false;
            _errorMessage = ErrorHandler.cleanErrorMessage(failure.message);
          });
        },
        (reports) {
          _allReports = reports;
          _isLoading = false;
        },
      );

      // 2. Fetch specific staff breakdown if a staff member is selected
      if (_selectedStaffUserId != null && _selectedStaffUserId!.isNotEmpty) {
        final staffResult = await repo.getOwnerCallReport(
          ownerIds: [_selectedStaffUserId!],
          startDate: startStr,
          endDate: endStr,
        );
        if (mounted) {
          staffResult.fold(
            (_) {
              _filteredReports = _allReports
                  .where((r) => r.ownerId == _selectedStaffUserId)
                  .toList();
            },
            (reports) {
              _filteredReports = reports;
            },
          );
        }
      } else {
        _filteredReports = List.from(_allReports);
      }

      if (mounted) {
        setState(() {
          if (_filteredReports.length == 1) {
            _expandedOwnerIds.add(_filteredReports.first.ownerId);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorHandler.cleanErrorMessage(e.toString());
        });
      }
    }
  }

  void _onStaffChanged(String? newStaffId) async {
    setState(() {
      _selectedStaffUserId = newStaffId;
      _isStaffReportLoading = true;
    });

    try {
      if (newStaffId != null && newStaffId.isNotEmpty) {
        final repo = sl<LeadsRepository>();
        final startStr = _startDate != null ? _formatDate(_startDate!) : null;
        final endStr = _endDate != null ? _formatDate(_endDate!) : null;

        final result = await repo.getOwnerCallReport(
          ownerIds: [newStaffId],
          startDate: startStr,
          endDate: endStr,
        );

        if (!mounted) return;
        result.fold(
          (_) {
            _filteredReports = _allReports
                .where((r) => r.ownerId == newStaffId)
                .toList();
          },
          (reports) {
            _filteredReports = reports;
          },
        );
      } else {
        _filteredReports = List.from(_allReports);
      }
    } catch (_) {
      if (mounted) {
        _filteredReports = (newStaffId != null && newStaffId.isNotEmpty)
            ? _allReports.where((r) => r.ownerId == newStaffId).toList()
            : List.from(_allReports);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStaffReportLoading = false;
          if (_filteredReports.length == 1) {
            _expandedOwnerIds.add(_filteredReports.first.ownerId);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Calls Report',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _handleRefresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Range Filter
              _buildDateFilterSection(),
              const SizedBox(height: 16),

              if (_isLoading) ...[
                const SizedBox(height: 60),
                const Center(
                  child: SpinningLogo(size: 60),
                ),
              ] else if (_errorMessage != null) ...[
                const SizedBox(height: 30),
                Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderEnabled),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEF2F2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage!.toLowerCase().contains('access denied')
                              ? 'Access Denied'
                              : 'Unable to Load Calls Report',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _handleRefresh,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                          label: const Text(
                            'Try Again',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const Text(
                  'Staff Call Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Staff Dropdown below Staff Call Breakdown
                _buildStaffFilterDropdown(),
                const SizedBox(height: 14),

                if (_isStaffReportLoading) ...[
                  const SizedBox(height: 30),
                  const Center(child: SpinningLogo(size: 40)),
                  const SizedBox(height: 30),
                ] else if (_filteredReports.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderEnabled),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(Icons.phone_disabled_outlined, color: AppColors.textHint, size: 40),
                          SizedBox(height: 8),
                          Text(
                            'No call report data available.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _filteredReports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildStaffReportCard(_filteredReports[index]);
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffFilterDropdown() {
    final Map<String, String> staffMap = {};

    for (final staff in _staffList) {
      if (staff.userId.isNotEmpty) {
        final displayName = staff.name.isNotEmpty ? staff.name : 'Staff (${staff.userId})';
        staffMap[staff.userId] = displayName;
      }
    }

    for (final report in _allReports) {
      if (report.ownerId.isNotEmpty && !staffMap.containsKey(report.ownerId)) {
        final displayName = report.ownerName.isNotEmpty ? report.ownerName : 'Owner (${report.ownerId})';
        staffMap[report.ownerId] = displayName;
      }
    }

    String selectedName = 'All Staff Members';
    if (_selectedStaffUserId != null && _selectedStaffUserId!.isNotEmpty) {
      selectedName = staffMap[_selectedStaffUserId] ?? 'Staff (${_selectedStaffUserId!})';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: Text(
            'Select Staff Member',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textLabel,
            ),
          ),
        ),
        InkWell(
          onTap: () => _openStaffPickerModal(staffMap),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderEnabled),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Icon(
                    _selectedStaffUserId == null || _selectedStaffUserId!.isEmpty
                        ? Icons.group_outlined
                        : Icons.person_outline,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selectedName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _selectedStaffUserId != null && _selectedStaffUserId!.isNotEmpty
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedStaffUserId != null && _selectedStaffUserId!.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => _onStaffChanged(null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.keyboard_arrow_down, color: AppColors.textHint, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openStaffPickerModal(Map<String, String> staffMap) {
    final sortedEntries = staffMap.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredList = sortedEntries.where((e) {
              return e.value.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Staff Member',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: TextField(
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search staff by name...',
                        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textHint),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.borderEnabled),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.borderEnabled),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [
                        if (searchQuery.isEmpty || 'all staff members'.contains(searchQuery.toLowerCase())) ...[
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            tileColor: (_selectedStaffUserId == null || _selectedStaffUserId!.isEmpty)
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : Colors.transparent,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: (_selectedStaffUserId == null || _selectedStaffUserId!.isEmpty)
                                  ? AppColors.primary
                                  : const Color(0xFFF1F5F9),
                              child: Icon(
                                Icons.group_outlined,
                                size: 18,
                                color: (_selectedStaffUserId == null || _selectedStaffUserId!.isEmpty)
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                            title: const Text(
                              'All Staff Members',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            trailing: (_selectedStaffUserId == null || _selectedStaffUserId!.isEmpty)
                                ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              _onStaffChanged(null);
                            },
                          ),
                          const Divider(height: 12),
                        ],
                        ...filteredList.map((entry) {
                          final isSelected = _selectedStaffUserId == entry.key;
                          final initial = entry.value.trim().isNotEmpty
                              ? entry.value.trim().substring(0, 1).toUpperCase()
                              : 'S';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            tileColor: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
                              child: Text(
                                initial,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            title: Text(
                              entry.value,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 14,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              _onStaffChanged(entry.key);
                            },
                          );
                        }),
                        if (filteredList.isEmpty && searchQuery.isNotEmpty) ...[
                          const SizedBox(height: 30),
                          const Center(
                            child: Text(
                              'No staff members found matching search.',
                              style: TextStyle(color: AppColors.textHint, fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateFilterSection() {
    final filterOptions = ['Today', 'Yesterday', 'Last Week', 'Last Month', 'All Time', 'Custom'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Date Range Filter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLabel,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: filterOptions.contains(_selectedQuickFilter) ? _selectedQuickFilter : filterOptions.first,
                    isDense: true,
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 18),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    onChanged: (String? val) {
                      if (val != null) {
                        _applyQuickDateFilter(val);
                      }
                    },
                    items: filterOptions.map((String opt) {
                      return DropdownMenuItem<String>(
                        value: opt,
                        child: Text(opt),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedQuickFilter = 'Custom';
                        _startDate = picked;
                      });
                      _fetchCallReport();
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderEnabled),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _startDate != null ? _formatDate(_startDate!) : 'Start Date',
                            style: TextStyle(
                              fontSize: 13,
                              color: _startDate != null ? AppColors.textPrimary : AppColors.textHint,
                              fontWeight: _startDate != null ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedQuickFilter = 'Custom';
                        _endDate = picked;
                      });
                      _fetchCallReport();
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderEnabled),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _endDate != null ? _formatDate(_endDate!) : 'End Date',
                            style: TextStyle(
                              fontSize: 13,
                              color: _endDate != null ? AppColors.textPrimary : AppColors.textHint,
                              fontWeight: _endDate != null ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_startDate != null || _endDate != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                  tooltip: 'Clear Dates',
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                      _selectedQuickFilter = 'All Time';
                    });
                    _fetchCallReport();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  double _parsePercentage(String? pctString, {int? current, int? target}) {
    if (pctString != null && pctString.isNotEmpty) {
      final clean = pctString.replaceAll('%', '').trim();
      final parsed = double.tryParse(clean);
      if (parsed != null) {
        return (parsed / 100.0).clamp(0.0, 1.0);
      }
    }
    if (current != null && target != null && target > 0) {
      return (current / target).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  Widget _buildStaffReportCard(OwnerCallReport report) {
    final initials = report.ownerName.trim().isNotEmpty
        ? report.ownerName.trim().substring(0, 1).toUpperCase()
        : 'S';
    final isExpanded = _expandedOwnerIds.contains(report.ownerId);
    final hasCalledLeads = report.calledLeads.isNotEmpty;

    final double callTargetProgress = _parsePercentage(
      report.callTargetPercentage,
      current: report.totalCallsCount,
      target: report.callTarget,
    );

    final double callTimeTargetProgress = _parsePercentage(
      report.callTimeTargetPercentage,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderEnabled),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header: Avatar, Owner Name, Handled By, and Duration Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.ownerName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (report.callHandledBy != null &&
                        report.callHandledBy!.isNotEmpty &&
                        report.callHandledBy != report.ownerName) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Handled by ${report.callHandledBy}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Duration Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, size: 13, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      report.totalDuration,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2. Target & Progress Section (if callTarget or callTimeTarget exists)
          if ((report.callTarget != null && report.callTarget! > 0) ||
              (report.callTimeTarget != null && report.callTimeTarget!.isNotEmpty)) ...[
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Call Count Target
                  if (report.callTarget != null && report.callTarget! > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.track_changes_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Call Target: ${report.totalCallsCount} / ${report.callTarget}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            report.callTargetPercentage ?? '${(callTargetProgress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: callTargetProgress,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ],

                  if (report.callTarget != null &&
                      report.callTarget! > 0 &&
                      report.callTimeTarget != null &&
                      report.callTimeTarget!.isNotEmpty)
                    const SizedBox(height: 9),

                  // Call Time Target
                  if (report.callTimeTarget != null && report.callTimeTarget!.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF0284C7)),
                            const SizedBox(width: 6),
                            Text(
                              'Time Target: ${report.totalDuration} / ${report.callTimeTarget}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            report.callTimeTargetPercentage ?? '${(callTimeTargetProgress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: callTimeTargetProgress,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 3. Connected vs Not Connected Status Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_in_talk, color: Color(0xFF059669), size: 15),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${report.connectedCallsCount}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF047857),
                              ),
                            ),
                            const Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_missed, color: Color(0xFFDC2626), size: 15),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${report.notConnectedCallsCount}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                            const Text(
                              'Not Connected',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          // 4. Inbound & Outbound Breakdown
          Row(
            children: [
              // Inbound
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.call_received, color: Color(0xFF16A34A), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Incoming',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${report.incomingCalls} calls',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        report.incomingCallsDuration,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Outbound
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.call_made, color: Color(0xFFEA580C), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Outgoing',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC2410C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${report.outgoingCalls} calls',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        report.outgoingCallsDuration,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFFC2410C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 5. Most Talked Lead Banner
          if (report.mostTalkedLeadName != null && report.mostTalkedLeadName!.isNotEmpty) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEDE9FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star_rounded, color: Color(0xFF7C3AED), size: 15),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Most Talked Lead',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6D28D9),
                          ),
                        ),
                        Text(
                          report.mostTalkedLeadName!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5B21B6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (report.mostTalkedLeadDuration != null && report.mostTalkedLeadDuration!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: Text(
                        report.mostTalkedLeadDuration!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6D28D9),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 6. Called Leads Collapsible Section
          if (hasCalledLeads) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedOwnerIds.remove(report.ownerId);
                  } else {
                    _expandedOwnerIds.add(report.ownerId);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list_alt_rounded, size: 15, color: AppColors.primary),
                    const SizedBox(width: 7),
                    Text(
                      'Called Leads (${report.calledLeads.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.primary,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 7),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: report.calledLeads.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, idx) {
                  final lead = report.calledLeads[idx];
                  final isConnected = lead.callStatus.toUpperCase() == 'CONNECTED';
                  final isOutgoing = lead.callType.toUpperCase() == 'OUT';

                  return InkWell(
                    onTap: lead.leadId.isNotEmpty
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LeadDetailsScreen(leadId: lead.leadId),
                              ),
                            );
                          }
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOutgoing ? Icons.call_made : Icons.call_received,
                            size: 15,
                            color: isOutgoing ? const Color(0xFFEA580C) : const Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lead.leadName.isNotEmpty ? lead.leadName : 'Lead (${lead.leadId})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (lead.callHandledBy != null && lead.callHandledBy!.isNotEmpty) ...[
                                  Text(
                                    'By ${lead.callHandledBy}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (lead.formattedCreatedAt.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    lead.formattedCreatedAt,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textHint,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isConnected ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isConnected ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                              ),
                            ),
                            child: Text(
                              isConnected ? 'CONNECTED' : (lead.callStatus.isNotEmpty ? lead.callStatus : 'NOT CONNECTED'),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isConnected ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            lead.duration,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (lead.leadId.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 15, color: AppColors.textHint),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
