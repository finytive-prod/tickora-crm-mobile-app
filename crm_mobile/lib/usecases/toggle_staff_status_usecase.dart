import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class ToggleStaffStatusUseCase {
  final SettingsRepository repository;

  ToggleStaffStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, bool isActive) {
    return repository.toggleStaffStatus(id, isActive);
  }
}
