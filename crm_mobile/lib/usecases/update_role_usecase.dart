import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class UpdateRoleUseCase {
  final SettingsRepository repository;

  UpdateRoleUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, Map<String, dynamic> roleData) async {
    return await repository.updateRole(id, roleData);
  }
}
