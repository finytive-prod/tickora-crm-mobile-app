import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/role_entity.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetRoleDetailsUseCase {
  final SettingsRepository repository;

  GetRoleDetailsUseCase(this.repository);

  Future<Either<Failure, RoleDetail>> call(String id) async {
    return await repository.getRoleDetails(id);
  }
}
