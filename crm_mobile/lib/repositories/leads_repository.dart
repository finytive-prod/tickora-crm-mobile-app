import 'dart:convert';
import 'dart:io';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:dartz/dartz.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/staff_user.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/activity_lead.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/pipeline_model.dart';
import 'package:crm_mobile/models/dialpad_lead_search_result.dart';
import 'package:crm_mobile/models/lead_filter_params.dart';
import 'package:crm_mobile/models/lead_call_log.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/utils/phone_number_utils.dart';
import 'package:crm_mobile/models/owner_call_report.dart';
import 'package:crm_mobile/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/injection/injection.dart';

abstract class LeadsRepository {
  Future<Either<Failure, List<Lead>>> getLeads(
    int page,
    int size, {
    String? statusId,
    bool? isActive,
    LeadFilterParams? filterParams,
    String? searchQuery,
  });
  Future<Either<Failure, List<Lead>>> searchLeads(
    String query, {
    int page = 0,
    int size = 10,
    LeadFilterParams? filterParams,
  });
  Future<Either<Failure, List<String>>> getLeadPriorities();
  Future<Either<Failure, List<StaffUser>>> getStaffUsers({String? search});
  Future<Either<Failure, List<StaffUser>>> getStaffDropdown();
  Future<Either<Failure, void>> createLead(
    Map<String, dynamic> leadData,
    List<String> filePaths, {
    String? leadFileName,
  });
  Future<Either<Failure, void>> updateLead(
    String leadId,
    Map<String, dynamic> leadData,
    List<String> filePaths, {
    String? leadFileName,
  });
  Future<Either<Failure, LeadDetail>> getLeadDetails(String id);
  Future<Either<Failure, AuditLogResponse>> getLeadAuditLogs(
    String id, {
    int page = 0,
    int size = 20,
  });
  Future<Either<Failure, List<Attachment>>> getLeadAttachments(String id);
  Future<Either<Failure, void>> uploadLeadAttachment(
    String leadId,
    String filePath,
  );
  Future<Either<Failure, void>> deleteLeadAttachment(String attachmentId);
  Future<Either<Failure, List<LeadAudio>>> getLeadAudios(String leadId);
  Future<Either<Failure, LeadCallLogResponse>> getLeadCallLogs(String leadId);
  Future<Either<Failure, LeadAudio>> uploadLeadAudio(
    String leadId,
    String? filePath, {
    String? bound,
    String? startTime,
    String? endTime,
    String? from,
    String? to,
    String? fromNumber,
    String? toNumber,
    String? duration,
    String? callDate,
    String? callStatus,
  });
  Future<Either<Failure, void>> updateLeadActiveStatus(
    String leadId,
    bool isActive,
  );
  Future<Either<Failure, String>> exportLeadReport(
    Map<String, dynamic> payload,
  );
  Future<Either<Failure, List<PipelineColumnData>>> getLeadPipeline({
    int page = 0,
    int size = 50,
  });
  Future<Either<Failure, void>> updateLeadStatusInPipeline(
    String leadId,
    String statusId,
  );
  Future<Either<Failure, DialpadLeadSearchResult>> searchLeadByNumber(
    String phoneNumber,
  );
  Future<Either<Failure, void>> quickInviteLead(Map<String, dynamic> data);
  Future<Either<Failure, void>> renameLeadAudio(String audioId, String newName);
  Future<Either<Failure, List<OwnerCallReport>>> getOwnerCallReport({
    String? ownerId,
    List<String>? ownerIds,
    String? startDate,
    String? endDate,
  });
}

class LeadsRepositoryImpl implements LeadsRepository {
  final ApiClient apiClient;

  LeadsRepositoryImpl({required this.apiClient});

  String get _leadsBaseUrl => ApiUrl.leadService;
  String get _identityBaseUrl => ApiUrl.identityService;

  Future<List<Lead>?> _searchGlobalLeads({
    required String? query,
    int page = 0,
    int size = 15,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final q = (query != null && query.trim().isNotEmpty)
          ? query.trim()
          : 'null';

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/search/global',
        queryParameters: {'page': page, 'size': size},
        data: {
          'query': q,
          'isLead': true,
          'isCustomer': false,
          'isUser': false,
          'isFollowup': false,
        },
      );

      final body = response.data;
      if (body != null &&
          (body['success'] == true || body['statusCode'] == 200) &&
          body['data'] != null) {
        final List<dynamic> content;
        if (body['data'] is List) {
          content = body['data'];
        } else if (body['data'] is Map && body['data']['content'] is List) {
          content = body['data']['content'];
        } else {
          content = [];
        }

        final leads = content.map((json) => LeadModel.fromJson(json)).toList();
        return leads;
      }
    } catch (e) {
      debugPrint('Error searching global leads: $e');
    }
    return null;
  }

  List<Lead>? _extractLeadsFromResponseBody(dynamic body, int? statusCode) {
    if (body == null) return null;

    dynamic content;

    if (body is List) {
      content = body;
    } else if (body is Map) {
      final isSuccessful = body['success'] == true ||
          body['statusCode'] == 200 ||
          body['code'] == 200 ||
          body['status'] == 200 ||
          body['status'] == 'OK' ||
          body['status'] == 'SUCCESS' ||
          (statusCode != null && statusCode >= 200 && statusCode < 300);

      if (body['data'] != null) {
        final data = body['data'];
        if (data is List) {
          content = data;
        } else if (data is Map && data['content'] is List) {
          content = data['content'];
        } else if (data is Map && data['leads'] is List) {
          content = data['leads'];
        }
      } else if (body['content'] is List) {
        content = body['content'];
      } else if (body['leads'] is List) {
        content = body['leads'];
      }

      if (content == null && !isSuccessful) {
        return null;
      }
    }

    if (content is List) {
      return content
          .where((item) => item is Map)
          .map((json) => LeadModel.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    }
    return null;
  }

  Future<List<Lead>> _enrichSummaryLeads(List<Lead> leads) async {
    final needsEnrichment = leads.any(
      (l) => l.createdAt == null || l.ownerUserName == null || l.ownerUserName!.isEmpty,
    );
    if (!needsEnrichment) return leads;

    final leadsBaseUrl = _leadsBaseUrl;
    return await Future.wait(
      leads.map((lead) async {
        if (lead.createdAt != null &&
            lead.ownerUserName != null &&
            lead.ownerUserName!.isNotEmpty &&
            lead.createdByName != null &&
            lead.createdByName!.isNotEmpty) {
          return lead;
        }
        try {
          final res = await apiClient.get('$leadsBaseUrl/leads/${lead.id}');
          final b = res.data;
          if (b != null && b['data'] != null && b['data'] is Map) {
            final detailJson = Map<String, dynamic>.from(b['data'] as Map);
            final fullLead = LeadModel.fromJson(detailJson);
            return fullLead;
          }
        } catch (_) {}
        return lead;
      }),
    );
  }

  @override
  Future<Either<Failure, List<Lead>>> getLeads(
    int page,
    int size, {
    String? statusId,
    bool? isActive,
    LeadFilterParams? filterParams,
    String? searchQuery,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;

      final queryParameters = <String, dynamic>{
        'page': page,
        'size': size,
        'sort': 'createdAt,desc',
      };
      if (isActive != null) {
        queryParameters['isActive'] = isActive;
      }
      if (statusId != null && statusId.isNotEmpty) {
        queryParameters['statusId'] = statusId;
      }

      final filterQueryParameters = Map<String, dynamic>.from(queryParameters);
      if (filterParams != null) {
        if (filterParams.sourceIds.isNotEmpty) {
          filterQueryParameters['sourceId'] = filterParams.sourceIds.first;
          filterQueryParameters['sourceIds'] = filterParams.sourceIds;
        }
        if (filterParams.statusIds.isNotEmpty) {
          filterQueryParameters['statusId'] = filterParams.statusIds.first;
          filterQueryParameters['statusIds'] = filterParams.statusIds;
        }
        if (filterParams.priorities.isNotEmpty) {
          filterQueryParameters['priority'] = filterParams.priorities.first;
          filterQueryParameters['priorities'] = filterParams.priorities;
        }
        if (filterParams.createdByIds.isNotEmpty) {
          filterQueryParameters['createdBy'] = filterParams.createdByIds.first;
          filterQueryParameters['createdByIds'] = filterParams.createdByIds;
        }
        if (filterParams.assignedToIds.isNotEmpty) {
          filterQueryParameters['assignedTo'] = filterParams.assignedToIds.first;
          filterQueryParameters['ownerUserId'] = filterParams.assignedToIds.first;
          filterQueryParameters['assignedToIds'] = filterParams.assignedToIds;
        }
        if (filterParams.startDate != null && filterParams.startDate!.isNotEmpty) {
          filterQueryParameters['startDate'] = filterParams.startDate;
          filterQueryParameters['from'] = filterParams.startDate;
          filterQueryParameters['fromDate'] = filterParams.startDate;
        }
        if (filterParams.endDate != null && filterParams.endDate!.isNotEmpty) {
          filterQueryParameters['endDate'] = filterParams.endDate;
          filterQueryParameters['to'] = filterParams.endDate;
          filterQueryParameters['toDate'] = filterParams.endDate;
        }
      }

      final hasSearch = searchQuery != null && searchQuery.trim().isNotEmpty;
      if (hasSearch) {
        final cleanedSearch = sanitizeLeadSearchQuery(searchQuery!);
        if (cleanedSearch.isNotEmpty) {
          queryParameters['search'] = cleanedSearch;
          filterQueryParameters['search'] = cleanedSearch;

          // ── Strategy 0: Dedicated Search Endpoint GET /leads/search?query=...&page=...&size=... ──
          try {
            final searchResponse = await apiClient.get(
              '$leadsBaseUrl/leads/search',
              queryParameters: {
                'query': cleanedSearch,
                'page': page,
                'size': size,
              },
            );
            final searchLeads = _extractLeadsFromResponseBody(
              searchResponse.data,
              searchResponse.statusCode,
            );
            if (searchLeads != null) {
              final enriched = await _enrichSummaryLeads(searchLeads);
              return Right(enriched);
            }
          } on DioException catch (dioErr) {
            debugPrint('[LeadsRepo] GET /leads/search returned ${dioErr.response?.statusCode}, trying fallbacks');
          } catch (e) {
            debugPrint('[LeadsRepo] GET /leads/search failed: $e, trying fallbacks');
          }
        }
      }

      // ── Strategy 1: Primary fetch via GET /leads (provides complete lead details: creator, owner, date, call status) ──
      try {
        final getResponse = await apiClient.get(
          '$leadsBaseUrl/leads',
          queryParameters: filterQueryParameters,
        );
        final parsedLeads = _extractLeadsFromResponseBody(
          getResponse.data,
          getResponse.statusCode,
        );
        if (parsedLeads != null) {
          final enriched = await _enrichSummaryLeads(parsedLeads);
          return Right(enriched);
        }
      } on DioException catch (dioErr) {
        debugPrint('[LeadsRepo] GET /leads returned ${dioErr.response?.statusCode}, trying filter fallback');
      } catch (e) {
        debugPrint('[LeadsRepo] GET /leads failed: $e, trying filter fallback');
      }

      // ── Strategy 2: Use POST /leads/filter (with body payload) ──
      final bodyPayload = <String, dynamic>{
        'page': page,
        'size': size,
        'sort': 'createdAt,desc',
      };
      if (isActive != null) {
        bodyPayload['isActive'] = isActive;
      }
      if (filterParams != null) {
        bodyPayload.addAll(filterParams.toJson());
      }

      if (statusId != null && statusId.isNotEmpty) {
        final existingStatuses = List<String>.from(
          bodyPayload['statusIds'] ?? [],
        );
        if (!existingStatuses.contains(statusId)) {
          existingStatuses.add(statusId);
        }
        bodyPayload['statusIds'] = existingStatuses;
        bodyPayload['statusId'] = statusId;
      }

      if (hasSearch) {
        final cleanedSearch = sanitizeLeadSearchQuery(searchQuery!);
        if (cleanedSearch.isNotEmpty) {
          bodyPayload['search'] = cleanedSearch;
        }
      }

      try {
        final postResponse = await apiClient.post(
          '$leadsBaseUrl/leads/filter',
          queryParameters: queryParameters,
          data: bodyPayload,
        );

        final parsedLeads = _extractLeadsFromResponseBody(
          postResponse.data,
          postResponse.statusCode,
        );
        if (parsedLeads != null) {
          final enriched = await _enrichSummaryLeads(parsedLeads);
          return Right(enriched);
        }
      } on DioException catch (dioErr) {
        debugPrint('[LeadsRepo] POST /leads/filter returned ${dioErr.response?.statusCode}');
      } catch (e) {
        debugPrint('[LeadsRepo] POST /leads/filter failed: $e');
      }

      // ── Strategy 3: Global search fallback ──
      try {
        final globalLeads = await _searchGlobalLeads(
          query: searchQuery,
          page: page,
          size: size,
        );
        if (globalLeads != null) {
          final enriched = await _enrichSummaryLeads(globalLeads);
          return Right(enriched);
        }
      } catch (_) {}

      // ── Strategy 4: Final direct GET /leads fallback ──
      final fallbackResponse = await apiClient.get(
        '$leadsBaseUrl/leads',
        queryParameters: queryParameters,
      );
      final fallbackLeads = _extractLeadsFromResponseBody(
        fallbackResponse.data,
        fallbackResponse.statusCode,
      );
      if (fallbackLeads != null) {
        final enriched = await _enrichSummaryLeads(fallbackLeads);
        return Right(enriched);
      }

      throw ApiException(message: fallbackResponse.data?['message'] ?? 'Failed to load leads');
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Lead>>> searchLeads(
    String query, {
    int page = 0,
    int size = 10,
    LeadFilterParams? filterParams,
  }) async {
    final qTrimmed = query.trim();
    if (qTrimmed.isEmpty) {
      return getLeads(page, size, filterParams: filterParams);
    }

    final cleanedSearch = sanitizeLeadSearchQuery(qTrimmed);

    // 1. Dedicated Search Endpoint: GET /leads/search?query=...&page=...&size=...
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final searchResponse = await apiClient.get(
        '$leadsBaseUrl/leads/search',
        queryParameters: {
          'query': cleanedSearch,
          'page': page,
          'size': size,
        },
      );
      final searchLeads = _extractLeadsFromResponseBody(
        searchResponse.data,
        searchResponse.statusCode,
      );
      if (searchLeads != null) {
        final enriched = await _enrichSummaryLeads(searchLeads);
        return Right(enriched);
      }
    } on DioException catch (dioErr) {
      debugPrint('[LeadsRepo] searchLeads GET /leads/search returned ${dioErr.response?.statusCode}');
    } catch (e) {
      debugPrint('[LeadsRepo] searchLeads GET /leads/search failed: $e');
    }

    // 2. Fallback: Use getLeads with search query and filter params
    final filterResult = await getLeads(
      page,
      size,
      filterParams: filterParams,
      searchQuery: qTrimmed,
    );

    final filterLeads = filterResult.fold<List<Lead>?>(
      (_) => null,
      (leads) => leads,
    );
    if (filterLeads != null && filterLeads.isNotEmpty) {
      return Right(filterLeads);
    }

    final cleanDigits = qTrimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanDigits.length >= 5) {
      try {
        final numberResult = await searchLeadByNumber(qTrimmed);
        final foundLead = numberResult.fold<Lead?>((_) => null, (res) {
          if (res.alreadyMapped &&
              res.leadId != null &&
              res.leadId!.isNotEmpty) {
            final nameStr = res.name ?? 'Lead';
            final parts = nameStr.trim().split(' ');
            final fName = parts.isNotEmpty ? parts.first : '';
            final lName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
            return Lead(
              id: res.leadId!,
              leadNumber: res.leadNumber ?? '',
              firstName: fName,
              lastName: lName,
              companyName: '',
              email: '',
              phone: res.phone ?? qTrimmed,
              status: res.statusName != null
                  ? LeadStatus(
                      id: '',
                      statusName: res.statusName!,
                      color: res.statusColor ?? '#6B7280',
                      isDefault: false,
                      isClosed: false,
                      displayOrder: 0,
                    )
                  : null,
              source: res.sourceName != null
                  ? LeadSource(
                      id: '',
                      name: res.sourceName!,
                      category: '',
                      description: '',
                    )
                  : null,
              ownerUserName: res.assignedToName,
            );
          }
          return null;
        });
        if (foundLead != null) {
          return Right([foundLead]);
        }
      } catch (_) {}
    }

    final globalLeads = await _searchGlobalLeads(
      query: qTrimmed,
      page: page,
      size: size,
    );
    if (globalLeads != null && globalLeads.isNotEmpty) {
      return Right(globalLeads);
    }

    return filterResult;
  }

  @override
  Future<Either<Failure, List<String>>> getLeadPriorities() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/lead-settings/priorities',
      );
      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final priorities = content.map((e) => e.toString()).toList();
        return Right(priorities);
      } else {
        return const Right(['HIGH', 'MEDIUM', 'LOW']);
      }
    } on Exception catch (_) {
      return const Right(['HIGH', 'MEDIUM', 'LOW']);
    }
  }

  @override
  Future<Either<Failure, List<StaffUser>>> getStaffDropdown() async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.get('$identityBaseUrl/users/dropdown');
      final body = response.data;
      if (body != null &&
          (body['success'] == true || response.statusCode == 200) &&
          body['data'] != null) {
        List<dynamic> content;
        if (body['data'] is List) {
          content = body['data'];
        } else if (body['data'] is Map && body['data']['content'] is List) {
          content = body['data']['content'];
        } else {
          content = [];
        }
        final users = content
            .map((json) => StaffUser.fromJson(json as Map<String, dynamic>))
            .toList();
        final sorted = users
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        return Right(sorted);
      }
      return const Right([]);
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<StaffUser>>> getStaffUsers({
    String? search,
  }) async {
    try {
      final identityBaseUrl = _identityBaseUrl;

      final queryParameters = <String, dynamic>{'page': 0, 'size': 1000};
      if (search != null && search.isNotEmpty) {
        queryParameters['search'] = search;
      }

      List<StaffUser> filterByOrg(List<StaffUser> list) {
        final currentOrgId = sl.isRegistered<SharedPreferences>()
            ? sl<SharedPreferences>().getString('organizationId')
            : null;
        if (currentOrgId != null && currentOrgId.isNotEmpty) {
          final matched = list
              .where(
                (u) =>
                    u.organizationId == null ||
                    u.organizationId == currentOrgId,
              )
              .toList();
          if (matched.isNotEmpty) return matched;
        }
        return list;
      }

      // 1. Try /identity/users/dropdown
      try {
        final query = (search != null && search.isNotEmpty)
            ? {'search': search}
            : null;
        final response = await apiClient.get(
          '$identityBaseUrl/users/dropdown',
          queryParameters: query,
        );

        final body = response.data;
        if (body != null &&
            (body['success'] == true || response.statusCode == 200) &&
            body['data'] != null) {
          List<dynamic> content;
          if (body['data'] is List) {
            content = body['data'];
          } else if (body['data'] is Map && body['data']['content'] is List) {
            content = body['data']['content'];
          } else {
            content = [];
          }
          final users = content
              .map((json) => StaffUser.fromJson(json))
              .toList();
          if (users.isNotEmpty) {
            final filtered = filterByOrg(users)
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
            return Right(filtered);
          }
        }
      } catch (_) {}

      // 2. Try /identity/users/staff
      try {
        final response = await apiClient.get(
          '$identityBaseUrl/users/staff',
          queryParameters: queryParameters,
        );

        final body = response.data;
        if (body != null &&
            (body['success'] == true || response.statusCode == 200) &&
            body['data'] != null) {
          List<dynamic> content;
          if (body['data'] is List) {
            content = body['data'];
          } else if (body['data'] is Map && body['data']['content'] is List) {
            content = body['data']['content'];
          } else {
            content = [];
          }
          final users = content
              .map((json) => StaffUser.fromJson(json))
              .toList();
          if (users.isNotEmpty) {
            final filtered = filterByOrg(users)
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
            return Right(filtered);
          }
        }
      } catch (_) {}

      // 3. Fallback to /identity/users
      final response = await apiClient.get(
        '$identityBaseUrl/users',
        queryParameters: queryParameters,
      );

      final body = response.data;
      if (body != null && body['data'] != null) {
        List<dynamic> content;
        if (body['data'] is List) {
          content = body['data'];
        } else if (body['data'] is Map && body['data']['content'] is List) {
          content = body['data']['content'];
        } else {
          content = [];
        }
        final users = content.map((json) => StaffUser.fromJson(json)).toList();
        final filtered = filterByOrg(
          users,
        )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Right(filtered);
      } else {
        return const Right([]);
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error fetching staff users: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> createLead(
    Map<String, dynamic> leadData,
    List<String> filePaths, {
    String? leadFileName,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();

      final leadJson = jsonEncode(leadData);
      final jsonFileName = (leadFileName != null && leadFileName.isNotEmpty)
          ? leadFileName
          : 'test.json';

      formData.files.add(
        MapEntry(
          'lead',
          MultipartFile.fromString(
            leadJson,
            filename: jsonFileName,
            contentType: MediaType('application', 'json'),
          ),
        ),
      );

      for (var path in filePaths) {
        if (path.isNotEmpty) {
          final filename = path.split('/').last.split('\\').last;
          formData.files.add(
            MapEntry(
              'attachments',
              await MultipartFile.fromFile(path, filename: filename),
            ),
          );
          formData.files.add(
            MapEntry(
              'files',
              await MultipartFile.fromFile(path, filename: filename),
            ),
          );
        }
      }

      final response = await apiClient.post(
        '$leadsBaseUrl/leads',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        NotificationService.instance.recordSelfLeadCreated();
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to create lead');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateLead(
    String leadId,
    Map<String, dynamic> leadData,
    List<String> filePaths, {
    String? leadFileName,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();

      final leadJson = jsonEncode(leadData);
      final jsonFileName = (leadFileName != null && leadFileName.isNotEmpty)
          ? leadFileName
          : 'test.json';

      formData.files.add(
        MapEntry(
          'lead',
          MultipartFile.fromString(
            leadJson,
            filename: jsonFileName,
            contentType: MediaType('application', 'json'),
          ),
        ),
      );

      if (leadData.containsKey('ownerUserId') &&
          leadData['ownerUserId'] != null) {
        formData.fields.add(
          MapEntry('uploadedBy', leadData['ownerUserId'].toString()),
        );
      }

      for (var path in filePaths) {
        if (path.isNotEmpty) {
          final filename = path.split('/').last.split('\\').last;
          formData.files.add(
            MapEntry(
              'attachments',
              await MultipartFile.fromFile(path, filename: filename),
            ),
          );
          formData.files.add(
            MapEntry(
              'files',
              await MultipartFile.fromFile(path, filename: filename),
            ),
          );
        }
      }

      final response = await apiClient.put(
        '$leadsBaseUrl/leads/$leadId',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        for (var path in filePaths) {
          if (path.isNotEmpty) {
            try {
              await uploadLeadAttachment(leadId, path);
            } catch (_) {}
          }
        }
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to update lead');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LeadDetail>> getLeadDetails(String id) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      try {
        final response = await apiClient.get('$leadsBaseUrl/leads/$id');
        final body = response.data;
        if (body != null &&
            (body['success'] == true || response.statusCode == 200) &&
            body['data'] != null) {
          final leadDetail = LeadDetailModel.fromJson(body['data']);
          return Right(leadDetail);
        }
      } catch (_) {}

      // Fallback 1: If id was a follow-up ID, resolve its leadId
      try {
        final followupRes = await apiClient.get(
          '$leadsBaseUrl/leads/followups/$id',
        );
        final fBody = followupRes.data;
        if (fBody != null && fBody['data'] != null) {
          final fData = fBody['data'] is Map ? fBody['data'] as Map : null;
          final realLeadId = (fData?['leadId'] ?? fData?['lead']?['id'])
              ?.toString()
              .trim();
          if (realLeadId != null && realLeadId.isNotEmpty && realLeadId != id) {
            final resolved = await getLeadDetails(realLeadId);
            if (resolved.isRight()) return resolved;
          }
        }
      } catch (_) {}

      // Fallback 2: Try global search with id
      try {
        final searchRes = await apiClient.post(
          '$leadsBaseUrl/leads/search/global',
          queryParameters: {'query': id, 'page': 0, 'size': 1},
          data: {'query': id},
        );
        final sBody = searchRes.data;
        if (sBody != null && sBody['data'] != null) {
          List content = [];
          if (sBody['data'] is Map && sBody['data']['content'] is List) {
            content = sBody['data']['content'];
          } else if (sBody['data'] is List) {
            content = sBody['data'];
          }
          if (content.isNotEmpty && content.first is Map) {
            final realLeadId = (content.first['leadId'] ?? content.first['id'])
                ?.toString()
                .trim();
            if (realLeadId != null &&
                realLeadId.isNotEmpty &&
                realLeadId != id) {
              final resolved = await getLeadDetails(realLeadId);
              if (resolved.isRight()) return resolved;
            }
          }
        }
      } catch (_) {}

      return Left(ServerFailure('Lead not found with id: $id'));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error loading lead details: $e'));
    }
  }

  @override
  Future<Either<Failure, AuditLogResponse>> getLeadAuditLogs(
    String id, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/$id/audit-logs',
        queryParameters: {'page': page, 'size': size},
      );

      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final auditLogResponse = AuditLogResponseModel.fromJson(body['data']);
        return Right(auditLogResponse);
      } else {
        throw ApiException(
          message: body['message'] ?? 'Failed to load audit logs',
        );
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Attachment>>> getLeadAttachments(
    String id,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/$id/attachments',
      );

      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final attachments = content
            .map((json) => AttachmentModel.fromJson(json))
            .toList();
        return Right(attachments);
      } else {
        throw ApiException(
          message: body['message'] ?? 'Failed to load attachments',
        );
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> uploadLeadAttachment(
    String leadId,
    String filePath,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();
      final filename = filePath.split('/').last.split('\\').last;

      formData.files.add(
        MapEntry(
          'files',
          await MultipartFile.fromFile(filePath, filename: filename),
        ),
      );

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/$leadId/attachments',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(
          message: body['message'] ?? 'Failed to upload attachment',
        );
      }
    } on DioException catch (e) {
      String msg = 'DioError: ${e.message}';
      if (e.response != null) {
        msg = 'Server 500: ${e.response?.data}';
      }
      return Left(ServerFailure(msg));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> deleteLeadAttachment(
    String attachmentId,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.delete(
        '$leadsBaseUrl/leads/attachments/$attachmentId',
      );
      final body = response.data;
      if (body != null && body is Map && body['success'] == false) {
        throw ApiException(
          message: body['message'] ?? 'Failed to delete attachment',
        );
      }
      return const Right(null);
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<LeadAudio>>> getLeadAudios(String leadId) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/$leadId/audios',
      );

      final body = response.data;
      List<dynamic> listData = [];
      if (body is List) {
        listData = body;
      } else if (body is Map) {
        if (body['data'] is List) {
          listData = body['data'];
        } else if (body['content'] is List) {
          listData = body['content'];
        }
      } else if (body is String && body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is List) {
            listData = decoded;
          } else if (decoded is Map) {
            if (decoded['data'] is List) {
              listData = decoded['data'];
            } else if (decoded['content'] is List) {
              listData = decoded['content'];
            }
          }
        } catch (_) {}
      }

      final audios = listData
          .whereType<Map>()
          .map((json) => LeadAudioModel.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      return Right(audios);
    } on DioException catch (e) {
      if (e.response?.statusCode == 500 || e.response?.statusCode == 404) {
        return const Right([]);
      }
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LeadCallLogResponse>> getLeadCallLogs(
    String leadId,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/$leadId/call-history',
      );

      final body = response.data;
      if (body != null) {
        if (body is List) {
          final callLogsResponse = LeadCallLogResponse.fromJson({'callHistory': body});
          return Right(callLogsResponse);
        } else if (body is Map) {
          final bodyMap = Map<String, dynamic>.from(body);
          final dataMap = (bodyMap.containsKey('data') && bodyMap['data'] is Map)
              ? Map<String, dynamic>.from(bodyMap['data'] as Map)
              : (bodyMap.containsKey('data') && bodyMap['data'] is List
                  ? {'callHistory': bodyMap['data'], ...bodyMap}
                  : bodyMap);
          final callLogsResponse = LeadCallLogResponse.fromJson(dataMap);
          return Right(callLogsResponse);
        }
      }
      return const Left(ServerFailure('Invalid response format'));
    } on DioException catch (e) {
      if (e.response?.statusCode == 500 || e.response?.statusCode == 404) {
        // Fallback to /call-logs if /call-history returned 404
        if (e.response?.statusCode == 404) {
          try {
            final fallbackResponse = await apiClient.get(
              '$_leadsBaseUrl/leads/$leadId/call-history',
            );
            final fallbackBody = fallbackResponse.data;
            if (fallbackBody != null) {
              if (fallbackBody is List) {
                return Right(LeadCallLogResponse.fromJson({'callHistory': fallbackBody}));
              } else if (fallbackBody is Map) {
                return Right(LeadCallLogResponse.fromJson(Map<String, dynamic>.from(fallbackBody)));
              }
            }
          } catch (_) {}
        }
        return const Right(
          LeadCallLogResponse(
            totalCalls: 0,
            totalInboundCalls: 0,
            totalOutboundCalls: 0,
            totalMissedCalls: 0,
            totalDuration: 0,
            callHistory: [],
          ),
        );
      }
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LeadAudio>> uploadLeadAudio(
    String leadId,
    String? filePath, {
    String? bound,
    String? startTime,
    String? endTime,
    String? from,
    String? to,
    String? fromNumber,
    String? toNumber,
    String? duration,
    String? callDate,
    String? callStatus,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();

      if (filePath != null &&
          filePath.isNotEmpty &&
          await File(filePath).exists()) {
        final filename = filePath.split('/').last.split('\\').last;

        String mimeType = 'audio/mpeg';
        final lowerName = filename.toLowerCase();
        if (lowerName.endsWith('.wav')) {
          mimeType = 'audio/wav';
        } else if (lowerName.endsWith('.m4a') || lowerName.endsWith('.aac')) {
          mimeType = 'audio/mp4';
        } else if (lowerName.endsWith('.3gp')) {
          mimeType = 'audio/3gpp';
        } else if (lowerName.endsWith('.amr')) {
          mimeType = 'audio/amr';
        } else if (lowerName.endsWith('.ogg') || lowerName.endsWith('.opus')) {
          mimeType = 'audio/ogg';
        }

        final ext = mimeType.split('/').last;

        final multipartFile = await MultipartFile.fromFile(
          filePath,
          filename: filename,
          contentType: MediaType('audio', ext),
        );

        formData.files.add(MapEntry('files', multipartFile));
      }

      var effBound = bound;
      var effStartTime = startTime;
      var effEndTime = endTime;
      var effFrom = (fromNumber != null && fromNumber.isNotEmpty)
          ? fromNumber
          : from;
      var effTo = (toNumber != null && toNumber.isNotEmpty)
          ? toNumber
          : to;
      var effDuration = duration;
      var effCallDate = callDate;

      if (filePath != null &&
          filePath.isNotEmpty &&
          await File(filePath).exists() &&
          (effStartTime == null ||
              effStartTime.isEmpty ||
              effFrom == null ||
              effFrom.isEmpty ||
              effTo == null ||
              effTo.isEmpty)) {
        try {
          // Fetch lead detail phone number if needed
          String leadPhone = '';
          try {
            final leadDetailResult = await getLeadDetails(leadId);
            leadDetailResult.fold((_) {}, (detail) {
              if (AutoCallRecordingUploader.isUsablePhone(detail.phone)) {
                leadPhone = detail.phone.trim();
              } else if (AutoCallRecordingUploader.isUsablePhone(
                detail.alternatePhone,
              )) {
                leadPhone = detail.alternatePhone!.trim();
              }
            });
          } catch (_) {}

          final callDetails =
              AutoCallRecordingUploader.isUsablePhone(leadPhone)
              ? await CallRecordingService().getLatestCallDetails(
                  phoneNumber: leadPhone,
                  callTimestamp: 0,
                )
              : null;

          final meta = await AutoCallRecordingUploader.buildAudioMetadata(
            filePath: filePath,
            phoneNumber: leadPhone,
            bound: effBound,
            startTime: effStartTime,
            endTime: effEndTime,
            from: effFrom,
            to: effTo,
            duration: effDuration,
            callDate: effCallDate,
            callDetails: callDetails,
          );

          effBound ??= meta['bound'];
          effStartTime ??= meta['startTime'];
          effEndTime ??= meta['endTime'];
          effFrom ??= meta['fromNumber'] ?? meta['from'];
          effTo ??= meta['toNumber'] ?? meta['to'];
          effDuration ??= meta['duration'];
          effCallDate ??= meta['callDate'];
        } catch (e) {
          debugPrint('Error auto-resolving metadata in uploadLeadAudio: $e');
        }
      }

      void setField(String key, String? val) {
        if (val != null && val.isNotEmpty) {
          formData.fields.add(MapEntry(key, val));
        }
      }

      String sanitizeDuration(String? d) {
        if (d == null || d.trim().isEmpty) return '0';
        final trimmed = d.trim();
        if (trimmed.contains(':')) {
          final parts = trimmed.split(':');
          if (parts.length == 3) {
            final h = int.tryParse(parts[0]) ?? 0;
            final m = int.tryParse(parts[1]) ?? 0;
            final s = int.tryParse(parts[2]) ?? 0;
            return (h * 3600 + m * 60 + s).toString();
          } else if (parts.length == 2) {
            final m = int.tryParse(parts[0]) ?? 0;
            final s = int.tryParse(parts[1]) ?? 0;
            return (m * 60 + s).toString();
          }
        }
        return (int.tryParse(trimmed) ?? 0).toString();
      }

      final formattedDuration = sanitizeDuration(effDuration);

      String effectiveBound = 'OUT';
      if (effBound != null && effBound.trim().isNotEmpty) {
        final bUpper = effBound.trim().toUpperCase();
        if (bUpper == 'IN' || bUpper == 'INBOUND' || bUpper == 'INCOMING') {
          effectiveBound = 'IN';
        } else {
          effectiveBound = 'OUT';
        }
      }

      final effectiveFrom = (effFrom != null && effFrom.isNotEmpty)
          ? effFrom
          : 'Staff';
      final effectiveTo = effTo ?? '';

      final durInt = int.tryParse(formattedDuration) ?? 0;
      final effectiveCallStatus = (callStatus != null && callStatus.isNotEmpty)
          ? (callStatus.toUpperCase() == 'ANSWERED' ? 'CONNECTED' : callStatus)
          : (durInt > 0
                ? 'CONNECTED'
                : (filePath != null && filePath.isNotEmpty
                      ? 'CONNECTED'
                      : 'NOT_CONNECTED'));

      setField('bound', effectiveBound);
      setField('fromNumber', effectiveFrom);
      setField('from', effectiveFrom);
      setField('toNumber', effectiveTo);
      setField('to', effectiveTo);
      setField('duration', formattedDuration);
      setField('callStatus', effectiveCallStatus);
      setField('callDate', effCallDate);
      setField('startTime', effStartTime);
      setField('endTime', effEndTime);

      if (filePath != null &&
          filePath.isNotEmpty &&
          await File(filePath).exists()) {
        final realFilename = filePath.split('/').last.split('\\').last;
        setField('originalFileName', realFilename);
      }

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/$leadId/audios',
        data: formData,
        queryParameters: null,
        options: Options(
          sendTimeout: const Duration(minutes: 15),
          receiveTimeout: const Duration(minutes: 15),
        ),
      );

      final body = response.data;
      if (body != null) {
        Map<String, dynamic> dataJson = {};
        if (body is Map<String, dynamic>) {
          if (body.containsKey('data')) {
            final dataVal = body['data'];
            if (dataVal is Map<String, dynamic>) {
              dataJson = dataVal;
            } else if (dataVal is List &&
                dataVal.isNotEmpty &&
                dataVal.first is Map<String, dynamic>) {
              dataJson = dataVal.first as Map<String, dynamic>;
            }
          } else {
            dataJson = body;
          }
        } else if (body is List &&
            body.isNotEmpty &&
            body.first is Map<String, dynamic>) {
          dataJson = body.first as Map<String, dynamic>;
        }

        LeadAudio audioModel;
        if (dataJson.isNotEmpty &&
            (dataJson['id'] != null || dataJson['_id'] != null)) {
          try {
            audioModel = LeadAudioModel.fromJson(dataJson);
          } catch (_) {
            audioModel = _createFallbackAudioModel(
              leadId,
              effBound,
              effStartTime,
              effEndTime,
              effectiveFrom,
              effTo,
              effDuration,
              effCallDate,
              callStatus,
            );
          }
        } else {
          audioModel = _createFallbackAudioModel(
            leadId,
            effBound,
            effStartTime,
            effEndTime,
            effectiveFrom,
            effTo,
            effDuration,
            effCallDate,
            callStatus,
          );
        }
        return Right(audioModel);
      } else {
        throw ApiException(message: 'Failed to upload audio file');
      }
    } on DioException catch (e) {
      String msg = 'Upload failed';
      if (e.response != null && e.response?.data is Map) {
        msg =
            e.response?.data['message'] ??
            'Server error ${e.response?.statusCode}';
      } else if (e.response != null) {
        msg = 'Server status ${e.response?.statusCode}';
      }
      return Left(ServerFailure(msg));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  LeadAudio _createFallbackAudioModel(
    String leadId,
    String? bound,
    String? startTime,
    String? endTime,
    String? from,
    String? to,
    String? duration,
    String? callDate,
    String? callStatus,
  ) {
    return LeadAudio(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      leadId: leadId,
      fileName: '',
      originalFileName: '',
      contentType: 'audio/mpeg',
      size: 0,
      bound: bound,
      startTimeStr: startTime,
      endTimeStr: endTime,
      fromNumber: from,
      toNumber: to,
      durationSeconds: int.tryParse(duration ?? '0') ?? 0,
      callDate: callDate,
      createdAt: DateTime.now(),
      callStatus: (callStatus != null && callStatus.isNotEmpty)
          ? (callStatus.toUpperCase() == 'ANSWERED' ? 'CONNECTED' : callStatus)
          : ((int.tryParse(duration ?? '0') ?? 0) > 0
                ? 'CONNECTED'
                : 'NOT_CONNECTED'),
    );
  }

  @override
  Future<Either<Failure, void>> updateLeadActiveStatus(
    String leadId,
    bool isActive,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.put(
        '$leadsBaseUrl/leads/$leadId/active-status?isActive=$isActive',
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(
          message: body['message'] ?? 'Failed to update lead status',
        );
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, String>> exportLeadReport(
    Map<String, dynamic> payload,
  ) async {
    final leadsBaseUrl = _leadsBaseUrl;
    final url = '$leadsBaseUrl/leads/export/csv';
    debugPrint('[LeadsRepo] Calling POST $url with payload $payload');
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath =
          '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.csv';

      await apiClient.download(
        url,
        savePath,
        data: payload,
        options: Options(method: 'POST'),
      );

      debugPrint('[LeadsRepo] Successfully downloaded export to $savePath');
      return Right(savePath);
    } catch (e) {
      debugPrint('[LeadsRepo] export error: $e');
      return const Left(ServerFailure('Failed to download export file.'));
    }
  }

  @override
  Future<Either<Failure, List<PipelineColumnData>>> getLeadPipeline({
    int page = 0,
    int size = 50,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/pipeline',
        queryParameters: {'page': page, 'size': size},
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] is List) {
        final List<dynamic> list = body['data'];
        final columns = list
            .map(
              (e) => PipelineColumnData.fromJson(
                e is Map<String, dynamic>
                    ? e
                    : Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
        columns.sort(
          (a, b) => a.status.displayOrder.compareTo(b.status.displayOrder),
        );
        return Right(columns);
      } else {
        throw ApiException(
          message: body?['message'] ?? 'Failed to fetch pipeline data',
        );
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateLeadStatusInPipeline(
    String leadId,
    String statusId,
  ) async {
    final leadsBaseUrl = _leadsBaseUrl;

    try {
      final res = await apiClient.put(
        '$leadsBaseUrl/leads/$leadId/status',
        data: {'statusId': statusId},
      );
      final body = res.data;
      if (body != null) {
        if (body['success'] == true) {
          return const Right(null);
        } else if (body['message'] != null &&
            body['message'].toString().trim().isNotEmpty) {
          return Left(ServerFailure(body['message'].toString().trim()));
        }
      }
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        try {
          final formData = FormData();
          final leadJson = jsonEncode({'statusId': statusId});
          formData.files.add(
            MapEntry(
              'lead',
              MultipartFile.fromString(
                leadJson,
                filename: 'test.json',
                contentType: MediaType('application', 'json'),
              ),
            ),
          );

          final response = await apiClient.put(
            '$leadsBaseUrl/leads/$leadId',
            data: formData,
          );

          final body = response.data;
          if (body != null && body['success'] == true) {
            return const Right(null);
          } else {
            return Left(
              ServerFailure(body?['message'] ?? 'Failed to update lead status'),
            );
          }
        } on Object catch (fallbackError) {
          return Left(ErrorHandler.mapExceptionToFailure(fallbackError));
        }
      }
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } on Object catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, DialpadLeadSearchResult>> searchLeadByNumber(
    String phoneNumber,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/search/number',
        queryParameters: {'phone': phoneNumber},
      );

      final body = response.data;
      if (body != null && body is Map<String, dynamic>) {
        final result = DialpadLeadSearchResult.fromJson(body);
        return Right(result);
      } else {
        return Right(DialpadLeadSearchResult(alreadyMapped: false));
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error searching lead by number: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> quickInviteLead(
    Map<String, dynamic> data,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.post(
        '$leadsBaseUrl/leads/quick-invite',
        data: data,
      );

      final body = response.data;
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          (body != null &&
              (body['success'] == true ||
                  body['statusCode'] == 200 ||
                  body['statusCode'] == 201))) {
        return const Right(null);
      } else {
        return Left(
          ServerFailure(body?['message'] ?? 'Failed to send quick invite'),
        );
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error sending quick invite: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> renameLeadAudio(
    String audioId,
    String newName,
  ) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.put(
        '$leadsBaseUrl/leads/audios/$audioId',
        data: {'fileName': newName},
      );

      final body = response.data;
      if (response.statusCode == 200 ||
          (body != null &&
              (body['success'] == true || body['statusCode'] == 200))) {
        return const Right(null);
      } else {
        return Left(
          ServerFailure(body?['message'] ?? 'Failed to rename audio'),
        );
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error renaming audio: $e'));
    }
  }

  @override
  Future<Either<Failure, List<OwnerCallReport>>> getOwnerCallReport({
    String? ownerId,
    List<String>? ownerIds,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final Map<String, dynamic> payload = {};

      if (ownerIds != null) {
        payload['ownerIds'] = ownerIds;
      } else if (ownerId != null && ownerId.isNotEmpty) {
        payload['ownerIds'] = [ownerId];
      } else {
        payload['ownerIds'] = [];
      }

      if (startDate != null && startDate.isNotEmpty) {
        payload['startDate'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        payload['endDate'] = endDate;
      }

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/owner-call-report',
        data: payload,
      );

      final body = response.data;
      if (body != null && (body['data'] is List)) {
        final List list = body['data'];
        final reports = list
            .map((e) => OwnerCallReport.fromJson(e as Map<String, dynamic>))
            .toList();
        return Right(reports);
      } else {
        return const Right([]);
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error fetching owner call report: $e'));
    }
  }
}
