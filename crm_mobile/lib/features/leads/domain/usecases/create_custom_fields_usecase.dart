import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class CreateCustomFieldsUseCase {
  final LeadsRepository repository;

  CreateCustomFieldsUseCase(this.repository);

  Future<Either<Failure, void>> call(List<Map<String, dynamic>> fields) async {
    return await repository.createCustomFields(fields);
  }
}
