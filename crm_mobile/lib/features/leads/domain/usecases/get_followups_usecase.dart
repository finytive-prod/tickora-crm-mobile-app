import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/follow_up.dart';
import '../repositories/followups_repository.dart';

class GetFollowUpsUseCase {
  final FollowUpsRepository repository;

  GetFollowUpsUseCase(this.repository);

  Future<Either<Failure, FollowUpResponse>> call({required String category, int page = 0, int size = 10}) {
    return repository.getFollowUps(category: category, page: page, size: size);
  }
}
