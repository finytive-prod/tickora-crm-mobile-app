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

      if (q != null && q.isNotEmpty) {
        try {
          final globalResponse = await apiClient.post(
            '$_leadsBaseUrl/leads/search/global',
            queryParameters: {
              'query': q,
              'search': q,
              'page': page,
              'size': size,
            },
            data: {
              'query': q,
              'search': q,
            },
          );

          final gBody = globalResponse.data;
          if (gBody != null && (gBody['success'] == true || gBody['statusCode'] == 200) && gBody['data'] != null) {
            List<dynamic> content = [];
            if (gBody['data'] is Map && gBody['data']['content'] is List) {
              content = gBody['data']['content'];
            } else if (gBody['data'] is List) {
              content = gBody['data'];
            }

            final followupItems = content.where((item) {
              if (item is Map) {
                final role = item['role']?.toString().toUpperCase() ?? '';
                return role == 'FOLLOWUP' || role.isEmpty;
              }
              return false;
            }).toList();

            final followUpList = <FollowUp>[];
            for (var item in followupItems) {
              final id = item['id']?.toString();
              if (id != null && id.isNotEmpty) {
                try {
                  final detailRes = await apiClient.get('$_leadsBaseUrl/leads/followups/$id');
                  final dBody = detailRes.data;
                  if (dBody != null && (dBody['success'] == true || dBody['statusCode'] == 200) && dBody['data'] != null) {
                    final f = FollowUpModel.fromJson(dBody['data']);
                    if (f.isRealFollowUp) {
                      followUpList.add(f);
                    }
                  }
                } catch (_) {}
              }
            }

            return Right(FollowUpResponse(
              summary: const FollowUpSummary(today: 0, upcoming: 0, missed: 0, completed: 0),
              followUps: followUpList,
              totalElements: followUpList.length,
              totalPages: 1,
              size: followUpList.length,
              number: 0,
              numberOfElements: followUpList.length,
              first: true,
              last: true,
              empty: followUpList.isEmpty,
            ));
          }
        } catch (_) {
          // Fall back to standard search endpoint if global search throws
        }
      }

      final queryParams = <String, dynamic>{
        'category': category,
        'page': page,
        'size': size,
      };
      if (q != null && q.isNotEmpty) {
        queryParams['search'] = q;
        queryParams['query'] = q;
      }

      final response = await apiClient.get(
        '$_leadsBaseUrl/leads/followups',
        queryParameters: queryParams,
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        FollowUpResponse followUpResponse = FollowUpResponseModel.fromJson(body['data']);

        // 1. Authoritative category mapping:
        // For whichever category is actively queried, its totalElements is the true total count.
        if (category == 'MISSED') {
          followUpResponse = followUpResponse.copyWith(
            summary: FollowUpSummary(
              today: followUpResponse.summary.today,
              upcoming: followUpResponse.summary.upcoming,
              missed: followUpResponse.totalElements,
              completed: followUpResponse.summary.completed,
            ),
          );
        } else if (category == 'TODAY') {
          followUpResponse = followUpResponse.copyWith(
            summary: FollowUpSummary(
              today: followUpResponse.totalElements,
              upcoming: followUpResponse.summary.upcoming,
              missed: followUpResponse.summary.missed,
              completed: followUpResponse.summary.completed,
            ),
          );
        } else if (category == 'UPCOMING') {
          followUpResponse = followUpResponse.copyWith(
            summary: FollowUpSummary(
              today: followUpResponse.summary.today,
              upcoming: followUpResponse.totalElements,
              missed: followUpResponse.summary.missed,
              completed: followUpResponse.summary.completed,
            ),
          );
        } else if (category == 'COMPLETED') {
          followUpResponse = followUpResponse.copyWith(
            summary: FollowUpSummary(
              today: followUpResponse.summary.today,
              upcoming: followUpResponse.summary.upcoming,
              missed: followUpResponse.summary.missed,
              completed: followUpResponse.totalElements,
            ),
          );
        }

        // 2. Fix backend summary bug:
        // When fetching non-MISSED category (e.g. TODAY/UPCOMING), backend summary.missed
        // often returns an unfiltered/inflated count (e.g. 14894). Query the real MISSED count.
        if (category != 'MISSED' && (followUpResponse.summary.missed > 200 || category == 'TODAY')) {
          try {
            final missedRes = await apiClient.get(
              '$_leadsBaseUrl/leads/followups',
              queryParameters: {'category': 'MISSED', 'page': 0, 'size': 1},
            );
            final mData = missedRes.data;
            if (mData != null && mData['data'] != null) {
              final realMissed = (mData['data']['totalElements'] as num?)?.toInt();
              if (realMissed != null) {
                followUpResponse = followUpResponse.copyWith(
                  summary: FollowUpSummary(
                    today: followUpResponse.summary.today,
                    upcoming: followUpResponse.summary.upcoming,
                    missed: realMissed,
                    completed: followUpResponse.summary.completed,
                  ),
                );
              }
            }
          } catch (_) {}
        }

        if (q != null && q.isNotEmpty) {
          final queryLower = q.toLowerCase();
          final filteredList = followUpResponse.followUps.where((item) {
            final leadName = item.leadName.toLowerCase();
            final phone = (item.phoneNumber ?? '').toLowerCase();
            final company = item.companyName.toLowerCase();
            final task = item.leadTask.toLowerCase();
            final status = item.followUpStatus.toLowerCase();
            final assigned = (item.assignedUser?.name ?? '').toLowerCase();
            return leadName.contains(queryLower) ||
                phone.contains(queryLower) ||
                company.contains(queryLower) ||
                task.contains(queryLower) ||
                status.contains(queryLower) ||
                assigned.contains(queryLower);
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
      dynamic body;
      try {
        final response = await apiClient.get(
          '$_leadsBaseUrl/leads/followups/$leadId',
        );
        body = response.data;
      } catch (_) {
        try {
          final response = await apiClient.get(
            '$_leadsBaseUrl/leads/$leadId/followups',
          );
          body = response.data;
        } catch (_) {
          return const Right(LeadFollowUps(followups: []));
        }
      }

      if (body != null && (body['success'] == true || body['statusCode'] == 200)) {
        if (body['data'] != null) {
          final leadFollowUps = LeadFollowUpsModel.fromJson(body['data']);
          return Right(leadFollowUps);
        }
        return const Right(LeadFollowUps(followups: []));
      } else if (body != null && (body['statusCode'] == 404 || body['data'] == null)) {
        return const Right(LeadFollowUps(followups: []));
      } else {
        return const Right(LeadFollowUps(followups: []));
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
