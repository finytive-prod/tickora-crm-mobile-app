import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/owner_call_report.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/usecases/get_staff_users_usecase.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  
  List<StaffUser> _staffList = [];
  String? _selectedStaffUserId; // null or empty means All Staffs

  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedQuickFilter = 'Today';

  List<OwnerCallReport> _allReports = [];
  List<OwnerCallReport> _filteredReports = [];

  @override
  void initState() {
    super.initState();
    _applyQuickDateFilter('Today', fetch: false);
    _loadInitialData();
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
            });
          }
        },
      );
    } catch (_) {}
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
      final List<String>? ownerIdsList = (_selectedStaffUserId != null && _selectedStaffUserId!.isNotEmpty)
          ? [_selectedStaffUserId!]
          : null;

      final result = await repo.getOwnerCallReport(
        ownerId: _selectedStaffUserId,
        ownerIds: ownerIdsList,
        startDate: _startDate != null ? _formatDate(_startDate!) : null,
        endDate: _endDate != null ? _formatDate(_endDate!) : null,
      );

      if (!mounted) return;

      result.fold(
        (failure) {
          setState(() {
            _isLoading = false;
            _errorMessage = failure.message;
          });
        },
        (reports) {
          setState(() {
            _isLoading = false;
            _allReports = reports;
            _applyFilter();
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading call report: $e';
        });
      }
    }
  }

  void _applyFilter() {
    if (_selectedStaffUserId == null || _selectedStaffUserId!.isEmpty) {
      _filteredReports = List.from(_allReports);
    } else {
      _filteredReports = _allReports
          .where((r) => r.ownerId == _selectedStaffUserId)
          .toList();
    }
  }

  void _onStaffChanged(String? newStaffId) {
    setState(() {
      _selectedStaffUserId = newStaffId;
    });
    _fetchCallReport();
  }

  @override
  Widget build(BuildContext context) {
    final int totalCalls = _filteredReports.fold(0, (sum, r) => sum + r.totalCallsCount);
    final int totalIncoming = _filteredReports.fold(0, (sum, r) => sum + r.incomingCalls);
    final int totalOutgoing = _filteredReports.fold(0, (sum, r) => sum + r.outgoingCalls);

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
              // Staff Dropdown
              _buildStaffFilterDropdown(),
              const SizedBox(height: 12),

              // Date Range Filter
              _buildDateFilterSection(),
              const SizedBox(height: 16),

              if (_isLoading) ...[
                const SizedBox(height: 60),
                const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ] else if (_errorMessage != null) ...[
                const SizedBox(height: 40),
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _handleRefresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // KPI Stat Cards
                _buildKpiSummarySection(totalCalls, totalIncoming, totalOutgoing),
                const SizedBox(height: 20),

                const Text(
                  'Staff Call Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                if (_filteredReports.isEmpty) ...[
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

  Widget _buildKpiSummarySection(int totalCalls, int totalIncoming, int totalOutgoing) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryKpiCard(
                'Total Calls',
                totalCalls.toString(),
                Icons.phone,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryKpiCard(
                'Inbound Calls',
                totalIncoming.toString(),
                Icons.call_received,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryKpiCard(
                'Outbound Calls',
                totalOutgoing.toString(),
                Icons.call_made,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStaffReportCard(OwnerCallReport report) {
    final initials = report.ownerName.trim().isNotEmpty
        ? report.ownerName.trim().substring(0, 1).toUpperCase()
        : 'S';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          // Header: Avatar & Owner Name
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.ownerName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.borderEnabled),
          const SizedBox(height: 12),

          // 2 Columns: Inbound & Outbound details
          Row(
            children: [
              // Inbound
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
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
                          Icon(Icons.call_received, color: Color(0xFF16A34A), size: 14),
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
                      const SizedBox(height: 6),
                      Text(
                        '${report.incomingCalls} calls',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Duration: ${report.incomingCallsDuration}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Outbound
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
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
                          Icon(Icons.call_made, color: Color(0xFFEA580C), size: 14),
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
                      const SizedBox(height: 6),
                      Text(
                        '${report.outgoingCalls} calls',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Duration: ${report.outgoingCallsDuration}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFC2410C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Highlighted Total Calls below Incoming box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Total: ${report.totalCallsCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              // Highlighted Total Duration below Outgoing box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Total Duration: ${report.totalDuration}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
