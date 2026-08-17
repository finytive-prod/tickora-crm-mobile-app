import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class UpdateLeadUseCase {
  final LeadsRepository repository;

  UpdateLeadUseCase(this.repository);

  Future<Either<Failure, void>> call(String leadId, Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName}) {
    return repository.updateLead(leadId, leadData, filePaths, leadFileName: leadFileName);
  }
}
