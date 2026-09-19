import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/models/lead_followups.dart';

import 'package:crm_mobile/core/network/api_constants.dart';

abstract class FollowUpsRepository {
  Future<Either<Failure, FollowUpResponse>> getFollowUps({required String category, int page = 0, int size = 10, String? searchQuery});
  Future<Either<Failure, LeadFollowUps>> getLeadFollowUps(String leadId);
  Future<Either<Failure, void>> updateFollowUp(String followupId, Map<String, dynamic> data);
  Future<Either<Failure, void>> addFollowUp(String leadId, Map<String, dynamic> data);
}

class FollowUpsRepositoryImpl implements FollowUpsRepository {
  final ApiClient apiClient;

  FollowUpsRepositoryImpl({required this.apiClient});

  String get _leadsBaseUrl => ApiUrl.leadService;

  @override
  Future<Either<Failure, FollowUpResponse>> getFollowUps({required String category, int page = 0, int size = 10, String? searchQuery}) async {
    try {
      final q = (searchQuery != null && searchQuery.trim().isNotEmpty) ? searchQuery.trim() : null;

      // If user is performing a search, try global search endpoint first
      if (q != null) {
        try {
          final response = await apiClient.post(
            '$_leadsBaseUrl/leads/search/global',
            queryParameters: {
              'page': page,
              'size': size,
            },
            data: {
              'query': q,
              'isLead': false,
              'isCustomer': false,
              'isUser': false,
              'isFollowup': true,
            },
          );

          final body = response.data;
          if (body != null && body['success'] == true && body['data'] != null) {
            FollowUpResponse followUpResponse = FollowUpResponseModel.fromJson(body['data']);
            final queryLower = q.toLowerCase();
            final filteredList = followUpResponse.followUps.where((item) {
              final leadName = item.leadName.toLowerCase();
              final phone = (item.phoneNumber ?? '').toLowerCase();
              final company = item.companyName.toLowerCase();
              final task = item.leadTask.toLowerCase();
              return leadName.contains(queryLower) || phone.contains(queryLower) || company.contains(queryLower) || task.contains(queryLower);
            }).toList();

            followUpResponse = followUpResponse.copyWith(
              followUps: filteredList,
              totalElements: filteredList.length,
              numberOfElements: filteredList.length,
            );

            if (followUpResponse.followUps.isNotEmpty) {
              return Right(followUpResponse);
            }
          }
        } catch (_) {
          // If search/global fails, continue to standard GET endpoint
        }
      }

      // Standard category followups retrieval (or fallback when searching)
      final response = await apiClient.get(
        '$_leadsBaseUrl/leads/followups',
        queryParameters: {
          'category': category,
          'page': page,
          'size': size,
        },
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        FollowUpResponse followUpResponse = FollowUpResponseModel.fromJson(body['data']);
        if (q != null && q.isNotEmpty) {
          final queryLower = q.toLowerCase();
          final filteredList = followUpResponse.followUps.where((item) {
            final leadName = item.leadName.toLowerCase();
            final phone = (item.phoneNumber ?? '').toLowerCase();
            final company = item.companyName.toLowerCase();
            final task = item.leadTask.toLowerCase();
            return leadName.contains(queryLower) || phone.contains(queryLower) || company.contains(queryLower) || task.contains(queryLower);
          }).toList();
          followUpResponse = followUpResponse.copyWith(
            followUps: filteredList,
            totalElements: filteredList.length,
            numberOfElements: filteredList.length,
          );
        }
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
      final response = await apiClient.get(
        '$_leadsBaseUrl/leads/$leadId/followups',
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
      final response = await apiClient.put(
        '$_leadsBaseUrl/leads/followups/$followupId',
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

  @override
  Future<Either<Failure, void>> addFollowUp(String leadId, Map<String, dynamic> data) async {
    try {
      final response = await apiClient.post(
        '$_leadsBaseUrl/leads/$leadId/followup',
        data: data,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to add followup');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
