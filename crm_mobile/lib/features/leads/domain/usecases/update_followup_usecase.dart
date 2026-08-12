import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/followups_repository.dart';

class UpdateFollowUpUseCase {
  final FollowUpsRepository repository;

  UpdateFollowUpUseCase(this.repository);

  Future<Either<Failure, void>> call(String followupId, Map<String, dynamic> data) {
    return repository.updateFollowUp(followupId, data);
  }
}
