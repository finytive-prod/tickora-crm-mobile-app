import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class UploadLeadAttachmentUseCase {
  final LeadsRepository repository;

  UploadLeadAttachmentUseCase(this.repository);

  Future<Either<Failure, void>> call(String leadId, String filePath) {
    return repository.uploadLeadAttachment(leadId, filePath);
  }
}
