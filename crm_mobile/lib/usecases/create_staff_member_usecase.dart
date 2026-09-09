import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class CreateStaffMemberUseCase {
  final SettingsRepository repository;

  CreateStaffMemberUseCase(this.repository);

  Future<Either<Failure, StaffMember>> call(Map<String, dynamic> data) {
    return repository.createStaffMember(data);
  }
}
