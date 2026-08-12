import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/follow_up.dart';
import '../entities/lead_followups.dart';

abstract class FollowUpsRepository {
  Future<Either<Failure, FollowUpResponse>> getFollowUps({required String category, int page = 0, int size = 10});
  Future<Either<Failure, LeadFollowUps>> getLeadFollowUps(String leadId);
  Future<Either<Failure, void>> updateFollowUp(String followupId, Map<String, dynamic> data);
}
