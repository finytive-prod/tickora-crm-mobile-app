import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/staff_personal_number.dart';

abstract class StaffPersonalNumbersRepository {
  Future<Either<Failure, List<StaffPersonalNumber>>> getStaffPersonalNumbers({
    int page = 0,
    int size = 50,
    String? search,
    bool? isActive = true,
  });

  Future<Either<Failure, StaffPersonalNumber>> getStaffPersonalNumberById(String id);

  Future<Either<Failure, StaffPersonalNumber>> createStaffPersonalNumber({
    String? userId,
    required String phoneNumber,
    required String contactName,
    String? notes,
    bool isActive = true,
  });

  Future<Either<Failure, StaffPersonalNumber>> updateStaffPersonalNumber(
    String id, {
    String? userId,
    required String phoneNumber,
    required String contactName,
    String? notes,
    bool isActive = true,
  });

  Future<Either<Failure, void>> deleteStaffPersonalNumber(String id);
}

class StaffPersonalNumbersRepositoryImpl implements StaffPersonalNumbersRepository {
  final ApiClient apiClient;

  StaffPersonalNumbersRepositoryImpl({required this.apiClient});

  static const String _cacheKey = 'cached_blocked_personal_numbers_v1';
  static final Set<String> _cachedBlockedDigits = {};
  static bool _cacheInitialized = false;

  String get _baseUrl => ApiUrl.leadService;

  /// Helper to check if a given phone number is blocked from recording/call-log tracking.
  static Future<bool> isNumberBlocked(String rawNumber) async {
    final cleanDigits = rawNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.isEmpty) return false;
    final last10 = cleanDigits.length >= 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;

    await _ensureCacheLoaded();
    return _cachedBlockedDigits.contains(last10);
  }

  static Future<void> _ensureCacheLoaded() async {
    if (_cacheInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_cacheKey) ?? [];
      _cachedBlockedDigits.addAll(list);
      _cacheInitialized = true;
    } catch (_) {}
  }

  static Future<void> _updateCache(List<StaffPersonalNumber> numbers) async {
    final Set<String> activeDigits = {};
    for (final n in numbers) {
      if (n.isActive) {
        final digits = n.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final last10 = digits.length >= 10
            ? digits.substring(digits.length - 10)
            : digits;
        if (last10.isNotEmpty) activeDigits.add(last10);
      }
    }
    _cachedBlockedDigits
      ..clear()
      ..addAll(activeDigits);
    _cacheInitialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cacheKey, activeDigits.toList());
    } catch (_) {}
  }

  static Future<void> _addOrUpdateNumberInCache(String phone, bool isActive) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final last10 = digits.length >= 10
        ? digits.substring(digits.length - 10)
        : digits;
    if (last10.isEmpty) return;

    await _ensureCacheLoaded();
    if (isActive) {
      _cachedBlockedDigits.add(last10);
    } else {
      _cachedBlockedDigits.remove(last10);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cacheKey, _cachedBlockedDigits.toList());
    } catch (_) {}
  }

  static Future<void> removeNumberFromCache(String phone) async {
    await _addOrUpdateNumberInCache(phone, false);
  }

  @override
  Future<Either<Failure, List<StaffPersonalNumber>>> getStaffPersonalNumbers({
    int page = 0,
    int size = 50,
    String? search,
    bool? isActive = true,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'page': page,
        'size': size,
        'sortBy': 'createdAt',
        'sortDir': 'desc',
      };
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
      if (isActive != null) {
        queryParams['isActive'] = isActive;
      }

      final response = await apiClient.get(
        '$_baseUrl/staff-personal-numbers',
        queryParameters: queryParams,
      );

      final body = response.data;
      if (body != null && body is Map<String, dynamic>) {
        final data = body['data'];
        List<dynamic> content = [];
        if (data is Map<String, dynamic> && data['content'] is List) {
          content = data['content'] as List<dynamic>;
        } else if (data is List) {
          content = data;
        }

        final numbers = content
            .map((item) => StaffPersonalNumber.fromJson(item as Map<String, dynamic>))
            .toList();

        // Sync local cache for instant call blocking
        unawaited(_updateCache(numbers));

        return Right(numbers);
      }
      return const Right([]);
    } on DioException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Failed to fetch personal numbers: $e'));
    }
  }

  @override
  Future<Either<Failure, StaffPersonalNumber>> getStaffPersonalNumberById(String id) async {
    try {
      final response = await apiClient.get('$_baseUrl/staff-personal-numbers/$id');
      final body = response.data;
      if (body != null && body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final number = StaffPersonalNumber.fromJson(body['data'] as Map<String, dynamic>);
        return Right(number);
      }
      return const Left(ServerFailure('Staff personal number not found'));
    } on DioException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Error fetching personal number: $e'));
    }
  }

  @override
  Future<Either<Failure, StaffPersonalNumber>> createStaffPersonalNumber({
    String? userId,
    required String phoneNumber,
    required String contactName,
    String? notes,
    bool isActive = true,
  }) async {
    try {
      final data = <String, dynamic>{
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
        'phoneNumber': phoneNumber.trim(),
        if (contactName.trim().isNotEmpty) 'contactName': contactName.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

      final response = await apiClient.post(
        '$_baseUrl/staff-personal-numbers',
        data: data,
      );

      final body = response.data;
      if (body != null && body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final created = StaffPersonalNumber.fromJson(body['data'] as Map<String, dynamic>);
        unawaited(_addOrUpdateNumberInCache(created.phoneNumber, created.isActive));
        return Right(created);
      }

      // Fallback response parsing if data is wrapped differently
      final fallback = StaffPersonalNumber(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        phoneNumber: phoneNumber.trim(),
        contactName: contactName.trim(),
        notes: notes?.trim(),
        isActive: isActive,
      );
      unawaited(_addOrUpdateNumberInCache(phoneNumber, isActive));
      return Right(fallback);
    } on DioException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Failed to create personal number: $e'));
    }
  }

  @override
  Future<Either<Failure, StaffPersonalNumber>> updateStaffPersonalNumber(
    String id, {
    String? userId,
    required String phoneNumber,
    required String contactName,
    String? notes,
    bool isActive = true,
  }) async {
    try {
      final data = <String, dynamic>{
        if (userId != null && userId.isNotEmpty) 'userId': userId,
        'phoneNumber': phoneNumber.trim(),
        'contactName': contactName.trim(),
        'notes': notes?.trim() ?? '',
        'isActive': isActive,
      };

      final response = await apiClient.put(
        '$_baseUrl/staff-personal-numbers/$id',
        data: data,
      );

      final body = response.data;
      if (body != null && body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final updated = StaffPersonalNumber.fromJson(body['data'] as Map<String, dynamic>);
        unawaited(_addOrUpdateNumberInCache(updated.phoneNumber, updated.isActive));
        return Right(updated);
      }

      final fallback = StaffPersonalNumber(
        id: id,
        phoneNumber: phoneNumber.trim(),
        contactName: contactName.trim(),
        notes: notes?.trim(),
        isActive: isActive,
      );
      unawaited(_addOrUpdateNumberInCache(phoneNumber, isActive));
      return Right(fallback);
    } on DioException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Failed to update personal number: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteStaffPersonalNumber(String id) async {
    try {
      await apiClient.delete('$_baseUrl/staff-personal-numbers/$id');
      return const Right(null);
    } on DioException catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    } catch (e) {
      return Left(ServerFailure('Failed to delete personal number: $e'));
    }
  }
}
