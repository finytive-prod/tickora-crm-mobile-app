import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../repositories/leads_repository.dart';

class UploadLeadAttachmentUseCase {
  final LeadsRepository repository;

  UploadLeadAttachmentUseCase(this.repository);

  Future<Either<Failure, void>> call(String leadId, String filePath) {
    return repository.uploadLeadAttachment(leadId, filePath);
  }
}
