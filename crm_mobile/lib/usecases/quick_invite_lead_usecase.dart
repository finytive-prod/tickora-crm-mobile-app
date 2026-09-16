import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class QuickInviteLeadUseCase {
  final LeadsRepository repository;

  QuickInviteLeadUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> data) {
    return repository.quickInviteLead(data);
  }
}
