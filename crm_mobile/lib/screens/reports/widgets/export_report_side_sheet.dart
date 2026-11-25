import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/widgets/custom_multi_select_dropdown.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:flutter/services.dart';

enum ReportType { status, source, owner }

class ExportReportSideSheet extends StatefulWidget {
  final ReportType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<dynamic> dynamicItems;


  const ExportReportSideSheet({
    Key? key,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.dynamicItems,
    
  }) : super(key: key);

  static void show(
    BuildContext context, {
    required ReportType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<dynamic> dynamicItems,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight, // Slides from right
          child: Material(
            elevation: 16,
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              height: double.infinity,
              child: ExportReportSideSheet(
                type: type,
                title: title,
                subtitle: subtitle,
                icon: icon,
                dynamicItems: dynamicItems,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
          child: child,
        );
      },
    );
  }

  @override
  State<ExportReportSideSheet> createState() => _ExportReportSideSheetState();
}

class _ExportReportSideSheetState extends State<ExportReportSideSheet> {
  String _selectedDateRange = 'All Time';
  DateTime? _fromDate;
  DateTime? _toDate;
  List<dynamic> _selectedDynamicItems = [];
  List<String> _selectedPriorities = [];
  bool _isExporting = false;

  final List<DropdownMenuItem<String>> _dateRangeItems = const [
    DropdownMenuItem(value: 'Today', child: Text('Today')),
    DropdownMenuItem(value: 'This Week', child: Text('This Week')),
    DropdownMenuItem(value: 'This Month', child: Text('This Month')),
    DropdownMenuItem(value: 'All Time', child: Text('All Time')),
    DropdownMenuItem(value: 'Custom', child: Text('Custom')),
  ];

  Future<void> _selectDate(BuildContext context, bool isFrom) async {
    final initialDate = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_toDate != null && _fromDate!.isAfter(_toDate!)) {
            _toDate = null;
          }
        } else {
          _toDate = picked;
        }
      });
    }
  }

  void _calculateDateRange() {
    final now = DateTime.now();
    switch (_selectedDateRange) {
      case 'Today':
        _fromDate = DateTime(now.year, now.month, now.day);
        _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Week':
        _fromDate = now.subtract(Duration(days: now.weekday - 1));
        _toDate = now;
        break;
      case 'This Month':
        _fromDate = DateTime(now.year, now.month, 1);
        _toDate = now;
        break;
      case 'All Time':
        _fromDate = null;
        _toDate = null;
        break;
    }
  }

  Future<void> _handleExport() async {
    if (_selectedDateRange != 'Custom') {
      _calculateDateRange();
    }
    
    setState(() => _isExporting = true);

    String reportTypeString = '';
    List<String> statusIds = [];
    List<String> sourceIds = [];
    List<String> ownerIds = [];

    switch (widget.type) {
      case ReportType.status:
        reportTypeString = 'LEAD_BY_STATUS';
        statusIds = _selectedDynamicItems.map((e) => (e as dynamic).id.toString()).toList();
        break;
      case ReportType.source:
        reportTypeString = 'LEAD_BY_SOURCE';
        sourceIds = _selectedDynamicItems.map((e) => (e as dynamic).id.toString()).toList();
        break;
      case ReportType.owner:
        reportTypeString = 'LEAD_BY_OWNER';
        ownerIds = _selectedDynamicItems.map((e) => (e as dynamic).userId.toString()).toList();
        break;
    }

    final payload = {
      if (_fromDate != null) "startDate": DateFormat('yyyy-MM-dd').format(_fromDate!),
      if (_toDate != null) "endDate": DateFormat('yyyy-MM-dd').format(_toDate!),
      if (statusIds.isNotEmpty) "statusIds": statusIds,
      if (sourceIds.isNotEmpty) "sourceIds": sourceIds,
      if (ownerIds.isNotEmpty) "ownerUserIds": ownerIds,
      if (_selectedPriorities.isNotEmpty) "priorities": _selectedPriorities,
      "reportType": reportTypeString,
    };

    final repository = sl<LeadsRepository>();
    final result = await repository.exportLeadReport(payload);

    setState(() => _isExporting = false);

    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: ${failure.message}'), backgroundColor: AppColors.primary));
      },
      (filePath) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File downloaded temporarily, saving to Downloads...')));
        
        try {
          final savedPath = await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod<String>(
            'saveToDownloads',
            {
              'filePath': filePath,
              'fileName': 'LeadReport_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
              'mimeType': 'text/csv',
            }
          );
          
          if (!mounted) return;
          Navigator.of(context).pop();
          if (savedPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to Downloads: $savedPath'), backgroundColor: Colors.green));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save to Downloads'), backgroundColor: AppColors.primary));
          }
        } catch (e) {
          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save to Downloads (Permission missing?)'), backgroundColor: AppColors.primary));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String dynamicLabel;
    switch (widget.type) {
      case ReportType.status:
        dynamicLabel = 'Select statuses';
        break;
      case ReportType.source:
        dynamicLabel = 'Select sources';
        break;
      case ReportType.owner:
        dynamicLabel = 'Select owners';
        break;
    }

    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.subtitle,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    
                    // Form Fields
                    CustomDropdownField<String>(
                      label: 'Select date range',
                      items: _dateRangeItems,
                      value: _selectedDateRange,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDateRange = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    if (_selectedDateRange == 'Custom')
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('From date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLabel)),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _selectDate(context, true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppColors.borderEnabled),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_fromDate != null ? DateFormat('MM/dd/yyyy').format(_fromDate!) : 'MM/DD/YYYY', style: TextStyle(color: _fromDate != null ? AppColors.textPrimary : AppColors.textHint)),
                                        const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textHint),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('To date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLabel)),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _selectDate(context, false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppColors.borderEnabled),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_toDate != null ? DateFormat('MM/dd/yyyy').format(_toDate!) : 'MM/DD/YYYY', style: TextStyle(color: _toDate != null ? AppColors.textPrimary : AppColors.textHint)),
                                        const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textHint),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    
                    if (_selectedDateRange == 'Custom') const SizedBox(height: 16),
                    
                    CustomMultiSelectDropdown<dynamic>(
                      label: dynamicLabel,
                      items: widget.dynamicItems,
                      selectedItems: _selectedDynamicItems,
                      itemLabelBuilder: (item) {
                        if (widget.type == ReportType.status) return (item as dynamic).statusName;
                        if (widget.type == ReportType.source) return (item as dynamic).name;
                        if (widget.type == ReportType.owner) return (item as dynamic).name;
                        return item.toString();
                      },
                      onChanged: (selected) {
                        setState(() => _selectedDynamicItems = selected);
                      },
                    ),

                    const SizedBox(height: 16),
                 

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            
            // Footer Buttons
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.borderEnabled),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isExporting ? null : _handleExport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _isExporting 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Export', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
