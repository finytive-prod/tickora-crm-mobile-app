import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/error_handler.dart';
import '../../domain/entities/follow_up.dart';
import '../../domain/entities/lead_followups.dart';
import '../../domain/repositories/followups_repository.dart';
import '../models/follow_up_model.dart';
import '../models/lead_followups_model.dart';

class FollowUpsRepositoryImpl implements FollowUpsRepository {
  final ApiClient apiClient;

  FollowUpsRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, FollowUpResponse>> getFollowUps({required String category, int page = 0, int size = 10}) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/followups',
        queryParameters: {
          'category': category,
          'page': page,
          'size': size,
        },
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final followUpResponse = FollowUpResponseModel.fromJson(body['data']);
        return Right(followUpResponse);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load followups');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LeadFollowUps>> getLeadFollowUps(String leadId) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/$leadId/followups',
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final leadFollowUps = LeadFollowUpsModel.fromJson(body['data']);
        return Right(leadFollowUps);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load lead followups');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateFollowUp(String followupId, Map<String, dynamic> data) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.put(
        '$leadsBaseUrl/leads/followups/$followupId',
        data: data,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to update followup');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
