import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/calendar_repository.dart';

class DeleteCalendarEventUseCase {
  final CalendarRepository repository;

  DeleteCalendarEventUseCase(this.repository);

  Future<Either<Failure, void>> call(String id) {
    return repository.deleteEvent(id);
  }
}
