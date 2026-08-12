import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/activity_lead.dart';
import '../repositories/leads_repository.dart';

class GetLeadAuditLogsUseCase {
  final LeadsRepository repository;

  GetLeadAuditLogsUseCase(this.repository);

  Future<Either<Failure, AuditLogResponse>> call(String id, {int page = 0, int size = 20}) {
    return repository.getLeadAuditLogs(id, page: page, size: size);
  }
}
