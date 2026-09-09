import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class ReorderRolePriorityUseCase {
  final SettingsRepository repository;

  ReorderRolePriorityUseCase(this.repository);

  Future<Either<Failure, void>> call(String roleId, int newPriority) async {
    return await repository.reorderRolePriority(roleId, newPriority);
  }
}
