import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';

class SearchLeadsUseCase {
  final LeadsRepository repository;

  SearchLeadsUseCase(this.repository);

  Future<Either<Failure, List<Lead>>> call(
    String query, {
    int page = 0,
    int size = 10,
    LeadFilterParams? filterParams,
  }) async {
    return await repository.searchLeads(
      query,
      page: page,
      size: size,
      filterParams: filterParams,
    );
  }
}

