import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetStaffUsersUseCase {
  final LeadsRepository repository;

  GetStaffUsersUseCase(this.repository);

  Future<Either<Failure, List<StaffUser>>> call({String? search}) async {
    return await repository.getStaffUsers(search: search);
  }
}
