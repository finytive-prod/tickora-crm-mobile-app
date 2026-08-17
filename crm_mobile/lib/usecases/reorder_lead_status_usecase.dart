import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class ReorderLeadStatusUseCase {
  final SettingsRepository repository;

  ReorderLeadStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, int displayOrder) async {
    return await repository.reorderLeadStatus(id, displayOrder);
  }
}
