import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class UpdateLeadActiveStatusUseCase {
  final LeadsRepository repository;

  UpdateLeadActiveStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(String leadId, bool isActive) async {
    return await repository.updateLeadActiveStatus(leadId, isActive);
  }
}
