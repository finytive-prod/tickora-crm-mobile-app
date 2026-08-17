import 'package:equatable/equatable.dart';

abstract class CalendarEvent extends Equatable {
  const CalendarEvent();

  @override
  List<Object> get props => [];
}

class FetchCalendarCategories extends CalendarEvent {}

class CreateCalendarEvent extends CalendarEvent {
  final Map<String, dynamic> data;

  const CreateCalendarEvent(this.data);

  @override
  List<Object> get props => [data];
}

class UpdateCalendarEvent extends CalendarEvent {
  final String id;
  final String? originalId; // Optional for tracking purposes
  final Map<String, dynamic> data;

  const UpdateCalendarEvent(this.id, this.data, {this.originalId});

  @override
  List<Object> get props => [id, data];
}

class FetchCalendarEvents extends CalendarEvent {
  final DateTime start;
  final DateTime end;

  const FetchCalendarEvents({required this.start, required this.end});

  @override
  List<Object> get props => [start, end];
}

class DeleteCalendarEvent extends CalendarEvent {
  final String id;

  const DeleteCalendarEvent(this.id);

  @override
  List<Object> get props => [id];
}
