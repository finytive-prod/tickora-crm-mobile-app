import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class ReorderLeadStatusUseCase {
  final LeadsRepository repository;

  ReorderLeadStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(String id, int displayOrder) async {
    return await repository.reorderLeadStatus(id, displayOrder);
  }
}
