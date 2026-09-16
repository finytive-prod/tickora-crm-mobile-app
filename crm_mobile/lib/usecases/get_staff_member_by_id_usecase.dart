import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetStaffMemberByIdUseCase {
  final SettingsRepository repository;

  GetStaffMemberByIdUseCase(this.repository);

  Future<Either<Failure, StaffMember>> call(String id) {
    return repository.getStaffMemberById(id);
  }
}
