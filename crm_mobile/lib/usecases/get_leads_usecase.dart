import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadsUseCase {
  final LeadsRepository repository;

  GetLeadsUseCase(this.repository);

  Future<Either<Failure, List<Lead>>> call(int page, int size, {String? statusId}) async {
    return await repository.getLeads(page, size, statusId: statusId);
  }
}
