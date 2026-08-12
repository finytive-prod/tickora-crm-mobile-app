import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class SetDefaultLeadStatusUseCase {
  final LeadsRepository repository;

  SetDefaultLeadStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(String id) async {
    return await repository.setDefaultLeadStatus(id);
  }
}
