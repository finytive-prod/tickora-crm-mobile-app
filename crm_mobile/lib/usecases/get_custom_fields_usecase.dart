import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetCustomFieldsUseCase {
  final SettingsRepository repository;

  GetCustomFieldsUseCase(this.repository);

  Future<Either<Failure, List<CustomField>>> call() async {
    return await repository.getCustomFieldsForm();
  }
}
