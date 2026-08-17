import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetCustomFieldsListUseCase {
  final SettingsRepository repository;

  GetCustomFieldsListUseCase(this.repository);

  Future<Either<Failure, List<CustomField>>> call() async {
    return await repository.getCustomFields();
  }
}
