import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class GetLeadAudiosUseCase {
  final LeadsRepository repository;

  GetLeadAudiosUseCase(this.repository);

  Future<Either<Failure, List<LeadAudio>>> call(String leadId) {
    return repository.getLeadAudios(leadId);
  }
}
