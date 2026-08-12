import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/staff_user.dart';
import '../repositories/leads_repository.dart';

class GetStaffUsersUseCase {
  final LeadsRepository repository;

  GetStaffUsersUseCase(this.repository);

  Future<Either<Failure, List<StaffUser>>> call({String? search}) async {
    return await repository.getStaffUsers(search: search);
  }
}
