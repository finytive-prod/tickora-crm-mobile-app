import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/followups_repository.dart';

class AddFollowUpUseCase {
  final FollowUpsRepository repository;

  AddFollowUpUseCase(this.repository);

  Future<Either<Failure, void>> call(String leadId, Map<String, dynamic> data) {
    return repository.addFollowUp(leadId, data);
  }
}
