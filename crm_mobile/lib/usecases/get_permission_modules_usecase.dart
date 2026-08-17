import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/permission_module.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetPermissionModulesUseCase {
  final SettingsRepository repository;

  GetPermissionModulesUseCase(this.repository);

  Future<Either<Failure, List<PermissionModule>>> call() async {
    return await repository.getPermissionModules();
  }
}
