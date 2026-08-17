import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/activity_lead.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadAuditLogsUseCase {
  final LeadsRepository repository;

  GetLeadAuditLogsUseCase(this.repository);

  Future<Either<Failure, AuditLogResponse>> call(String id, {int page = 0, int size = 20}) {
    return repository.getLeadAuditLogs(id, page: page, size: size);
  }
}
