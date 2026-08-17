import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/repositories/followups_repository.dart';

class GetFollowUpsUseCase {
  final FollowUpsRepository repository;

  GetFollowUpsUseCase(this.repository);

  Future<Either<Failure, FollowUpResponse>> call({required String category, int page = 0, int size = 10}) {
    return repository.getFollowUps(category: category, page: page, size: size);
  }
}
