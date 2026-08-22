import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetStaffMembersUseCase {
  final SettingsRepository repository;

  GetStaffMembersUseCase(this.repository);

  Future<Either<Failure, List<StaffMember>>> call({int page = 0, int size = 20, String status = 'ACTIVE', String? searchQuery}) {
    return repository.getStaffMembers(page, size, status, searchQuery: searchQuery);
  }
}
