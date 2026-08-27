import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
}

class LeadsRepositoryImpl implements LeadsRepository {
  final ApiClient apiClient;

  LeadsRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId, bool? isActive}) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final queryParameters = <String, dynamic>{
        'page': page,
        'size': size,
        'sort': 'createdAt,desc',
      };
      if (statusId != null) {
        queryParameters['statusId'] = statusId;
      }
      if (isActive != null) {
        queryParameters['isActive'] = isActive;
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
  Future<Either<Failure, List<Lead>>> searchLeads(String query, {int page = 0, int size = 10}) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/search',
        queryParameters: {
          'query': query,
          'page': page,
          'size': size,
          'sort': 'createdAt,desc',
        },
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null && body['data']['content'] != null) {
        final List<dynamic> content = body['data']['content'];
        final leads = content.map((json) => LeadModel.fromJson(json)).toList();
        return Right(leads);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to search leads');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getLeadPriorities() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
      
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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

      // Append uploadedBy as per the user's requirement. If we don't have the user ID readily available in the repo, 
      // the API might accept it if it's already in the leadData or we pass a hardcoded/extracted one. Wait, in the example 
      // the user provided: uploadedBy: 5ebdf6f1-ebf5-4f49-97fc-67ce1db348aa.
      // Usually, ownerUserId from leadData can be used, or the backend derives it. But to be safe with the payload 
      // structure provided by the user, we will add it if ownerUserId is present in leadData.
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
        }
      }

      final response = await apiClient.put(
        '$leadsBaseUrl/leads/$leadId',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
        final Map<String, dynamic> dataJson = (body is Map<String, dynamic> && body.containsKey('data') && body['data'] is Map<String, dynamic>)
            ? body['data']
            : (body is Map<String, dynamic> ? body : {});
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
    final baseUrl = dotenv.env['BASE_URL'] ?? '';
    final url = '$baseUrl/leads/export/csv';
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
}
