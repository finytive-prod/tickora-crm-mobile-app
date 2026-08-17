import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/calendar_repository.dart';
import 'package:crm_mobile/models/calendar_event_model.dart';

class GetCalendarEventsUseCase {
  final CalendarRepository repository;

  GetCalendarEventsUseCase(this.repository);

  Future<Either<Failure, List<CalendarEventModel>>> call(String start, String end) async {
    final result = await repository.getCalendarEvents(start, end);
    return result.bind((dataList) {
      try {
        final events = dataList.map((e) => CalendarEventModel.fromJson(e)).toList();
        return Right(events);
      } catch (e) {
        return const Left(ServerFailure('Failed to parse calendar events'));
      }
    });
  }
}
