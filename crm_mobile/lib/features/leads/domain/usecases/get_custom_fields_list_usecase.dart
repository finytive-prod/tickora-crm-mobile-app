import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/custom_field.dart';
import '../repositories/leads_repository.dart';

class GetCustomFieldsListUseCase {
  final LeadsRepository repository;

  GetCustomFieldsListUseCase(this.repository);

  Future<Either<Failure, List<CustomField>>> call() async {
    return await repository.getCustomFields();
  }
}
