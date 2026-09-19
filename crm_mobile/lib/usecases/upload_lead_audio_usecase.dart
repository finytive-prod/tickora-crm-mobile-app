import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class UploadLeadAudioUseCase {
  final LeadsRepository repository;

  UploadLeadAudioUseCase(this.repository);

  Future<Either<Failure, LeadAudio>> call(
    String leadId,
    String? filePath, {
    String? bound,
    String? startTime,
    String? endTime,
    String? from,
    String? to,
    String? duration,
    String? callDate,
    String? callStatus,
  }) {
    return repository.uploadLeadAudio(
      leadId,
      filePath,
      bound: bound,
      startTime: startTime,
      endTime: endTime,
      from: from,
      to: to,
      duration: duration,
      callDate: callDate,
      callStatus: callStatus,
    );
  }
}
