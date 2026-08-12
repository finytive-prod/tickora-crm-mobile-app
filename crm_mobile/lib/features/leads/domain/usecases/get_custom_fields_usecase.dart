import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/custom_field.dart';
import '../repositories/leads_repository.dart';

class GetCustomFieldsUseCase {
  final LeadsRepository repository;

  GetCustomFieldsUseCase(this.repository);

  Future<Either<Failure, List<CustomField>>> call() async {
    return await repository.getCustomFieldsForm();
  }
}
