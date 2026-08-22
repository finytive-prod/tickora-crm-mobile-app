import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/repositories/dashboard_repository.dart';
import 'package:crm_mobile/models/dashboard_models.dart';
import 'package:crm_mobile/blocs/dashboard_event.dart';
import 'package:crm_mobile/blocs/dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository repository;

  DashboardBloc({
    required this.repository,
  }) : super(DashboardInitial()) {
    on<FetchDashboardPreferences>(_onFetchDashboardPreferences);
    on<UpdateDashboardPreferences>(_onUpdateDashboardPreferences);
    on<ChangeLeadTrendPeriod>(_onChangeLeadTrendPeriod);
  }

  Future<void> _onFetchDashboardPreferences(
    FetchDashboardPreferences event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading());

    final visibleWidgetsFuture = repository.getDashboardPreferences();
    final summaryMetricsFuture = repository.getSummaryMetrics();
    final chartsDataFuture = repository.getChartsData();
    final leadTrendFuture = repository.getLeadTrend(event.trendPeriod);
    final recentLeadsFuture = repository.getRecentLeads();
    final upcomingFollowupsFuture = repository.getUpcomingFollowups();
    final recentActivitiesFuture = repository.getRecentActivities();
    final revenueTargetFuture = repository.getRevenueTarget();

    final visibleWidgetsRes = await visibleWidgetsFuture;
    final summaryMetricsRes = await summaryMetricsFuture;
    final chartsDataRes = await chartsDataFuture;
    final leadTrendRes = await leadTrendFuture;
    final recentLeadsRes = await recentLeadsFuture;
    final upcomingFollowupsRes = await upcomingFollowupsFuture;
    final recentActivitiesRes = await recentActivitiesFuture;
    final revenueTargetRes = await revenueTargetFuture;

    final visibleWidgets = visibleWidgetsRes.fold(
      (_) => DashboardWidgetKeys.allKeys,
      (w) => w.isEmpty ? DashboardWidgetKeys.allKeys : w,
    );

    final summaryMetrics = summaryMetricsRes.fold((_) => SummaryMetrics(), (data) => data);
    final chartsData = chartsDataRes.fold((_) => ChartsData(statusDistribution: [], sourceDistribution: [], salesPipeline: []), (data) => data);
    final leadTrendData = leadTrendRes.fold((_) => LeadTrendData(leadsCreated: [], leadsWon: []), (data) => data);
    final recentLeads = recentLeadsRes.fold((_) => <DashboardRecentLead>[], (data) => data);
    final upcomingFollowups = upcomingFollowupsRes.fold((_) => <DashboardUpcomingFollowup>[], (data) => data);
    final recentActivities = recentActivitiesRes.fold((_) => <DashboardRecentActivity>[], (data) => data);
    final revenueTarget = revenueTargetRes.fold((_) => RevenueTargetData(), (data) => data);

    emit(DashboardLoaded(
      visibleWidgets: visibleWidgets,
      summaryMetrics: summaryMetrics,
      chartsData: chartsData,
      leadTrendData: leadTrendData,
      recentLeads: recentLeads,
      upcomingFollowups: upcomingFollowups,
      recentActivities: recentActivities,
      revenueTarget: revenueTarget,
      activeTrendPeriod: event.trendPeriod,
    ));
  }

  Future<void> _onChangeLeadTrendPeriod(
    ChangeLeadTrendPeriod event,
    Emitter<DashboardState> emit,
  ) async {
    if (state is DashboardLoaded) {
      final currentState = state as DashboardLoaded;
      final trendRes = await repository.getLeadTrend(event.period);
      trendRes.fold(
        (_) {},
        (newTrend) {
          emit(currentState.copyWith(
            leadTrendData: newTrend,
            activeTrendPeriod: event.period,
          ));
        },
      );
    }
  }

  Future<void> _onUpdateDashboardPreferences(
    UpdateDashboardPreferences event,
    Emitter<DashboardState> emit,
  ) async {
    List<String> currentWidgets = DashboardWidgetKeys.allKeys;
    DashboardLoaded? loadedState;
    if (state is DashboardLoaded) {
      loadedState = state as DashboardLoaded;
      currentWidgets = loadedState.visibleWidgets;
    }
    emit(DashboardUpdating(currentWidgets));

    final result = await repository.updateDashboardPreferences(event.visibleWidgets);
    result.fold(
      (failure) => emit(DashboardError(failure.message)),
      (_) {
        if (loadedState != null) {
          emit(loadedState.copyWith(visibleWidgets: event.visibleWidgets));
        } else {
          add(const FetchDashboardPreferences());
        }
      },
    );
  }
}
