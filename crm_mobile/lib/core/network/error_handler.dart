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
        return ApiException(message: 'Connection timed out. Please check your internet connection.');
      case DioExceptionType.sendTimeout:
        return ApiException(message: 'Send request timed out. Please try again.');
      case DioExceptionType.receiveTimeout:
        return ApiException(message: 'Server response timed out. Please try again.');
      case DioExceptionType.badCertificate:
        return ApiException(message: 'Bad certificate');
      case DioExceptionType.badResponse:
        return _handleStatusCode(error.response?.statusCode, error.response?.data);
      case DioExceptionType.cancel:
        return ApiException(message: 'Request was cancelled');
      case DioExceptionType.connectionError:
        return ApiException(message: 'Unable to connect to server. Please check your internet connection.');
      case DioExceptionType.transformTimeout:
        return ApiException(message: 'Data processing timed out');
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return ApiException(message: 'No Internet connection. Please check your network.');
        }
        return ApiException(message: 'Network error occurred. Please try again.');
    }
  }

  static String cleanErrorMessage(String rawMessage) {
    if (rawMessage.trim().isEmpty) return 'An unexpected error occurred.';

    final trimmed = rawMessage.trim();

    // 1. Extract "message": "..." from embedded JSON strings
    final messageRegex = RegExp(r'"message"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"');
    final messageMatch = messageRegex.firstMatch(trimmed);
    if (messageMatch != null && messageMatch.group(1) != null) {
      final extracted = messageMatch.group(1)!.replaceAll(r'\"', '"').trim();
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }

    // 2. Extract "error": "..." from embedded JSON strings
    final errorRegex = RegExp(r'"error"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"');
    final errorMatch = errorRegex.firstMatch(trimmed);
    if (errorMatch != null && errorMatch.group(1) != null) {
      final extracted = errorMatch.group(1)!.replaceAll(r'\"', '"').trim();
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }

    // 3. Handle common HTTP / Feign Client 403 / 401 patterns
    if (trimmed.contains('403') || trimmed.toLowerCase().contains('access denied')) {
      return 'Access Denied: You do not have sufficient privileges.';
    }
    if (trimmed.contains('401') || trimmed.toLowerCase().contains('unauthorized')) {
      return 'Session expired or unauthorized access. Please log in again.';
    }

    // 4. Strip technical Feign client log prefixes like [403] during [GET] to [http://...]:
    if (trimmed.contains(']: ')) {
      final afterColon = trimmed.split(']: ').last.trim();
      if (afterColon.isNotEmpty && !afterColon.startsWith('[')) {
        return afterColon;
      }
    }

    return trimmed;
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
      defaultMessage = cleanErrorMessage(data);
    }

    defaultMessage = cleanErrorMessage(defaultMessage);

    final hasServerMessage = !defaultMessage.startsWith('Something went wrong');

    switch (statusCode) {
      case 400:
        return ApiException(message: defaultMessage, statusCode: 400);
      case 401:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Unauthorized access', statusCode: 401);
      case 403:
        return ApiException(message: hasServerMessage ? defaultMessage : 'Access Denied: You do not have sufficient privileges.', statusCode: 403);
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
      return ServerFailure(cleanErrorMessage(e.message));
    } else if (e is DioException) {
      return ServerFailure(cleanErrorMessage(handle(e).message));
    }
    return ServerFailure(cleanErrorMessage(e.toString()));
  }
}
