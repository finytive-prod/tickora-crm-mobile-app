import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadAttachmentsUseCase {
  final LeadsRepository repository;

  GetLeadAttachmentsUseCase(this.repository);

  Future<Either<Failure, List<Attachment>>> call(String id) {
    return repository.getLeadAttachments(id);
  }
}
