import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class CreateLeadStatusUseCase {
  final LeadsRepository repository;

  CreateLeadStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> statusData) async {
    return await repository.createLeadStatus(statusData);
  }
}
