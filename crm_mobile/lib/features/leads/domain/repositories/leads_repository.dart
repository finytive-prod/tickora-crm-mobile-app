import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../entities/lead.dart';

abstract class LeadsRepository {
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId});
  Future<Either<Failure, List<LeadStatus>>> getLeadStatuses();
}
