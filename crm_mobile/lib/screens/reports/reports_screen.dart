import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/screens/reports/widgets/report_card.dart';
import 'package:crm_mobile/screens/reports/widgets/export_report_side_sheet.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  void _showStatusReportSheet(BuildContext context, LeadsState state) {
    List<dynamic> items = [];
    if (state is LeadsLoaded) {
      items = state.statuses;
    }
    ExportReportSideSheet.show(
      context,
      type: ReportType.status,
      title: 'Export lead by status',
      subtitle: 'Export leads grouped by their current pipeline status.',
      icon: Icons.account_tree_outlined,
      dynamicItems: items,
    );
  }

  void _showSourceReportSheet(BuildContext context, LeadsState state) {
    List<dynamic> items = [];
    if (state is LeadsLoaded) {
      items = state.sources;
    }
    ExportReportSideSheet.show(
      context,
      type: ReportType.source,
      title: 'Export lead by source',
      subtitle: 'Export leads with their acquisition source channel.',
      icon: Icons.filter_alt_outlined,
      dynamicItems: items,
    );
  }

  void _showOwnerReportSheet(BuildContext context, LeadsState state) {
    List<dynamic> items = [];
    if (state is LeadsLoaded) {
      items = state.owners;
    }
    ExportReportSideSheet.show(
      context,
      type: ReportType.owner,
      title: 'Export lead by owner',
      subtitle: 'Export leads grouped by the assigned sales representative.',
      icon: Icons.badge_outlined,
      dynamicItems: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Lead Reports',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Welcome to your Tickora CRM view',
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: BlocBuilder<LeadsBloc, LeadsState>(
        builder: (context, state) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ReportCard(
                    icon: Icons.account_tree_outlined,
                    title: 'Lead by Status',
                    subtitle: 'Export leads grouped by their current pipeline status.',
                    onExport: () => _showStatusReportSheet(context, state),
                  ),
                  ReportCard(
                    icon: Icons.filter_alt_outlined,
                    title: 'Lead by Source',
                    subtitle: 'Export leads with their acquisition source channel.',
                    onExport: () => _showSourceReportSheet(context, state),
                  ),
                  ReportCard(
                    icon: Icons.badge_outlined,
                    title: 'Lead by Owner',
                    subtitle: 'Export leads grouped by the assigned sales representative.',
                    onExport: () => _showOwnerReportSheet(context, state),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
