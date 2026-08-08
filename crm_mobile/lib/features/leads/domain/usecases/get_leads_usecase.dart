import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/lead.dart';
import '../repositories/leads_repository.dart';

class GetLeadsUseCase {
  final LeadsRepository repository;

  GetLeadsUseCase(this.repository);

  Future<Either<Failure, List<Lead>>> call(int page, int size, {String? statusId}) async {
    return await repository.getLeads(page, size, statusId: statusId);
  }
}
