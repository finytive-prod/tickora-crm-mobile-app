import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/followups_repository.dart';

class UpdateFollowUpUseCase {
  final FollowUpsRepository repository;

  UpdateFollowUpUseCase(this.repository);

  Future<Either<Failure, void>> call(String followupId, Map<String, dynamic> data) {
    return repository.updateFollowUp(followupId, data);
  }
}
