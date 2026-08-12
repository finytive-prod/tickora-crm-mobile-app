import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/lead_detail.dart';
import '../repositories/leads_repository.dart';

class GetLeadDetailsUseCase {
  final LeadsRepository repository;

  GetLeadDetailsUseCase(this.repository);

  Future<Either<Failure, LeadDetail>> call(String id) {
    return repository.getLeadDetails(id);
  }
}
