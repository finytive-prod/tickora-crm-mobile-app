import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class GetLeadPrioritiesUseCase {
  final LeadsRepository repository;

  GetLeadPrioritiesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() async {
    return await repository.getLeadPriorities();
  }
}
