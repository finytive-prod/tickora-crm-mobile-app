import 'package:dartz/dartz.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';

abstract class CalendarRepository {
  Future<Either<Failure, List<String>>> getCalendarCategories();
  Future<Either<Failure, void>> createEvent(Map<String, dynamic> data);
  Future<Either<Failure, void>> updateEvent(String id, Map<String, dynamic> data);
  Future<Either<Failure, List<dynamic>>> getCalendarEvents(String start, String end);
  Future<Either<Failure, void>> deleteEvent(String id);
}

class CalendarRepositoryImpl implements CalendarRepository {
  final ApiClient apiClient;

  CalendarRepositoryImpl({required this.apiClient});

  @override
  Future<Either<Failure, List<String>>> getCalendarCategories() async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final taskBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'task-service');
      
      final response = await apiClient.get('$taskBaseUrl/calendar/categories');
      
      if (response.data != null && response.data['success'] == true) {
        final List<dynamic> data = response.data['data'];
        final List<String> categories = data.map((e) => e.toString()).toList();
        return Right(categories);
      } else {
        return Left(ServerFailure(response.data?['message'] ?? 'Failed to retrieve categories'));
      }
    } on ApiException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> createEvent(Map<String, dynamic> data) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final taskBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'task-service');
      
      final response = await apiClient.post(
        '$taskBaseUrl/calendar',
        data: data,
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return const Right(null);
      } else {
        return Left(ServerFailure(response.data?['message'] ?? 'Failed to create event'));
      }
    } on ApiException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateEvent(String id, Map<String, dynamic> data) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final taskBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'task-service');
      
      final response = await apiClient.put(
        '$taskBaseUrl/calendar/$id',
        data: data,
      );
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        return const Right(null);
      } else {
        return Left(ServerFailure(response.data?['message'] ?? 'Failed to update event'));
      }
    } on ApiException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<dynamic>>> getCalendarEvents(String start, String end) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final taskBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'task-service');
      
      final response = await apiClient.get(
        '$taskBaseUrl/calendar',
        queryParameters: {
          'start': start,
          'end': end,
        },
      );
      
      if (response.data != null && response.data['success'] == true) {
        return Right(response.data['data']);
      } else {
        return Left(ServerFailure(response.data?['message'] ?? 'Failed to retrieve events'));
      }
    } on ApiException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteEvent(String id) async {
    try {
      final leadsBaseUrl = dotenv.env['BASE_URL'] ?? '';
      final taskBaseUrl = leadsBaseUrl.replaceAll('lead-service', 'task-service');
      
      final response = await apiClient.delete(
        '$taskBaseUrl/calendar/$id',
      );
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        return const Right(null);
      } else {
        return Left(ServerFailure(response.data?['message'] ?? 'Failed to delete event'));
      }
    } on ApiException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
