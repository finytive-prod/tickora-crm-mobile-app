import 'package:dartz/dartz.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/customer.dart';
import 'package:crm_mobile/core/network/api_constants.dart';

abstract class CustomerRepository {
  Future<Either<Failure, CustomerListResponse>> getCustomers({int page = 0, int size = 20, String? searchQuery});
  Future<Either<Failure, Customer>> getCustomerById(String id);
  Future<Either<Failure, List<String>>> getCustomerTypes();
  Future<Either<Failure, void>> createCustomer(Map<String, dynamic> customerData);
  Future<Either<Failure, void>> updateCustomer(String id, Map<String, dynamic> customerData);
  Future<Either<Failure, void>> deleteCustomer(String id);
}

class CustomerRepositoryImpl implements CustomerRepository {
  final ApiClient apiClient;

  CustomerRepositoryImpl({required this.apiClient});

  String get _baseUrl => ApiUrl.customerService;

  @override
  Future<Either<Failure, CustomerListResponse>> getCustomers({int page = 0, int size = 20, String? searchQuery}) async {
    try {
      final customerBaseUrl = _baseUrl;
      final q = (searchQuery != null && searchQuery.trim().isNotEmpty) ? searchQuery.trim() : null;

      // 1. Primary: Fetch directly from customer-service with sorting newest first
      try {
        final queryParams = <String, dynamic>{
          'page': page,
          'size': size,
          'sort': 'createdAt,desc',
        };
        if (q != null && q.isNotEmpty) {
          queryParams['search'] = q;
          queryParams['query'] = q;
        }

        final response = await apiClient.get(
          '$customerBaseUrl/customers',
          queryParameters: queryParams,
        );

        final body = response.data;
        if (body != null && (body['success'] == true || response.statusCode == 200)) {
          final dynamic dataField = (body is Map && body.containsKey('data') && body['data'] != null)
              ? body['data']
              : body;
          final List<dynamic> content;
          if (dataField is List) {
            content = dataField;
          } else if (dataField is Map && dataField['content'] is List) {
            content = dataField['content'];
          } else if (dataField is Map && dataField['customers'] is List) {
            content = dataField['customers'];
          } else {
            content = [];
          }
          final customers = content
              .where((json) => json is Map)
              .map((json) => Customer.fromJson(Map<String, dynamic>.from(json as Map)))
              .toList();

          int? totalCount;
          int totalPages = 1;

          if (dataField is Map) {
            final rawTotal = dataField['totalElements'] ??
                dataField['totalCount'] ??
                dataField['total'] ??
                dataField['totalRecords'] ??
                dataField['count'];
            if (rawTotal != null) {
              totalCount = int.tryParse(rawTotal.toString());
            }
            final rawPages = dataField['totalPages'] ?? dataField['pages'];
            if (rawPages != null) {
              totalPages = int.tryParse(rawPages.toString()) ?? 1;
            }
          }

          if (totalCount == null && body is Map) {
            final rawTotal = body['totalElements'] ??
                body['totalCount'] ??
                body['total'] ??
                body['totalRecords'] ??
                body['count'];
            if (rawTotal != null) {
              totalCount = int.tryParse(rawTotal.toString());
            }
            final rawPages = body['totalPages'] ?? body['pages'];
            if (rawPages != null) {
              totalPages = int.tryParse(rawPages.toString()) ?? 1;
            }
          }

          totalCount ??= customers.length;

          return Right(CustomerListResponse(
            customers: customers,
            totalCount: totalCount,
            totalPages: totalPages,
            currentPage: page,
          ));
        }
      } catch (_) {}

      // 2. Fallback: Query global search from lead-service
      final leadsBaseUrl = ApiUrl.leadService;
      final response = await apiClient.post(
        '$leadsBaseUrl/leads/search/global',
        queryParameters: {
          'page': page,
          'size': size,
        },
        data: {
          'query': q,
          'isLead': false,
          'isCustomer': true,
          'isUser': false,
          'isFollowup': false,
        },
      );
      
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200)) {
        final dynamic dataField = (body is Map && body.containsKey('data') && body['data'] != null)
            ? body['data']
            : body;
        final List<dynamic> content;
        if (dataField is List) {
          content = dataField;
        } else if (dataField is Map && dataField['content'] is List) {
          content = dataField['content'];
        } else {
          content = [];
        }

        var customers = content
            .where((json) => json is Map)
            .map((json) => Customer.fromJson(Map<String, dynamic>.from(json as Map)))
            .toList();
        if (q != null && q.isNotEmpty) {
          final queryLower = q.toLowerCase();
          customers = customers.where((c) {
            final name = c.customerName.toLowerCase();
            final company = c.companyName.toLowerCase();
            final phone = c.phone.toLowerCase();
            final email = c.email.toLowerCase();
            return name.contains(queryLower) || company.contains(queryLower) || phone.contains(queryLower) || email.contains(queryLower);
          }).toList();
        }

        int? totalCount;
        int totalPages = 1;
        if (dataField is Map) {
          final rawTotal = dataField['totalElements'] ?? dataField['totalCount'] ?? dataField['total'];
          if (rawTotal != null) totalCount = int.tryParse(rawTotal.toString());
          final rawPages = dataField['totalPages'] ?? dataField['pages'];
          if (rawPages != null) totalPages = int.tryParse(rawPages.toString()) ?? 1;
        }
        totalCount ??= customers.length;

        return Right(CustomerListResponse(
          customers: customers,
          totalCount: totalCount,
          totalPages: totalPages,
          currentPage: page,
        ));
      } else {
        throw ApiException(message: body?['message'] ?? 'Failed to load customers');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Customer>> getCustomerById(String id) async {
    try {
      final response = await apiClient.get('$_baseUrl/customers/$id');
      final body = response.data;
      if (body != null && (body['success'] == true || response.statusCode == 200) && body['data'] != null) {
        final Map<String, dynamic> data = body['data'] is Map<String, dynamic>
            ? body['data']
            : (body['data'] is List && (body['data'] as List).isNotEmpty ? (body['data'] as List).first : {});
        return Right(Customer.fromJson(data));
      }
      throw ApiException(message: body?['message'] ?? 'Failed to load customer details');
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getCustomerTypes() async {
    try {
      final response = await apiClient.get('$_baseUrl/customers/types');
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data'];
        final types = content.map((e) => e.toString()).toList();
        return Right(types);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load customer types');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> createCustomer(Map<String, dynamic> customerData) async {
    try {
      final response = await apiClient.post(
        '$_baseUrl/customers',
        data: customerData,
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return const Right(null);
      } else {
        throw ApiException(message: 'Failed to create customer');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateCustomer(String id, Map<String, dynamic> customerData) async {
    try {
      final response = await apiClient.put(
        '$_baseUrl/customers/$id',
        data: customerData,
      );
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        return const Right(null);
      } else {
        throw ApiException(message: 'Failed to update customer');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCustomer(String id) async {
    try {
      final response = await apiClient.delete('$_baseUrl/customers/$id');
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        return const Right(null);
      } else {
        throw ApiException(message: 'Failed to delete customer');
      }
    } on Exception catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
