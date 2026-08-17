import 'package:equatable/equatable.dart';

abstract class CalendarState extends Equatable {
  const CalendarState();

  @override
  List<Object> get props => [];
}

class CalendarInitial extends CalendarState {}

class CalendarLoading extends CalendarState {}

class CalendarEventsLoaded extends CalendarState {
  final List<dynamic> events;

  const CalendarEventsLoaded({required this.events});

  @override
  List<Object> get props => [events];
}

class CalendarCategoriesLoaded extends CalendarState {
  final List<String> categories;

  const CalendarCategoriesLoaded({required this.categories});

  @override
  List<Object> get props => [categories];
}

class CalendarError extends CalendarState {
  final String message;

  const CalendarError({required this.message});

  @override
  List<Object> get props => [message];
}

class CalendarActionLoading extends CalendarState {}

class CalendarActionSuccess extends CalendarState {
  final String message;

  const CalendarActionSuccess(this.message);

  @override
  List<Object> get props => [message];
}

class CalendarActionFailure extends CalendarState {
  final String message;

  const CalendarActionFailure(this.message);

  @override
  List<Object> get props => [message];
}
