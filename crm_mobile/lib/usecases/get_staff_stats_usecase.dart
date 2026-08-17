import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/staff_stats.dart';
import 'package:crm_mobile/repositories/settings_repository.dart';

class GetStaffStatsUseCase {
  final SettingsRepository repository;

  GetStaffStatsUseCase(this.repository);

  Future<Either<Failure, StaffStats>> call() {
    return repository.getStaffStats();
  }
}
