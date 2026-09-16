import 'dart:convert';
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
import 'package:crm_mobile/models/lead_model.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/models/lead_detail_model.dart';
import 'package:crm_mobile/models/activity_lead.dart';
import 'package:crm_mobile/models/activity_lead_model.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/models/attachment_model.dart';
import 'package:crm_mobile/models/lead_audio.dart';
import 'package:crm_mobile/models/lead_audio_model.dart';
import 'package:crm_mobile/models/pipeline_model.dart';
import 'package:crm_mobile/models/dialpad_lead_search_result.dart';
import 'package:crm_mobile/core/network/api_constants.dart';

abstract class LeadsRepository {
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId, bool? isActive});
  Future<Either<Failure, List<Lead>>> searchLeads(String query, {int page = 0, int size = 10});
  Future<Either<Failure, List<String>>> getLeadPriorities();
  Future<Either<Failure, List<StaffUser>>> getStaffUsers({String? search});
  Future<Either<Failure, void>> createLead(Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName});
  Future<Either<Failure, void>> updateLead(String leadId, Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName});
  Future<Either<Failure, LeadDetail>> getLeadDetails(String id);
  Future<Either<Failure, AuditLogResponse>> getLeadAuditLogs(String id, {int page = 0, int size = 20});
  Future<Either<Failure, List<Attachment>>> getLeadAttachments(String id);
  Future<Either<Failure, void>> uploadLeadAttachment(String leadId, String filePath);
  Future<Either<Failure, List<LeadAudio>>> getLeadAudios(String leadId);
  Future<Either<Failure, LeadAudio>> uploadLeadAudio(String leadId, String filePath);
  Future<Either<Failure, void>> updateLeadActiveStatus(String leadId, bool isActive);
  Future<Either<Failure, String>> exportLeadReport(Map<String, dynamic> payload);
  Future<Either<Failure, List<PipelineColumnData>>> getLeadPipeline({int page = 0, int size = 50});
  Future<Either<Failure, void>> updateLeadStatusInPipeline(String leadId, String statusId);
  Future<Either<Failure, DialpadLeadSearchResult>> searchLeadByNumber(String phoneNumber);
  Future<Either<Failure, void>> quickInviteLead(Map<String, dynamic> data);
}

class LeadsRepositoryImpl implements LeadsRepository {
  final ApiClient apiClient;

  LeadsRepositoryImpl({required this.apiClient});

  String get _leadsBaseUrl => ApiUrl.leadService;
  String get _identityBaseUrl => ApiUrl.identityService;

  @override
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId, bool? isActive}) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;

      final queryParameters = <String, dynamic>{
        'page': page,
        'size': size,
        'sort': 'createdAt,desc',
      };
      if (statusId != null) queryParameters['statusId'] = statusId;
      if (isActive != null) queryParameters['isActive'] = isActive;

      final response = await apiClient.get(
        '$leadsBaseUrl/leads',
        queryParameters: queryParameters,
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content;
        if (body['data'] is List) {
          content = body['data'];
        } else if (body['data'] is Map && body['data']['content'] is List) {
          content = body['data']['content'];
        } else {
          content = [];
        }
        final leads = content.map((json) => LeadModel.fromJson(json)).toList();
        return Right(leads);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load leads');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Lead>>> searchLeads(String query, {int page = 0, int size = 10}) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.post(
        '$leadsBaseUrl/leads/search/global',
        queryParameters: {
          'page': page,
          'size': size,
        },
        data: {
          'query': query.trim().isEmpty ? null : query.trim(),
          'isLead': true,
          'isCustomer': false,
          'isUser': false,
          'isFollowup': false,
        },
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content;
        if (body['data'] is List) {
          content = body['data'];
        } else if (body['data'] is Map && body['data']['content'] is List) {
          content = body['data']['content'];
        } else {
          content = [];
        }

        final q = query.trim().toLowerCase();
        final leads = content
            .map((json) => LeadModel.fromJson(json))
            .where((lead) {
              if (q.isEmpty) return true;
              final fullName = '${lead.firstName} ${lead.lastName}'.toLowerCase();
              final phone = lead.phone.toLowerCase();
              final email = lead.email.toLowerCase();
              final company = lead.companyName.toLowerCase();
              return fullName.contains(q) || phone.contains(q) || email.contains(q) || company.contains(q);
            })
            .toList();
        return Right(leads);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to search leads');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getLeadPriorities() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/priorities');
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
  Future<Either<Failure, List<StaffUser>>> getStaffUsers({String? search}) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      
      final queryParameters = <String, dynamic>{};
      if (search != null && search.isNotEmpty) {
        queryParameters['search'] = search;
      }

      final response = await apiClient.get(
        '$identityBaseUrl/users/dropdown',
        queryParameters: queryParameters,
      );

      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        List<dynamic> content;
        if (body['data'] is List) {
          content = body['data'];
        } else if (body['data'] is Map && body['data']['content'] != null) {
          content = body['data']['content'];
        } else {
          content = [];
        }
        final users = content.map((json) => StaffUser.fromJson(json)).toList();
        return Right(users);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load staff users');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createLead(Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName}) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();

      final leadJson = jsonEncode(leadData);
      final jsonFileName = (leadFileName != null && leadFileName.isNotEmpty) ? leadFileName : 'test.json';

      formData.files.add(MapEntry(
        'lead',
        MultipartFile.fromString(
          leadJson,
          filename: jsonFileName,
          contentType: MediaType('application', 'json'),
        ),
      ));

      for (var path in filePaths) {
        if (path.isNotEmpty) {
          final filename = path.split('/').last.split('\\').last;
          formData.files.add(MapEntry(
            'attachments',
            await MultipartFile.fromFile(
              path,
              filename: filename,
            ),
          ));
          formData.files.add(MapEntry(
            'files',
            await MultipartFile.fromFile(
              path,
              filename: filename,
            ),
          ));
        }
      }

      final response = await apiClient.post(
        '$leadsBaseUrl/leads',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to create lead');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateLead(String leadId, Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName}) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();

      final leadJson = jsonEncode(leadData);
      final jsonFileName = (leadFileName != null && leadFileName.isNotEmpty) ? leadFileName : 'test.json';

      formData.files.add(MapEntry(
        'lead',
        MultipartFile.fromString(
          leadJson,
          filename: jsonFileName,
          contentType: MediaType('application', 'json'),
        ),
      ));

      if (leadData.containsKey('ownerUserId') && leadData['ownerUserId'] != null) {
        formData.fields.add(MapEntry('uploadedBy', leadData['ownerUserId'].toString()));
      }

      for (var path in filePaths) {
        if (path.isNotEmpty) {
          final filename = path.split('/').last.split('\\').last;
          formData.files.add(MapEntry(
            'attachments',
            await MultipartFile.fromFile(
              path,
              filename: filename,
            ),
          ));
          formData.files.add(MapEntry(
            'files',
            await MultipartFile.fromFile(
              path,
              filename: filename,
            ),
          ));
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
      final response = await apiClient.get('$leadsBaseUrl/leads/$id');

      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final leadDetail = LeadDetailModel.fromJson(body['data']);
        return Right(leadDetail);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load lead details');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, AuditLogResponse>> getLeadAuditLogs(String id, {int page = 0, int size = 20}) async {
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
        throw ApiException(message: body['message'] ?? 'Failed to load audit logs');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Attachment>>> getLeadAttachments(String id) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/leads/$id/attachments');

      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final attachments = content.map((json) => AttachmentModel.fromJson(json)).toList();
        return Right(attachments);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load attachments');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> uploadLeadAttachment(String leadId, String filePath) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();
      final filename = filePath.split('/').last.split('\\').last;

      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(
          filePath,
          filename: filename,
        ),
      ));

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/$leadId/attachments',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to upload attachment');
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
  Future<Either<Failure, List<LeadAudio>>> getLeadAudios(String leadId) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/leads/$leadId/audios');

      final body = response.data;
      List<dynamic> listData = [];
      if (body is List) {
        listData = body;
      } else if (body is Map<String, dynamic>) {
        if (body['data'] is List) {
          listData = body['data'];
        } else if (body['content'] is List) {
          listData = body['content'];
        }
      }

      final audios = listData.map((json) => LeadAudioModel.fromJson(json)).toList();
      return Right(audios);
    } on DioException catch (e) {
      if (e.response?.statusCode == 500) {
        return const Right([]);
      }
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LeadAudio>> uploadLeadAudio(String leadId, String filePath) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final formData = FormData();
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

      final multipartFile1 = await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: MediaType('audio', ext),
      );
      final multipartFile2 = await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: MediaType('audio', ext),
      );

      formData.files.add(MapEntry('files', multipartFile1));
      formData.files.add(MapEntry('file', multipartFile2));

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/$leadId/audios',
        data: formData,
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
            } else if (dataVal is List && dataVal.isNotEmpty && dataVal.first is Map<String, dynamic>) {
              dataJson = dataVal.first as Map<String, dynamic>;
            }
          } else {
            dataJson = body;
          }
        } else if (body is List && body.isNotEmpty && body.first is Map<String, dynamic>) {
          dataJson = body.first as Map<String, dynamic>;
        }
        final audioModel = LeadAudioModel.fromJson(dataJson);
        return Right(audioModel);
      } else {
        throw ApiException(message: 'Failed to upload audio file');
      }
    } on DioException catch (e) {
      String msg = 'Upload failed';
      if (e.response != null && e.response?.data is Map) {
        msg = e.response?.data['message'] ?? 'Server error ${e.response?.statusCode}';
      } else if (e.response != null) {
        msg = 'Server status ${e.response?.statusCode}';
      }
      return Left(ServerFailure(msg));
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateLeadActiveStatus(String leadId, bool isActive) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.put(
        '$leadsBaseUrl/leads/$leadId/active-status?isActive=$isActive',
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to update lead status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, String>> exportLeadReport(Map<String, dynamic> payload) async {
    final leadsBaseUrl = _leadsBaseUrl;
    final url = '$leadsBaseUrl/leads/export/csv';
    debugPrint('[LeadsRepo] Calling POST $url with payload $payload');
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.csv';
      
      await apiClient.download(
        url,
        savePath,
        data: payload,
        options: Options(
          method: 'POST',
        ),
      );
      
      debugPrint('[LeadsRepo] Successfully downloaded export to $savePath');
      return Right(savePath);
    } catch (e) {
      debugPrint('[LeadsRepo] export error: $e');
      return const Left(ServerFailure('Failed to download export file.'));
    }
  }

  @override
  Future<Either<Failure, List<PipelineColumnData>>> getLeadPipeline({int page = 0, int size = 50}) async {
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
            .map((e) => PipelineColumnData.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map)))
            .toList();
        columns.sort((a, b) => a.status.displayOrder.compareTo(b.status.displayOrder));
        return Right(columns);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to fetch pipeline data');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateLeadStatusInPipeline(String leadId, String statusId) async {
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
        } else if (body['message'] != null && body['message'].toString().trim().isNotEmpty) {
          return Left(ServerFailure(body['message'].toString().trim()));
        }
      }
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        try {
          final formData = FormData();
          final leadJson = jsonEncode({'statusId': statusId});
          formData.files.add(MapEntry(
            'lead',
            MultipartFile.fromString(
              leadJson,
              filename: 'test.json',
              contentType: MediaType('application', 'json'),
            ),
          ));

          final response = await apiClient.put(
            '$leadsBaseUrl/leads/$leadId',
            data: formData,
          );

          final body = response.data;
          if (body != null && body['success'] == true) {
            return const Right(null);
          } else {
            return Left(ServerFailure(body?['message'] ?? 'Failed to update lead status'));
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
  Future<Either<Failure, DialpadLeadSearchResult>> searchLeadByNumber(String phoneNumber) async {
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
  Future<Either<Failure, void>> quickInviteLead(Map<String, dynamic> data) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.post(
        '$leadsBaseUrl/leads/quick-invite',
        data: data,
      );

      final body = response.data;
      if (body != null && (body['success'] == true || body['statusCode'] == 200 || body['statusCode'] == 201)) {
        return const Right(null);
      } else {
        return Left(ServerFailure(body?['message'] ?? 'Failed to send quick invite'));
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error sending quick invite: $e'));
    }
  }
}
