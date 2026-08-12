import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class CreateLeadUseCase {
  final LeadsRepository repository;

  CreateLeadUseCase(this.repository);

  Future<Either<Failure, void>> call(Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName}) {
    return repository.createLead(leadData, filePaths, leadFileName: leadFileName);
  }
}
