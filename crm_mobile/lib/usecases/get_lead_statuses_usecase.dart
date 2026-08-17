import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetLeadStatusesUseCase {
  final SettingsRepository repository;

  GetLeadStatusesUseCase(this.repository);

  Future<Either<Failure, List<LeadStatus>>> call() async {
    return await repository.getLeadStatuses();
  }
}
