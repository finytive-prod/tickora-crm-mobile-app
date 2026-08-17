import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadPrioritiesUseCase {
  final LeadsRepository repository;

  GetLeadPrioritiesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() async {
    return await repository.getLeadPriorities();
  }
}
