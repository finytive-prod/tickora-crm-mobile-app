import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/calendar_repository.dart';

class UpdateCalendarEventUseCase {
  final CalendarRepository repository;

  UpdateCalendarEventUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, Map<String, dynamic> data) async {
    return await repository.updateEvent(id, data);
  }
}
