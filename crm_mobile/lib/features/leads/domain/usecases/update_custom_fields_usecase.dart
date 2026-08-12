import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class UpdateCustomFieldsUseCase {
  final LeadsRepository repository;

  UpdateCustomFieldsUseCase(this.repository);

  Future<Either<Failure, void>> call(List<Map<String, dynamic>> fields) async {
    return await repository.updateCustomFields(fields);
  }
}
