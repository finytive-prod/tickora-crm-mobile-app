import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/dashboard_models.dart';

class DashboardWidgetKeys {
  static const String totalLeads = "TOTAL_LEADS";
  static const String newLeadsToday = "NEW_LEADS_TODAY";
  static const String qualifiedLeads = "QUALIFIED_LEADS";
  static const String lostLeads = "LOST_LEADS";
  static const String todaysFollowups = "TODAYS_FOLLOWUPS";
  static const String overdueFollowups = "OVERDUE_FOLLOWUPS";
  static const String revenueThisMonth = "REVENUE_THIS_MONTH";
  static const String conversionRate = "CONVERSION_RATE";
  static const String leadTrendAnalysis = "LEAD_TREND_ANALYSIS";
  static const String salesPipeline = "SALES_PIPELINE";
  static const String leadStatusDistribution = "LEAD_STATUS_DISTRIBUTION";
  static const String leadSourceDistribution = "LEAD_SOURCE_DISTRIBUTION";
  static const String monthlyRevenueTarget = "MONTHLY_REVENUE_TARGET";
  static const String upcomingFollowups = "UPCOMING_FOLLOWUPS";
  static const String recentLeads = "RECENT_LEADS";
  static const String recentActivities = "RECENT_ACTIVITIES";

  static const List<String> allKeys = [
    totalLeads,
    newLeadsToday,
    qualifiedLeads,
    lostLeads,
    todaysFollowups,
    overdueFollowups,
    revenueThisMonth,
    conversionRate,
    leadTrendAnalysis,
    salesPipeline,
    leadStatusDistribution,
    leadSourceDistribution,
    monthlyRevenueTarget,
    upcomingFollowups,
    recentLeads,
    recentActivities,
  ];

  static Map<String, String> keyTitles = {
    totalLeads: "Total Leads Card",
    newLeadsToday: "New Leads Today Card",
    qualifiedLeads: "Qualified Leads Card",
    lostLeads: "Lost Leads Card",
    todaysFollowups: "Today's Follow-ups Card",
    overdueFollowups: "Overdue Follow-ups Card",
    revenueThisMonth: "Revenue This Month Card",
    conversionRate: "Conversion Rate Card",
    leadTrendAnalysis: "Lead Trend Analysis Chart",
    salesPipeline: "Sales Pipeline Chart",
    leadStatusDistribution: "Lead Status Distribution Donut",
    leadSourceDistribution: "Lead Source Distribution Donut",
    monthlyRevenueTarget: "Monthly Revenue Target Progress",
    upcomingFollowups: "Upcoming Follow-ups List",
    recentLeads: "Recent Leads List",
    recentActivities: "Recent Activities Timeline",
  };
}

abstract class DashboardRepository {
  Future<Either<Failure, List<String>>> getDashboardPreferences();
  Future<Either<Failure, void>> updateDashboardPreferences(List<String> visibleWidgets);
  Future<Either<Failure, List<DashboardWidgetInfo>>> getAllWidgets();

  Future<Either<Failure, SummaryMetrics>> getSummaryMetrics();
  Future<Either<Failure, ChartsData>> getChartsData();
  Future<Either<Failure, LeadTrendData>> getLeadTrend(String period);
  Future<Either<Failure, List<DashboardRecentLead>>> getRecentLeads();
  Future<Either<Failure, List<DashboardUpcomingFollowup>>> getUpcomingFollowups();
  Future<Either<Failure, List<DashboardRecentActivity>>> getRecentActivities();
  Future<Either<Failure, RevenueTargetData>> getRevenueTarget();

}

class DashboardRepositoryImpl implements DashboardRepository {
  final ApiClient apiClient;

  DashboardRepositoryImpl({required this.apiClient});

  String _getDashboardBaseUrl() {
    final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
    return '$leadsBaseUrl/dashboard';
  }

  String _getIdentityBaseUrl() {
    final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
    if (leadsBaseUrl.contains('lead-service')) {
      return leadsBaseUrl.replaceAll('lead-service', 'identity-service');
    }
    return leadsBaseUrl;
  }

  @override
  Future<Either<Failure, List<String>>> getDashboardPreferences() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/widgets/me');

    try {
      final response = await apiClient.get('$dashboardBaseUrl/widgets/me');
      debugPrint('[DashboardRepo] widgets/me status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        final rawData = body['data'];
        List<String> parsed = [];
        if (rawData is List) {
          parsed = rawData.map((e) => e.toString()).toList();
        } else if (rawData is String) {
          final List<dynamic> jsonList = jsonDecode(rawData);
          parsed = jsonList.map((e) => e.toString()).toList();
        }
        if (parsed.isNotEmpty) return Right(parsed);
      }
    } catch (e) {
      debugPrint('[DashboardRepo] widgets/me error: $e');
    }

    // Try fallback
    try {
      final identityBaseUrl = _getIdentityBaseUrl();
      debugPrint('[DashboardRepo] Fallback GET $identityBaseUrl/users/me/preferences/DASHBOARD_WIDGETS');
      final response = await apiClient.get('$identityBaseUrl/users/me/preferences/DASHBOARD_WIDGETS');
      final body = response.data;
      if (body != null && body['data'] != null) {
        final rawData = body['data'];
        List<String> parsedWidgets = [];
        if (rawData is String) {
          final List<dynamic> jsonList = jsonDecode(rawData);
          parsedWidgets = jsonList.map((e) => e.toString()).toList();
        } else if (rawData is List) {
          parsedWidgets = rawData.map((e) => e.toString()).toList();
        }
        if (parsedWidgets.isNotEmpty) {
          return Right(parsedWidgets);
        }
      }
    } catch (e) {
      debugPrint('[DashboardRepo] identity preferences error: $e');
    }

    return const Right(DashboardWidgetKeys.allKeys);
  }

  @override
  Future<Either<Failure, void>> updateDashboardPreferences(List<String> visibleWidgets) async {
    final identityBaseUrl = _getIdentityBaseUrl();
    final payload = {
      'preferenceKey': 'DASHBOARD_WIDGETS',
      'preferenceValue': jsonEncode(visibleWidgets),
    };

    debugPrint('[DashboardRepo] Calling PUT $identityBaseUrl/user-preferences with $payload');
    try {
      try {
        await apiClient.put('$identityBaseUrl/user-preferences', data: payload);
      } catch (_) {
        await apiClient.put('$identityBaseUrl/users/me/preferences', data: payload);
      }
      return const Right(null);
    } catch (e) {
      debugPrint('[DashboardRepo] updatePreferences error: $e');
      return Left(ErrorHandler.mapExceptionToFailure(e as Exception));
    }
  }

  @override
  Future<Either<Failure, List<DashboardWidgetInfo>>> getAllWidgets() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/widgets/all');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/widgets/all');
      debugPrint('[DashboardRepo] widgets/all status: ${response.statusCode}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        final List<dynamic> list = body['data'];
        return Right(list.map((e) => DashboardWidgetInfo.fromJson(e as Map<String, dynamic>)).toList());
      }
      return const Right([]);
    } catch (e) {
      debugPrint('[DashboardRepo] widgets/all error: $e');
      return const Right([]);
    }
  }

  @override
  Future<Either<Failure, SummaryMetrics>> getSummaryMetrics() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/summary-metrics');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/summary-metrics');
      debugPrint('[DashboardRepo] summary-metrics status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        return Right(SummaryMetrics.fromJson(body['data'] as Map<String, dynamic>));
      }
      return Right(SummaryMetrics());
    } catch (e) {
      debugPrint('[DashboardRepo] summary-metrics error: $e');
      return Right(SummaryMetrics());
    }
  }

  @override
  Future<Either<Failure, ChartsData>> getChartsData() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/charts');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/charts');
      debugPrint('[DashboardRepo] charts status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        return Right(ChartsData.fromJson(body['data'] as Map<String, dynamic>));
      }
      return Right(ChartsData(statusDistribution: [], sourceDistribution: [], salesPipeline: []));
    } catch (e) {
      debugPrint('[DashboardRepo] charts error: $e');
      return Right(ChartsData(statusDistribution: [], sourceDistribution: [], salesPipeline: []));
    }
  }

  @override
  Future<Either<Failure, LeadTrendData>> getLeadTrend(String period) async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/trend?period=$period');
    try {
      final response = await apiClient.get(
        '$dashboardBaseUrl/trend',
        queryParameters: {'period': period.toLowerCase()},
      );
      debugPrint('[DashboardRepo] trend status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        return Right(LeadTrendData.fromJson(body['data'] as Map<String, dynamic>));
      }
      return Right(LeadTrendData(leadsCreated: [], leadsWon: []));
    } catch (e) {
      debugPrint('[DashboardRepo] trend error: $e');
      return Right(LeadTrendData(leadsCreated: [], leadsWon: []));
    }
  }

  @override
  Future<Either<Failure, List<DashboardRecentLead>>> getRecentLeads() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/recent-leads');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/recent-leads');
      debugPrint('[DashboardRepo] recent-leads status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        final List<dynamic> list = body['data'];
        return Right(list.map((e) => DashboardRecentLead.fromJson(e as Map<String, dynamic>)).toList());
      }
      return const Right([]);
    } catch (e) {
      debugPrint('[DashboardRepo] recent-leads error: $e');
      return const Right([]);
    }
  }

  @override
  Future<Either<Failure, List<DashboardUpcomingFollowup>>> getUpcomingFollowups() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/upcoming-followups');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/upcoming-followups');
      debugPrint('[DashboardRepo] upcoming-followups status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        final List<dynamic> list = body['data'];
        return Right(list.map((e) => DashboardUpcomingFollowup.fromJson(e as Map<String, dynamic>)).toList());
      }
      return const Right([]);
    } catch (e) {
      debugPrint('[DashboardRepo] upcoming-followups error: $e');
      return const Right([]);
    }
  }

  @override
  Future<Either<Failure, List<DashboardRecentActivity>>> getRecentActivities() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/recent-activities');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/recent-activities');
      debugPrint('[DashboardRepo] recent-activities status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        final List<dynamic> list = body['data'];
        return Right(list.map((e) => DashboardRecentActivity.fromJson(e as Map<String, dynamic>)).toList());
      }
      return const Right([]);
    } catch (e) {
      debugPrint('[DashboardRepo] recent-activities error: $e');
      return const Right([]);
    }
  }

  @override
  Future<Either<Failure, RevenueTargetData>> getRevenueTarget() async {
    final dashboardBaseUrl = _getDashboardBaseUrl();
    debugPrint('[DashboardRepo] Calling GET $dashboardBaseUrl/revenue-target');
    try {
      final response = await apiClient.get('$dashboardBaseUrl/revenue-target');
      debugPrint('[DashboardRepo] revenue-target status: ${response.statusCode}, data: ${response.data}');
      final body = response.data;
      if (body != null && body['data'] != null) {
        return Right(RevenueTargetData.fromJson(body['data'] as Map<String, dynamic>));
      }
      return Right(RevenueTargetData());
    } catch (e) {
      debugPrint('[DashboardRepo] revenue-target error: $e');
      return Right(RevenueTargetData());
    }
  }
}
