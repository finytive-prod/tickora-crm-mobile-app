import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/calendar_repository.dart';

class CreateCalendarEventUseCase {
  final CalendarRepository repository;

  CreateCalendarEventUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> data) async {
    return await repository.createEvent(data);
  }
}
