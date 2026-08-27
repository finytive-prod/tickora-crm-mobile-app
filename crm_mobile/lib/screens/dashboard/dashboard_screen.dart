import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/dashboard_bloc.dart';
import 'package:crm_mobile/blocs/dashboard_event.dart';
import 'package:crm_mobile/blocs/dashboard_state.dart';
import 'package:crm_mobile/repositories/dashboard_repository.dart';
import 'package:crm_mobile/models/dashboard_models.dart';
import 'package:crm_mobile/screens/dashboard/dashboard_charts.dart';
import 'package:crm_mobile/screens/dashboard/customize_dashboard_modal.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DashboardBloc>()..add(const FetchDashboardPreferences()),
      child: const DashboardView(),
    );
  }
}

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  String _trendPeriod = 'weekly';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DashboardBloc>().add(const FetchDashboardPreferences());
      }
    });
  }

  void _openCustomizeModal(BuildContext context, List<String> currentWidgets) async {
    final selected = await CustomizeDashboardModal.show(context, currentWidgets);
    if (selected != null && context.mounted) {
      context.read<DashboardBloc>().add(UpdateDashboardPreferences(selected));
    }
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return const Color(0xFF3B82F6);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.webp',
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => const Icon(Icons.dashboard_customize_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            const Text(
              'Dashboard',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          BlocBuilder<DashboardBloc, DashboardState>(
            builder: (context, state) {
              List<String> visibleWidgets = DashboardWidgetKeys.allKeys;
              if (state is DashboardLoaded) {
                visibleWidgets = state.visibleWidgets;
              } else if (state is DashboardUpdating) {
                visibleWidgets = state.currentWidgets;
              } else if (state is DashboardUpdateSuccess) {
                visibleWidgets = state.visibleWidgets;
              }
              return IconButton(
                icon: const Icon(Icons.tune_rounded, color: AppColors.textPrimary),
                tooltip: 'Customize Dashboard',
                onPressed: () => _openCustomizeModal(context, visibleWidgets),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            tooltip: 'Refresh Dashboard',
            onPressed: () => context.read<DashboardBloc>().add(const FetchDashboardPreferences()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: BlocConsumer<DashboardBloc, DashboardState>(
        listener: (context, state) {
          if (state is DashboardUpdateSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dashboard preferences saved successfully'),
                backgroundColor: Color(0xFF10B981),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (state is DashboardError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.primary,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is DashboardLoading) {
            return const Center(child: SpinningLogo(size: 60));
          }

          List<String> visibleWidgets = DashboardWidgetKeys.allKeys;
          SummaryMetrics summaryMetrics = SummaryMetrics();
          ChartsData chartsData = ChartsData(statusDistribution: [], sourceDistribution: [], salesPipeline: []);
          LeadTrendData leadTrendData = LeadTrendData(leadsCreated: [], leadsWon: []);
          List<DashboardRecentLead> recentLeads = [];
          List<DashboardUpcomingFollowup> upcomingFollowups = [];
          List<DashboardRecentActivity> recentActivities = [];
          RevenueTargetData revenueTarget = RevenueTargetData();

          if (state is DashboardLoaded) {
            visibleWidgets = state.visibleWidgets;
            summaryMetrics = state.summaryMetrics;
            chartsData = state.chartsData;
            leadTrendData = state.leadTrendData;
            recentLeads = state.recentLeads;
            upcomingFollowups = state.upcomingFollowups;
            recentActivities = state.recentActivities;
            revenueTarget = state.revenueTarget;
            _trendPeriod = state.activeTrendPeriod;
          } else if (state is DashboardUpdating) {
            visibleWidgets = state.currentWidgets;
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<DashboardBloc>().add(const FetchDashboardPreferences());
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 1. TOP 8 METRIC CARDS GRID ─────────────────────────────────
                  _buildStatCardsGrid(visibleWidgets, summaryMetrics),
                  if (_hasAnyStatCardVisible(visibleWidgets)) const SizedBox(height: 16),

                  // ─── 2. LEAD TREND ANALYSIS ───────────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.leadTrendAnalysis) || visibleWidgets.contains('LEAD_TREND')) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.show_chart, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Lead Trend Analysis',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Filter Pills above chart
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: ['weekly', 'monthly'].map((period) {
                                final isSelected = _trendPeriod.toLowerCase() == period.toLowerCase();
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => _trendPeriod = period);
                                      context.read<DashboardBloc>().add(ChangeLeadTrendPeriod(period));
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: isSelected
                                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                            : null,
                                      ),
                                      child: Text(
                                        period.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TrendLineChart(activePeriod: _trendPeriod, trendData: leadTrendData),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 3. SALES PIPELINE ────────────────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.salesPipeline)) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.filter_alt_outlined, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Sales Pipeline',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          PipelineBarChart(items: chartsData.salesPipeline),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 4. LEAD STATUS DISTRIBUTION ──────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.leadStatusDistribution)) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.pie_chart_outline, color: Color(0xFF10B981), size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Lead Status Distribution',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DonutChartWidget(
                            title: 'Status',
                            segments: _buildStatusSegments(chartsData.statusDistribution),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 5. LEAD SOURCE DISTRIBUTION ──────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.leadSourceDistribution)) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.share_outlined, color: Color(0xFF8B5CF6), size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Lead Source Distribution',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DonutChartWidget(
                            title: 'Source',
                            segments: _buildSourceSegments(chartsData.sourceDistribution),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 6. MONTHLY REVENUE TARGET ─────────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.monthlyRevenueTarget)) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFF59E0B), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Monthly Revenue Target',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          MonthlyRevenueTargetCard(targetData: revenueTarget),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 7. UPCOMING FOLLOW-UPS ───────────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.upcomingFollowups) || visibleWidgets.contains('UPCOMING_FOLLOWUPS')) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.access_time_outlined, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Upcoming Follow-ups',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildUpcomingFollowupsList(upcomingFollowups),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 8. RECENT ACTIVITIES ─────────────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.recentActivities)) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.history_outlined, color: Color(0xFF8B5CF6), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Recent Activities',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildRecentActivitiesTimeline(recentActivities),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── 9. RECENT LEADS ───────────────────────────────────────────
                  if (visibleWidgets.contains(DashboardWidgetKeys.recentLeads) || visibleWidgets.contains('RECENT_LEADS')) ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.person_add_outlined, color: Color(0xFF10B981), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Recent Leads',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildRecentLeadsList(recentLeads),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<DonutSegment> _buildStatusSegments(List<StatusDistributionItem> items) {
    if (items.isEmpty) return [];
    const colors = [
      Color(0xFFFF6600),
      Color(0xFFFB923C),
      Color(0xFF3B82F6),
      Color(0xFF06B6D4),
      Color(0xFFF97316),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
    ];
    return items.asMap().entries.map((e) {
      final idx = e.key;
      final item = e.value;
      return DonutSegment(
        label: item.statusName,
        value: item.count.toDouble(),
        color: colors[idx % colors.length],
      );
    }).toList();
  }

  List<DonutSegment> _buildSourceSegments(List<SourceDistributionItem> items) {
    if (items.isEmpty) return [];
    const colors = [
      Color(0xFF4285F4),
      Color(0xFF34A853),
      Color(0xFF1877F2),
      Color(0xFFFBBC05),
      Color(0xFFEA4335),
      Color(0xFF8B5CF6),
    ];
    return items.asMap().entries.map((e) {
      final idx = e.key;
      final item = e.value;
      return DonutSegment(
        label: item.sourceName,
        value: item.count.toDouble(),
        color: colors[idx % colors.length],
      );
    }).toList();
  }

  bool _hasAnyStatCardVisible(List<String> visibleWidgets) {
    if (visibleWidgets.contains('SUMMARY_METRICS')) return true;
    const statKeys = [
      DashboardWidgetKeys.totalLeads,
      DashboardWidgetKeys.newLeadsToday,
      DashboardWidgetKeys.qualifiedLeads,
      DashboardWidgetKeys.lostLeads,
      DashboardWidgetKeys.todaysFollowups,
      DashboardWidgetKeys.overdueFollowups,
      DashboardWidgetKeys.revenueThisMonth,
      DashboardWidgetKeys.conversionRate,
    ];
    return statKeys.any((key) => visibleWidgets.contains(key));
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderEnabled),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatCardsGrid(List<String> visibleWidgets, SummaryMetrics metrics) {
    final showAll = visibleWidgets.contains('SUMMARY_METRICS');

    final List<Map<String, dynamic>> allStats = [
      {
        'key': DashboardWidgetKeys.totalLeads,
        'title': 'TOTAL LEADS',
        'value': '${metrics.totalLeads}',
        'icon': Icons.people_alt_outlined,
        'iconBg': const Color(0xFFDBEAFE),
        'iconColor': const Color(0xFF2563EB),
      },
      {
        'key': DashboardWidgetKeys.newLeadsToday,
        'title': 'NEW LEADS TODAY',
        'value': '${metrics.newLeadsToday}',
        'icon': Icons.person_add_alt_1_outlined,
        'iconBg': const Color(0xFFD1FAE5),
        'iconColor': const Color(0xFF10B981),
      },
      {
        'key': DashboardWidgetKeys.qualifiedLeads,
        'title': 'QUALIFIED LEADS',
        'value': '${metrics.qualifiedLeads}',
        'icon': Icons.verified_user_outlined,
        'iconBg': const Color(0xFFEDE9FE),
        'iconColor': const Color(0xFF8B5CF6),
      },
      {
        'key': DashboardWidgetKeys.lostLeads,
        'title': 'LOST LEADS',
        'value': '${metrics.lostLeads}',
        'icon': Icons.cancel_outlined,
        'iconBg': const Color(0xFFFEE2E2),
        'iconColor': const Color(0xFFEF4444),
      },
      {
        'key': DashboardWidgetKeys.todaysFollowups,
        'title': 'TODAY\'S FOLLOW-UPS',
        'value': '${metrics.todaysFollowups}',
        'icon': Icons.access_time_outlined,
        'iconBg': const Color(0xFFE0E7FF),
        'iconColor': const Color(0xFF6366F1),
      },
      {
        'key': DashboardWidgetKeys.overdueFollowups,
        'title': 'OVERDUE FOLLOW-UPS',
        'value': '${metrics.overdueFollowups}',
        'icon': Icons.warning_amber_rounded,
        'iconBg': const Color(0xFFFFE4E6),
        'iconColor': const Color(0xFFF43F5E),
      },
      {
        'key': DashboardWidgetKeys.revenueThisMonth,
        'title': 'REVENUE THIS MONTH',
        'value': '₹${metrics.revenueThisMonth.toInt()}',
        'icon': Icons.currency_rupee,
        'iconBg': const Color(0xFFA7F3D0),
        'iconColor': const Color(0xFF059669),
      },
      {
        'key': DashboardWidgetKeys.conversionRate,
        'title': 'CONVERSION RATE',
        'value': '${metrics.conversionRate.toStringAsFixed(1)}%',
        'icon': Icons.trending_up,
        'iconBg': const Color(0xFFCFFAFE),
        'iconColor': const Color(0xFF06B6D4),
      },
    ];

    final visibleStats = allStats.where((s) => showAll || visibleWidgets.contains(s['key'])).toList();

    if (visibleStats.isEmpty) return const SizedBox();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.85,
      ),
      itemCount: visibleStats.length,
      itemBuilder: (context, index) {
        final stat = visibleStats[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderEnabled),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: stat['iconBg'] as Color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(stat['icon'] as IconData, size: 20, color: stat['iconColor'] as Color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textHint,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stat['value'] as String,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpcomingFollowupsList(List<DashboardUpcomingFollowup> followups) {
    if (followups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Text(
            'No upcoming follow-ups scheduled.',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: followups.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderEnabled),
      itemBuilder: (context, index) {
        final item = followups[index];
        final initial = item.leadName.isNotEmpty ? item.leadName[0].toUpperCase() : 'F';
        final timeStr = '${item.followUpDate} ${item.followUpTime}'.trim();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  initial,
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.leadName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    Text(
                      '${item.companyName.isNotEmpty ? "${item.companyName} • " : ""}$timeStr',
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.followUpStatus.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentActivitiesTimeline(List<DashboardRecentActivity> activities) {
    if (activities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Text(
            'No recent activities recorded.',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      children: activities.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final isLast = idx == activities.length - 1;

        final userOrLead = item.performedBy.isNotEmpty ? item.performedBy : (item.leadName.isNotEmpty ? item.leadName : 'System');
        final details = item.description.isNotEmpty ? item.description : (item.leadName.isNotEmpty ? 'Updated details for ${item.leadName}' : 'Lead updated');

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Icon(Icons.history_outlined, size: 16, color: Color(0xFF2563EB)),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : AppColors.borderEnabled,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            userOrLead,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                          ),
                          Text(
                            item.timestamp,
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.actionType.isNotEmpty && item.actionType.toUpperCase() != 'UPDATE') ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Text(
                                item.actionType.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              details,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentLeadsList(List<DashboardRecentLead> leads) {
    if (leads.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Text(
            'No recent leads found.',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FixedColumnWidth(160), // Name
          1: FixedColumnWidth(120), // Company
          2: FixedColumnWidth(130), // Phone
          3: FixedColumnWidth(120), // Status
          4: FixedColumnWidth(130), // Assigned User
          5: FixedColumnWidth(110), // Created Date
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            children: [
              _buildTableHeaderCell('Name'),
              _buildTableHeaderCell('Company'),
              _buildTableHeaderCell('Phone'),
              _buildTableHeaderCell('Status'),
              _buildTableHeaderCell('Assigned User'),
              _buildTableHeaderCell('Created Date'),
            ],
          ),
          ...leads.map((lead) {
            final statusColor = _hexToColor(lead.statusColor);
            final name = lead.fullName.isNotEmpty ? lead.fullName : '—';
            final company = lead.companyName.isNotEmpty ? lead.companyName : '—';
            final phone = lead.phoneNumber.isNotEmpty ? lead.phoneNumber : '—';
            final assigned = lead.assignedUser.isNotEmpty ? lead.assignedUser : 'Unassigned';
            final created = lead.createdAt.isNotEmpty ? lead.createdAt : '—';

            return TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    company,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    phone,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        lead.statusName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    assigned,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    created,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String title) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFFEF4444),
        ),
      ),
    );
  }
}
