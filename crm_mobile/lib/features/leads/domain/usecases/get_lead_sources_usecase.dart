import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/lead.dart';
import '../repositories/leads_repository.dart';

class GetLeadSourcesUseCase {
  final LeadsRepository repository;

  GetLeadSourcesUseCase(this.repository);

  Future<Either<Failure, List<LeadSource>>> call() async {
    return await repository.getLeadSources();
  }
}
