import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class CreateLeadSourceUseCase {
  final SettingsRepository repository;

  CreateLeadSourceUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> sourceData) async {
    return await repository.createLeadSource(sourceData);
  }
}
