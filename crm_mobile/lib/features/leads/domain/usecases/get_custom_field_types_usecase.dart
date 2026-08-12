import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class GetCustomFieldTypesUseCase {
  final LeadsRepository repository;

  GetCustomFieldTypesUseCase(this.repository);

  Future<Either<Failure, List<String>>> call() async {
    return await repository.getCustomFieldTypes();
  }
}
