import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/lead.dart';
import '../repositories/leads_repository.dart';

class GetLeadStatusesUseCase {
  final LeadsRepository repository;

  GetLeadStatusesUseCase(this.repository);

  Future<Either<Failure, List<LeadStatus>>> call() async {
    return await repository.getLeadStatuses();
  }
}
