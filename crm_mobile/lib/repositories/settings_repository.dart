import 'package:dartz/dartz.dart';
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

abstract class SettingsRepository {
  Future<Either<Failure, List<CustomField>>> getCustomFieldsForm();
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

  Future<Either<Failure, List<StaffMember>>> getStaffMembers(int page, int size, String status);
  Future<Either<Failure, StaffStats>> getStaffStats();
  Future<Either<Failure, void>> updateStaffMember(String id, Map<String, dynamic> data);
  Future<Either<Failure, void>> toggleStaffStatus(String id, bool isActive);
}

class SettingsRepositoryImpl implements SettingsRepository {
  final ApiClient apiClient;

  SettingsRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, List<CustomField>>> getCustomFieldsForm() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final response = await apiClient.get('$leadsBaseUrl/lead-settings/custom-fields');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final fields = content
            .map((json) => CustomFieldModel.fromJson(json))
            .where((f) => f.active)
            .toList();
        return Right(fields);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load custom fields form');
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
        throw ApiException(message: body['message'] ?? 'Failed to load custom fields');
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
        throw ApiException(message: body['message'] ?? 'Failed to load lead statuses');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> reorderLeadStatus(String id, int displayOrder) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
        throw ApiException(message: body['message'] ?? 'Failed to load lead sources');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createLeadSource(Map<String, dynamic> sourceData) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
      final response = await apiClient.get('$identityBaseUrl/roles/dropdown');
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final roles = content.map((json) => RoleDropdownItemModel.fromJson(json)).toList();
        return Right(roles);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load roles dropdown');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, RoleDetail>> getRoleDetails(String id) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
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
  Future<Either<Failure, List<StaffMember>>> getStaffMembers(int page, int size, String status) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
      final queryParams = <String, dynamic>{
        'page': page,
        'size': size,
      };
      if (status.toUpperCase() == 'INACTIVE') {
        queryParams['isActive'] = false;
        queryParams['status'] = 'INACTIVE';
      } else {
        queryParams['isActive'] = true;
        queryParams['status'] = 'ACTIVE';
      }

      final response = await apiClient.get(
        '$identityBaseUrl/users/staff',
        queryParameters: queryParams,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final staff = content.map((json) => StaffMemberModel.fromJson(json)).toList();
        return Right(staff);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load staff members');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateStaffMember(String id, Map<String, dynamic> data) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
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
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final identityBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'identity-service');
      
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
