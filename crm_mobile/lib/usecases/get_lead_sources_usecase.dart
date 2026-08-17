import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetLeadSourcesUseCase {
  final SettingsRepository repository;

  GetLeadSourcesUseCase(this.repository);

  Future<Either<Failure, List<LeadSource>>> call() async {
    return await repository.getLeadSources();
  }
}
