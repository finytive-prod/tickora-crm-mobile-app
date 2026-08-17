import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/calendar_event.dart';
import 'package:crm_mobile/blocs/calendar_state.dart';
import 'package:crm_mobile/usecases/get_calendar_categories_usecase.dart';
import 'package:crm_mobile/usecases/create_calendar_event_usecase.dart';
import 'package:crm_mobile/usecases/update_calendar_event_usecase.dart';
import 'package:crm_mobile/usecases/get_calendar_events_usecase.dart';
import 'package:crm_mobile/usecases/delete_calendar_event_usecase.dart';

class CalendarBloc extends Bloc<CalendarEvent, CalendarState> {
  final GetCalendarCategoriesUseCase getCalendarCategoriesUseCase;
  final CreateCalendarEventUseCase createCalendarEventUseCase;
  final UpdateCalendarEventUseCase updateCalendarEventUseCase;
  final GetCalendarEventsUseCase getCalendarEventsUseCase;
  final DeleteCalendarEventUseCase deleteCalendarEventUseCase;

  CalendarBloc({
    required this.getCalendarCategoriesUseCase,
    required this.createCalendarEventUseCase,
    required this.updateCalendarEventUseCase,
    required this.getCalendarEventsUseCase,
    required this.deleteCalendarEventUseCase,
  }) : super(CalendarInitial()) {
    on<FetchCalendarCategories>(_onFetchCalendarCategories);
    on<CreateCalendarEvent>(_onCreateCalendarEvent);
    on<UpdateCalendarEvent>(_onUpdateCalendarEvent);
    on<FetchCalendarEvents>(_onFetchCalendarEvents);
    on<DeleteCalendarEvent>(_onDeleteCalendarEvent);
  }

  Future<void> _onFetchCalendarCategories(FetchCalendarCategories event, Emitter<CalendarState> emit) async {
    emit(CalendarLoading());
    final result = await getCalendarCategoriesUseCase();
    result.fold(
      (failure) => emit(CalendarError(message: failure.message)),
      (categories) => emit(CalendarCategoriesLoaded(categories: categories)),
    );
  }

  Future<void> _onCreateCalendarEvent(CreateCalendarEvent event, Emitter<CalendarState> emit) async {
    emit(CalendarActionLoading());
    final result = await createCalendarEventUseCase(event.data);
    result.fold(
      (failure) => emit(CalendarActionFailure(failure.message)),
      (_) => emit(const CalendarActionSuccess('Event created successfully')),
    );
  }

  Future<void> _onUpdateCalendarEvent(UpdateCalendarEvent event, Emitter<CalendarState> emit) async {
    emit(CalendarActionLoading());
    final result = await updateCalendarEventUseCase(event.id, event.data);
    result.fold(
      (failure) => emit(CalendarActionFailure(failure.message)),
      (_) => emit(const CalendarActionSuccess('Event updated successfully')),
    );
  }

  Future<void> _onFetchCalendarEvents(FetchCalendarEvents event, Emitter<CalendarState> emit) async {
    emit(CalendarLoading());
    final startStr = event.start.toIso8601String().substring(0, 19);
    final endStr = event.end.toIso8601String().substring(0, 19);
    
    final result = await getCalendarEventsUseCase(startStr, endStr);
    result.fold(
      (failure) => emit(CalendarError(message: failure.message)),
      (events) => emit(CalendarEventsLoaded(events: events)),
    );
  }

  Future<void> _onDeleteCalendarEvent(DeleteCalendarEvent event, Emitter<CalendarState> emit) async {
    emit(CalendarActionLoading());
    final result = await deleteCalendarEventUseCase(event.id);
    result.fold(
      (failure) => emit(CalendarActionFailure(failure.message)),
      (_) => emit(const CalendarActionSuccess('Event deleted successfully')),
    );
  }
}
