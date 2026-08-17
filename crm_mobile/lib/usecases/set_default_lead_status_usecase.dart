import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class SetDefaultLeadStatusUseCase {
  final SettingsRepository repository;

  SetDefaultLeadStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(String id) async {
    return await repository.setDefaultLeadStatus(id);
  }
}
