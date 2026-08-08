import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/error_handler.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/leads_repository.dart';
import '../models/lead_model.dart';

class LeadsRepositoryImpl implements LeadsRepository {
  final ApiClient apiClient;

  LeadsRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId}) async {
    try {
      final leadsBaseUrl = dotenv.env['LEADS_BASE_URL'] ?? '';
      final queryParameters = <String, dynamic>{
        'page': page,
        'size': size,
      };
      if (statusId != null) {
        queryParameters['statusId'] = statusId;
      }

      final response = await apiClient.get(
        '$leadsBaseUrl/leads',
        queryParameters: queryParameters,
      );

      final body = response.data;
      if (body['success'] == true && body['data'] != null && body['data']['content'] != null) {
        final List<dynamic> content = body['data']['content'];
        final leads = content.map((json) => LeadModel.fromJson(json)).toList();
        return Right(leads);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load leads');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<LeadStatus>>> getLeadStatuses() async {
    try {
      final leadsBaseUrl = dotenv.env['LEADS_BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/statuses');
      
      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final statuses = content.map((json) => LeadStatusModel.fromJson(json)).toList();
        return Right(statuses);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load statuses');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
