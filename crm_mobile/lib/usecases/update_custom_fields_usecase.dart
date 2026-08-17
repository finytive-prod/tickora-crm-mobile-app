import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class UpdateCustomFieldsUseCase {
  final SettingsRepository repository;

  UpdateCustomFieldsUseCase(this.repository);

  Future<Either<Failure, void>> call(List<Map<String, dynamic>> fields) async {
    return await repository.updateCustomFields(fields);
  }
}
