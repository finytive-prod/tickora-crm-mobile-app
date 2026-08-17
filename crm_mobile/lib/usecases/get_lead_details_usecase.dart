import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadDetailsUseCase {
  final LeadsRepository repository;

  GetLeadDetailsUseCase(this.repository);

  Future<Either<Failure, LeadDetail>> call(String id) {
    return repository.getLeadDetails(id);
  }
}
