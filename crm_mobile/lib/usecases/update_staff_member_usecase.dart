import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class UpdateStaffMemberUseCase {
  final SettingsRepository repository;

  UpdateStaffMemberUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, Map<String, dynamic> data) {
    return repository.updateStaffMember(id, data);
  }
}
