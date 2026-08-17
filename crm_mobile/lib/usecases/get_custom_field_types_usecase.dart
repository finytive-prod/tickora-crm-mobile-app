import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetCustomFieldTypesUseCase {
  final SettingsRepository repository;

  GetCustomFieldTypesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() async {
    return await repository.getCustomFieldTypes();
  }
}
