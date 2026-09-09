import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/lead_model.dart';
import 'package:crm_mobile/models/custom_field.dart';
import 'package:crm_mobile/models/custom_field_model.dart';
import 'package:crm_mobile/models/permission_module.dart';
import 'package:crm_mobile/models/role_entity.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/models/staff_stats.dart';

import 'package:crm_mobile/models/lead_form_layout.dart';
import 'package:crm_mobile/core/network/api_constants.dart';

abstract class SettingsRepository {
  Future<Either<Failure, LeadFormLayout>> getCustomFieldsForm();
  Future<Either<Failure, List<CustomField>>> getCustomFields();
  Future<Either<Failure, void>> createCustomFields(List<Map<String, dynamic>> fields);
  Future<Either<Failure, void>> updateCustomFields(List<Map<String, dynamic>> fields);
  Future<Either<Failure, List<String>>> getCustomFieldTypes();

  Future<Either<Failure, List<LeadStatus>>> getLeadStatuses();
  Future<Either<Failure, void>> reorderLeadStatus(String id, int displayOrder);
  Future<Either<Failure, void>> setDefaultLeadStatus(String id);
  Future<Either<Failure, void>> createLeadStatus(Map<String, dynamic> statusData);

  Future<Either<Failure, List<LeadSource>>> getLeadSources();
  Future<Either<Failure, void>> createLeadSource(Map<String, dynamic> sourceData);
  Future<Either<Failure, void>> deleteLeadSource(String id);
  Future<Either<Failure, List<String>>> getLeadSourceCategories();

  Future<Either<Failure, List<PermissionModule>>> getPermissionModules();
  Future<Either<Failure, List<RoleDropdownItem>>> getRolesDropdown();
  Future<Either<Failure, RoleDetail>> getRoleDetails(String id);
  Future<Either<Failure, void>> createRole(Map<String, dynamic> roleData);
  Future<Either<Failure, void>> updateRole(String id, Map<String, dynamic> roleData);
  Future<Either<Failure, void>> reorderRolePriority(String roleId, int newPriority);

  Future<Either<Failure, List<StaffMember>>> getStaffMembers(int page, int size, String status, {String? searchQuery});
  Future<Either<Failure, StaffStats>> getStaffStats();
  Future<Either<Failure, StaffMember>> createStaffMember(Map<String, dynamic> data);
  Future<Either<Failure, void>> updateStaffMember(String id, Map<String, dynamic> data);
  Future<Either<Failure, void>> toggleStaffStatus(String id, bool isActive);
}

class SettingsRepositoryImpl implements SettingsRepository {
  final ApiClient apiClient;

  SettingsRepositoryImpl({required this.apiClient});

  String get _leadsBaseUrl => ApiUrl.leadService;
  String get _identityBaseUrl => ApiUrl.identityService;

  @override
  Future<Either<Failure, LeadFormLayout>> getCustomFieldsForm() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/custom-fields/form');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final layout = LeadFormLayout.fromJson(body['data']);
        return Right(layout);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load lead form layout');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<CustomField>>> getCustomFields() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/custom-fields');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
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
  Future<Either<Failure, void>> createCustomFields(List<Map<String, dynamic>> fields) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
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
      final leadsBaseUrl = _leadsBaseUrl;
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
  Future<Either<Failure, List<String>>> getCustomFieldTypes() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
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
  Future<Either<Failure, List<LeadStatus>>> getLeadStatuses() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/statuses');
      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final statuses = content.map((json) => LeadStatusModel.fromJson(json)).toList();
        return Right(statuses);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load lead statuses');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> reorderLeadStatus(String id, int displayOrder) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.patch('$leadsBaseUrl/lead-settings/statuses/$id/reorder?displayOrder=$displayOrder');
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to reorder lead status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> setDefaultLeadStatus(String id) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.patch('$leadsBaseUrl/lead-settings/statuses/$id/set-default');
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to set default lead status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createLeadStatus(Map<String, dynamic> statusData) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
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
  Future<Either<Failure, List<LeadSource>>> getLeadSources() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/sources');
      final body = response.data;
      if (body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final sources = content.map((json) => LeadSourceModel.fromJson(json)).toList();
        return Right(sources);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load lead sources');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createLeadSource(Map<String, dynamic> sourceData) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.post(
        '$leadsBaseUrl/lead-settings/sources',
        data: sourceData,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to create lead source');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> deleteLeadSource(String id) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.delete('$leadsBaseUrl/lead-settings/sources/$id');
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to delete lead source');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getLeadSourceCategories() async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/sources/categories');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final categories = content.map((e) => e.toString()).toList();
        return Right(categories);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load source categories');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<PermissionModule>>> getPermissionModules() async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.get('$identityBaseUrl/permissions/modules');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final modules = content.map((json) => PermissionModuleModel.fromJson(json)).toList();
        return Right(modules);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load permission modules');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<RoleDropdownItem>>> getRolesDropdown() async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      dynamic response;
      try {
        response = await apiClient.get('$identityBaseUrl/roles', queryParameters: {'page': 0, 'size': 50});
      } catch (_) {
        response = await apiClient.get('$identityBaseUrl/roles/dropdown');
      }
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        List<dynamic> content = [];
        final rawData = body['data'];
        if (rawData is List) {
          content = rawData;
        } else if (rawData is Map && rawData['content'] is List) {
          content = rawData['content'];
        }
        final roles = content.map((json) => RoleDropdownItemModel.fromJson(json)).toList();
        roles.sort((a, b) => a.priority.compareTo(b.priority));
        return Right(roles);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load roles');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, RoleDetail>> getRoleDetails(String id) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.get('$identityBaseUrl/roles/$id');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final roleDetail = RoleDetailModel.fromJson(body['data']);
        return Right(roleDetail);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load role details');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createRole(Map<String, dynamic> roleData) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.post(
        '$identityBaseUrl/roles',
        data: roleData,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to create role');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateRole(String id, Map<String, dynamic> roleData) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.put(
        '$identityBaseUrl/roles/$id',
        data: roleData,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to update role');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> reorderRolePriority(String roleId, int newPriority) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.put(
        '$identityBaseUrl/roles/$roleId/reorder?newPriority=$newPriority',
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to reorder role priority');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<StaffMember>>> getStaffMembers(int page, int size, String status, {String? searchQuery}) async {
    try {
      final leadsBaseUrl = _leadsBaseUrl;
      final identityBaseUrl = _identityBaseUrl;
      final q = (searchQuery != null && searchQuery.trim().isNotEmpty) ? searchQuery.trim() : null;

      try {
        final response = await apiClient.post(
          '$leadsBaseUrl/leads/search/global',
          queryParameters: {
            'page': page,
            'size': size,
          },
          data: {
            'query': q,
            'isLead': false,
            'isCustomer': false,
            'isUser': true,
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
          var staff = content.map((json) => StaffMemberModel.fromJson(json)).toList();

          if (q != null && q.isNotEmpty) {
            final queryLower = q.toLowerCase();
            staff = staff.where((s) {
              final name = s.fullName.toLowerCase();
              final phone = s.phone.toLowerCase();
              final email = s.email.toLowerCase();
              final username = s.username.toLowerCase();
              final code = s.userCode.toLowerCase();
              return name.contains(queryLower) || phone.contains(queryLower) || email.contains(queryLower) || username.contains(queryLower) || code.contains(queryLower);
            }).toList();
          }

          if (status.toUpperCase() == 'ACTIVE') {
            staff = staff.where((s) => s.isActive).toList();
          } else if (status.toUpperCase() == 'INACTIVE') {
            staff = staff.where((s) => !s.isActive).toList();
          }

          if (staff.isNotEmpty) {
            return Right(staff);
          }
        }
      } catch (_) {}

      final queryParams = <String, dynamic>{
        'page': page,
        'size': size,
      };
      if (status.toUpperCase() == 'INACTIVE') {
        queryParams['isActive'] = false;
      } else if (status.toUpperCase() == 'ACTIVE') {
        queryParams['isActive'] = true;
      }
      if (q != null && q.isNotEmpty) {
        queryParams['search'] = q;
      }

      final response = await apiClient.get(
        '$identityBaseUrl/users/staff',
        queryParameters: queryParams,
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
        final staff = content.map((json) => StaffMemberModel.fromJson(json)).toList();
        return Right(staff);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load staff members');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, StaffMember>> createStaffMember(Map<String, dynamic> data) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      
      dynamic response;
      try {
        response = await apiClient.post(
          '$identityBaseUrl/users',
          data: data,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          response = await apiClient.post(
            '$identityBaseUrl/users/staff',
            data: data,
          );
        } else {
          rethrow;
        }
      }

      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 201 || response.statusCode == 200)) {
        final Map<String, dynamic> staffJson = (body is Map<String, dynamic> && body.containsKey('data') && body['data'] is Map<String, dynamic>)
            ? body['data']
            : (body is Map<String, dynamic> ? body : data);
        final staffMember = StaffMemberModel.fromJson(staffJson);
        return Right(staffMember);
      } else {
        throw ApiException(message: body is Map ? (body['message'] ?? 'Failed to create staff member') : 'Failed to create staff member');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateStaffMember(String id, Map<String, dynamic> data) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.put(
        '$identityBaseUrl/users/$id',
        data: data,
      );
      
      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 204) {
        return const Right(null);
      } else {
        throw ApiException(message: 'Failed to update staff member');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> toggleStaffStatus(String id, bool isActive) async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      final response = await apiClient.put(
        '$identityBaseUrl/users/$id/status',
        queryParameters: {'isActive': isActive},
      );
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        return const Right(null);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to update staff status');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, StaffStats>> getStaffStats() async {
    try {
      final identityBaseUrl = _identityBaseUrl;
      
      dynamic responseData;
      try {
        final response = await apiClient.get('$identityBaseUrl/users/stats');
        responseData = response.data;
      } catch (_) {
        final response = await apiClient.get('$identityBaseUrl/api/v1/users/stats');
        responseData = response.data;
      }
      
      final body = responseData;
      if (body != null && body['success'] == true && body['data'] != null) {
        final stats = StaffStats.fromJson(body['data']);
        return Right(stats);
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load staff statistics');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
