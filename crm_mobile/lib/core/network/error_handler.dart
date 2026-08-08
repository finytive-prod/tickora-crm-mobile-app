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
    if (data is Map<String, dynamic> && data['message'] != null) {
      defaultMessage = data['message'];
    } else if (data is Map<String, dynamic> && data['error'] != null) {
      defaultMessage = data['error'].toString();
    }

    switch (statusCode) {
      case 400:
        return ApiException(message: 'Bad Request: $defaultMessage', statusCode: 400);
      case 401:
        return ApiException(message: 'Unauthorized access', statusCode: 401);
      case 403:
        return ApiException(message: 'Forbidden request', statusCode: 403);
      case 404:
        return ApiException(message: 'Resource not found', statusCode: 404);
      case 409:
        return ApiException(message: 'Conflict occurred', statusCode: 409);
      case 422:
        return ApiException(message: 'Unprocessable Entity: $defaultMessage', statusCode: 422);
      case 429:
        return ApiException(message: 'Too many requests', statusCode: 429);
      case 500:
        return ApiException(message: 'Internal server error', statusCode: 500);
      case 502:
        return ApiException(message: 'Bad gateway', statusCode: 502);
      case 503:
        return ApiException(message: 'Service unavailable', statusCode: 503);
      case 504:
        return ApiException(message: 'Gateway timeout', statusCode: 504);
      default:
        return ApiException(message: 'Received invalid status code: $statusCode', statusCode: statusCode);
    }
  }

  static Failure mapExceptionToFailure(Exception e) {
    if (e is ApiException) {
      return ServerFailure(e.message);
    }
    return ServerFailure(e.toString());
  }
}
