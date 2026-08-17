import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class CreateRoleUseCase {
  final SettingsRepository repository;

  CreateRoleUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> roleData) async {
    return await repository.createRole(roleData);
  }
}
