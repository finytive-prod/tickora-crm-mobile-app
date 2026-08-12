import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/error_handler.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/staff_user.dart';
import '../../domain/repositories/leads_repository.dart';
import '../../domain/entities/custom_field.dart';
import '../models/custom_field_model.dart';
import '../models/lead_model.dart';

import '../../domain/entities/lead_detail.dart';
import '../models/lead_detail_model.dart';
import '../../domain/entities/activity_lead.dart';
import '../models/activity_lead_model.dart';
import '../../domain/entities/attachment.dart';
import '../models/attachment_model.dart';

class LeadsRepositoryImpl implements LeadsRepository {
  final ApiClient apiClient;

  LeadsRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, List<Lead>>> getLeads(int page, int size, {String? statusId}) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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

  @override
  Future<Either<Failure, List<LeadSource>>> getLeadSources() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/sources');
      
      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final sources = content.map((json) => LeadSourceModel.fromJson(json)).toList();
        return Right(sources);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load sources');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getLeadPriorities() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/leads/priorities');
      
      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final priorities = content.map((e) => e.toString()).toList();
        return Right(priorities);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load priorities');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
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
        final List<dynamic> content = body['data'];
        final staffUsers = content.map((json) => StaffUser.fromJson(json)).toList();
        return Right(staffUsers);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load staff users');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<CustomField>>> getCustomFieldsForm() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/custom-fields/form');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null && body['data']['customFields'] != null) {
        final List<dynamic> content = body['data']['customFields'];
        final fields = content.map((json) => CustomFieldModel.fromJson(json)).toList();
        return Right(fields);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load custom fields');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<CustomField>>> getCustomFields() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/custom-fields');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final fields = content.map((json) => CustomFieldModel.fromJson(json)).toList();
        return Right(fields);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load custom fields settings');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createCustomFields(List<Map<String, dynamic>> fields) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.post(
        '$leadsBaseUrl/lead-settings/custom-fields',
        data: fields,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to create custom fields');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateCustomFields(List<Map<String, dynamic>> fields) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.put(
        '$leadsBaseUrl/lead-settings/custom-fields',
        data: fields,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to update custom fields');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> reorderLeadStatus(String id, int displayOrder) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.patch(
        '$leadsBaseUrl/lead-settings/statuses/$id/reorder',
        queryParameters: {'displayOrder': displayOrder},
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to reorder status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> setDefaultLeadStatus(String id) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.patch(
        '$leadsBaseUrl/lead-settings/statuses/$id/set-default',
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to set default status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createLeadStatus(Map<String, dynamic> statusData) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.post(
        '$leadsBaseUrl/lead-settings/statuses',
        data: statusData,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to create lead status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getCustomFieldTypes() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/custom-fields/field-types');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final types = content.map((e) => e.toString()).toList();
        return Right(types);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load custom field types');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createLead(Map<String, dynamic> leadData, List<String> filePaths, {String? leadFileName}) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      
      final leadJson = jsonEncode(leadData);
      debugPrint('--- Lead JSON Payload ---');
      debugPrint(const JsonEncoder.withIndent('  ').convert(leadData));
      debugPrint('-------------------------');

      // Build multipart form data
      final formData = FormData();

      // Part 1: 'lead' — JSON string sent as a Blob with application/json content type
      formData.files.add(MapEntry(
        'lead',
        MultipartFile.fromString(
          leadJson,
          contentType: MediaType('application', 'json'),
        ),
      ));

      // Part 2: 'files' — one or more uploaded file attachments
      for (final filePath in filePaths) {
        final fileName = filePath.split('/').last.split('\\').last;
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(filePath, filename: fileName),
        ));
      }

      // POST — do NOT manually set Content-Type; Dio sets multipart boundary automatically
      final response = await apiClient.post(
        '$leadsBaseUrl/leads',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to create lead');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LeadDetail>> getLeadDetails(String id) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get(
        '$leadsBaseUrl/leads/$id',
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final leadDetail = LeadDetailModel.fromJson(body['data']);
        return Right(leadDetail);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load lead details');
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
        queryParameters: {
          'page': page,
          'size': size,
        },
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final auditLogs = AuditLogResponseModel.fromJson(body['data']);
        return Right(auditLogs);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load audit logs');
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
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> dataList = body['data'];
        final attachments = dataList.map((json) => AttachmentModel.fromJson(json)).toList();
        return Right(attachments);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load attachments');
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
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(filePath),
      ));

      final response = await apiClient.post(
        '$leadsBaseUrl/leads/$leadId/attachments',
        data: formData,
      );

      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to upload document');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
