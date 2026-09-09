import 'dart:io';
import 'package:dio/dio.dart';
import 'api_exception.dart';
import '../error/failure.dart';

class ErrorHandler {
  static ApiException handle(dynamic error) {
    if (error is DioException) {
      return _handleDioError(error);
    } else if (error is SocketException) {
      return ApiException(message: 'No Internet connection');
    } else if (error is FormatException) {
      return ApiException(message: 'JSON Parsing Error');
    } else {
      return ApiException(message: 'Unknown error occurred: $error');
    }
  }

  static ApiException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return ApiException(message: 'Connection timeout');
      case DioExceptionType.sendTimeout:
        return ApiException(message: 'Send timeout');
      case DioExceptionType.receiveTimeout:
        return ApiException(message: 'Receive timeout');
      case DioExceptionType.badCertificate:
        return ApiException(message: 'Bad certificate');
      case DioExceptionType.badResponse:
        return _handleStatusCode(error.response?.statusCode, error.response?.data);
      case DioExceptionType.cancel:
        return ApiException(message: 'Request to API server was cancelled');
      case DioExceptionType.connectionError:
        return ApiException(message: 'Connection error');
      case DioExceptionType.transformTimeout:
        return ApiException(message: 'Transform timeout');
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return ApiException(message: 'No Internet connection');
        }
        return ApiException(message: 'Unknown API error');
    }
  }

  static ApiException _handleStatusCode(int? statusCode, dynamic data) {
    String defaultMessage = 'Something went wrong';
    if (data is Map<String, dynamic>) {
      if (data['message'] != null && data['message'].toString().trim().isNotEmpty) {
        defaultMessage = data['message'].toString().trim();
      } else if (data['error'] != null && data['error'].toString().trim().isNotEmpty) {
        defaultMessage = data['error'].toString().trim();
      } else if (data['detail'] != null && data['detail'].toString().trim().isNotEmpty) {
        defaultMessage = data['detail'].toString().trim();
      }
    } else if (data is String && data.trim().isNotEmpty) {
      defaultMessage = data.trim();
    }

    final hasServerMessage = !defaultMessage.startsWith('Something went wrong');

    switch (statusCode) {
      case 400:
        return ApiException(message: defaultMessage, statusCode: 400);
      case 401:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Unauthorized access', statusCode: 401);
      case 403:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Forbidden request', statusCode: 403);
      case 404:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Resource not found', statusCode: 404);
      case 409:
        return ApiException(message: defaultMessage, statusCode: 409);
      case 422:
        return ApiException(message: defaultMessage, statusCode: 422);
      case 429:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Too many requests', statusCode: 429);
      case 500:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Internal server error', statusCode: 500);
      case 502:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Bad gateway', statusCode: 502);
      case 503:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Service unavailable', statusCode: 503);
      case 504:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Gateway timeout', statusCode: 504);
      default:
        return ApiException(message: defaultMessage, statusCode: statusCode);
    }
  }

  static Failure mapExceptionToFailure(Object e) {
    if (e is ApiException) {
      return ServerFailure(e.message);
    } else if (e is DioException) {
      return ServerFailure(handle(e).message);
    }
    return ServerFailure(e.toString());
  }
}
