import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/calendar_repository.dart';

class GetCalendarCategoriesUseCase {
  final CalendarRepository repository;

  GetCalendarCategoriesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() async {
    return await repository.getCalendarCategories();
  }
}
