import 'package:equatable/equatable.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

class FetchDashboardPreferences extends DashboardEvent {
  final String trendPeriod;
  const FetchDashboardPreferences({this.trendPeriod = 'weekly'});

  @override
  List<Object?> get props => [trendPeriod];
}

class UpdateDashboardPreferences extends DashboardEvent {
  final List<String> visibleWidgets;

  const UpdateDashboardPreferences(this.visibleWidgets);

  @override
  List<Object?> get props => [visibleWidgets];
}

class ChangeLeadTrendPeriod extends DashboardEvent {
  final String period;

  const ChangeLeadTrendPeriod(this.period);

  @override
  List<Object?> get props => [period];
}
