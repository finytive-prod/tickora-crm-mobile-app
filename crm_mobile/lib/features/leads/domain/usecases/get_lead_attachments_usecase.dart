import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/attachment.dart';
import '../repositories/leads_repository.dart';

class GetLeadAttachmentsUseCase {
  final LeadsRepository repository;

  GetLeadAttachmentsUseCase(this.repository);

  Future<Either<Failure, List<Attachment>>> call(String id) {
    return repository.getLeadAttachments(id);
  }
}
