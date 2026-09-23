import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadCallLogsUseCase {
  final LeadsRepository repository;

  GetLeadCallLogsUseCase(this.repository);

  Future<Either<Failure, LeadCallLogResponse>> call(String leadId) async {
    return await repository.getLeadCallLogs(leadId);
  }
}
