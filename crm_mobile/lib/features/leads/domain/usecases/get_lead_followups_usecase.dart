import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/lead_followups.dart';
import '../repositories/followups_repository.dart';

class GetLeadFollowUpsUseCase {
  final FollowUpsRepository repository;

  GetLeadFollowUpsUseCase(this.repository);

  Future<Either<Failure, LeadFollowUps>> call(String leadId) {
    return repository.getLeadFollowUps(leadId);
  }
}
