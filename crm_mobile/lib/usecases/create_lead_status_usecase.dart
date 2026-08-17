import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class CreateLeadStatusUseCase {
  final SettingsRepository repository;

  CreateLeadStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> statusData) async {
    return await repository.createLeadStatus(statusData);
  }
}
