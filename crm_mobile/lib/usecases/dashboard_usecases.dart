import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/dashboard_repository.dart';

class GetDashboardPreferencesUseCase {
  final DashboardRepository repository;

  GetDashboardPreferencesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() {
    return repository.getDashboardPreferences();
  }
}

class UpdateDashboardPreferencesUseCase {
  final DashboardRepository repository;

  UpdateDashboardPreferencesUseCase(this.repository);

  Future<Either<Failure, void>> call(List<String> visibleWidgets) {
    return repository.updateDashboardPreferences(visibleWidgets);
  }
}
