import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/customer.dart';

abstract class CustomerRepository {
  Future<Either<Failure, List<Customer>>> getCustomers({int page = 0, int size = 20, String? searchQuery});
  Future<Either<Failure, List<String>>> getCustomerTypes();
  Future<Either<Failure, void>> createCustomer(Map<String, dynamic> customerData);
  Future<Either<Failure, void>> updateCustomer(String id, Map<String, dynamic> customerData);
  Future<Either<Failure, void>> deleteCustomer(String id);
}

class CustomerRepositoryImpl implements CustomerRepository {
  final ApiClient apiClient;

  CustomerRepositoryImpl({required this.apiClient});

  String get _baseUrl {
    final baseUrl = dotenv.env['BASE_URL'] ?? '';
    return baseUrl.replaceAll('lead-service', 'customer-service');
  }

  @override
  Future<Either<Failure, List<Customer>>> getCustomers({int page = 0, int size = 20, String? searchQuery}) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'size': size,
      };
      
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        queryParams['search'] = searchQuery.trim();
      }

      final response = await apiClient.get(
        '$_baseUrl/customers',
        queryParameters: queryParams,
      );
      
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final List<dynamic> content = body['data']['content'] ?? body['data']; // Handling both paginated and list responses
        final customers = content.map((json) => Customer.fromJson(json)).toList();
        return Right(customers);
      } else {
        throw ApiException(message: body['message'] ?? 'Failed to load customers');
      }
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
