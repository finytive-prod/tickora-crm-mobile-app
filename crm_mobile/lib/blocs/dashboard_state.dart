import 'package:equatable/equatable.dart';
import 'package:crm_mobile/models/dashboard_models.dart';

abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {}

class DashboardLoading extends DashboardState {}

class DashboardLoaded extends DashboardState {
  final List<String> visibleWidgets;
  final SummaryMetrics summaryMetrics;
  final ChartsData chartsData;
  final LeadTrendData leadTrendData;
  final List<DashboardRecentLead> recentLeads;
  final List<DashboardUpcomingFollowup> upcomingFollowups;
  final List<DashboardRecentActivity> recentActivities;
  final RevenueTargetData revenueTarget;
  final String activeTrendPeriod;

  const DashboardLoaded({
    required this.visibleWidgets,
    required this.summaryMetrics,
    required this.chartsData,
    required this.leadTrendData,
    required this.recentLeads,
    required this.upcomingFollowups,
    required this.recentActivities,
    required this.revenueTarget,
    this.activeTrendPeriod = 'weekly',
  });

  DashboardLoaded copyWith({
    List<String>? visibleWidgets,
    SummaryMetrics? summaryMetrics,
    ChartsData? chartsData,
    LeadTrendData? leadTrendData,
    List<DashboardRecentLead>? recentLeads,
    List<DashboardUpcomingFollowup>? upcomingFollowups,
    List<DashboardRecentActivity>? recentActivities,
    RevenueTargetData? revenueTarget,
    String? activeTrendPeriod,
  }) {
    return DashboardLoaded(
      visibleWidgets: visibleWidgets ?? this.visibleWidgets,
      summaryMetrics: summaryMetrics ?? this.summaryMetrics,
      chartsData: chartsData ?? this.chartsData,
      leadTrendData: leadTrendData ?? this.leadTrendData,
      recentLeads: recentLeads ?? this.recentLeads,
      upcomingFollowups: upcomingFollowups ?? this.upcomingFollowups,
      recentActivities: recentActivities ?? this.recentActivities,
      revenueTarget: revenueTarget ?? this.revenueTarget,
      activeTrendPeriod: activeTrendPeriod ?? this.activeTrendPeriod,
    );
  }

  @override
  List<Object?> get props => [
        visibleWidgets,
        summaryMetrics,
        chartsData,
        leadTrendData,
        recentLeads,
        upcomingFollowups,
        recentActivities,
        revenueTarget,
        activeTrendPeriod,
      ];
}

class DashboardUpdating extends DashboardState {
  final List<String> currentWidgets;

  const DashboardUpdating(this.currentWidgets);

  @override
  List<Object?> get props => [currentWidgets];
}

class DashboardUpdateSuccess extends DashboardState {
  final List<String> visibleWidgets;

  const DashboardUpdateSuccess(this.visibleWidgets);

  @override
  List<Object?> get props => [visibleWidgets];
}

class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}
