import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/role_entity.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetRolesDropdownUseCase {
  final SettingsRepository repository;

  GetRolesDropdownUseCase(this.repository);

  Future<Either<Failure, List<RoleDropdownItem>>> call() async {
    return await repository.getRolesDropdown();
  }
}
