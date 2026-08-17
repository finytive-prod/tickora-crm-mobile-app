import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead_followups.dart';
import 'package:crm_mobile/repositories/followups_repository.dart';

class GetLeadFollowUpsUseCase {
  final FollowUpsRepository repository;

  GetLeadFollowUpsUseCase(this.repository);

  Future<Either<Failure, LeadFollowUps>> call(String leadId) {
    return repository.getLeadFollowUps(leadId);
  }
}
