import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/error/failure.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_exception.dart';
import 'package:crm_mobile/core/network/error_handler.dart';
import 'package:crm_mobile/models/user.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/core/utils/staff_phone_resolver.dart';
import 'package:crm_mobile/core/services/fcm_service.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/user_profile.dart';

import 'package:crm_mobile/core/services/secure_token_storage.dart';
import 'package:crm_mobile/core/services/oauth_service.dart';

abstract class LoginRepository {
  Future<Either<Failure, User>> login(String email, String password);
  Future<Either<Failure, User>> loginWithOAuthCode(String code, String codeVerifier);
  Future<Either<Failure, String>> refreshOAuthToken();
  Future<Either<Failure, void>> verifyMail(String email);
  Future<Either<Failure, void>> resetPassword(
    String email,
    String currentPassword,
    String newPassword,
  );
  Future<Either<Failure, void>> logout({String? fcmToken});
  Future<Either<Failure, UserProfile>> getProfile();
  Future<Either<Failure, UserProfile>> updateProfile(String name);
}

class LoginRepositoryImpl implements LoginRepository {
  final ApiClient apiClient;
  final SharedPreferences sharedPreferences;
  final SecureTokenStorage? secureTokenStorage;
  final OAuthService? oauthService;

  LoginRepositoryImpl({
    required this.apiClient,
    required this.sharedPreferences,
    this.secureTokenStorage,
    this.oauthService,
  });

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final loginUrl = '${ApiUrl.identityService}/auth/login';

      final response = await apiClient.post(
        loginUrl,
        data: {'username': email, 'password': password},
      );

      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final userModel = UserModel.fromJson(body['data']);
        // Save token on successful login
        await sharedPreferences.setString('token', userModel.accessToken);
        try {
          final storage = secureTokenStorage ?? (sl.isRegistered<SecureTokenStorage>() ? sl<SecureTokenStorage>() : null);
          if (storage != null) {
            await storage.saveTokens(
              accessToken: userModel.accessToken,
              refreshToken: '',
              expiresIn: userModel.expiresIn > 0 ? userModel.expiresIn : 86400,
              tokenType: userModel.tokenType.isNotEmpty ? userModel.tokenType : 'Bearer',
            );
          }
        } catch (_) {}

        // Extract userName and email from JWT
        Map<String, dynamic> decoded = {};
        try {
          final parts = userModel.accessToken.split('.');
          if (parts.length == 3) {
            final payload = parts[1];
            var normalized = base64Url.normalize(payload);
            final resp = utf8.decode(base64Url.decode(normalized));
            decoded = jsonDecode(resp);
          }
        } catch (_) {}

        // Determine real user name (without hardcoded defaults)
        String name = userModel.userName;
        if (name.isEmpty) {
          name =
              (decoded['fullName'] ??
                      decoded['name'] ??
                      decoded['preferred_username'] ??
                      decoded['username'] ??
                      decoded['sub'] ??
                      '')
                  .toString();
        }
        if (name.isEmpty && email.isNotEmpty) {
          name = email.split('@').first;
        }
        if (name.isEmpty) {
          name = 'User';
        }

        // Determine real user email (fallback to the email entered at login)
        String userEmail =
            (decoded['email'] ??
                    body['data']['email'] ??
                    body['data']['username'] ??
                    '')
                .toString();
        if (userEmail.isEmpty || !userEmail.contains('@')) {
          userEmail = email.trim();
        }

        String userPhone =
            (decoded['phone'] ??
                    decoded['phoneNumber'] ??
                    decoded['mobile'] ??
                    '')
                .toString();
        if (userPhone.isEmpty) {
          userPhone =
              (body['data']['phone'] ??
                      body['data']['phoneNumber'] ??
                      body['data']['mobile'] ??
                      body['data']['contactNumber'] ??
                      '')
                  .toString();
        }

        await sharedPreferences.setString('userName', name);
        await sharedPreferences.setString('userEmail', userEmail);
        String userRole = userModel.role;
        if (userRole.isEmpty) {
          userRole =
              (decoded['roles'] != null
                  ? (decoded['roles'] is List
                        ? (decoded['roles'] as List).join(', ')
                        : decoded['roles'].toString())
                  : decoded['role']?.toString()) ??
              body['data']?['roleName']?.toString() ??
              body['data']?['role']?.toString() ??
              '';
        }
        await sharedPreferences.setString('userRole', userRole);
        if (userModel.userId.isNotEmpty) {
          await sharedPreferences.setString('userId', userModel.userId);
        }
        if (userPhone.isNotEmpty) {
          await sharedPreferences.setString('userPhone', userPhone);
        }

        final orgId = (decoded['organizationId'] ??
                decoded['orgId'] ??
                body['data']?['organizationId'] ??
                body['data']?['orgId'] ??
                '')
            .toString();
        if (orgId.isNotEmpty) {
          await sharedPreferences.setString('organizationId', orgId);
        }

        // Sync privileges extracted from login response and token
        try {
          final List<String> extractedPrivs = PrivilegeService.parsePrivilegeList(body['data']);
          if (decoded.isNotEmpty) {
            extractedPrivs.addAll(PrivilegeService.parsePrivilegeList(decoded));
          }
          if (userModel.privileges.isNotEmpty) {
            extractedPrivs.addAll(userModel.privileges);
          }
          if (extractedPrivs.isNotEmpty && sl.isRegistered<PrivilegeService>()) {
            sl<PrivilegeService>().setPrivileges(extractedPrivs, replace: true);
          }
        } catch (_) {}

        // If phone is still not found, fetch the staff profile to get the phone number
        if (userPhone.isEmpty && userModel.userId.isNotEmpty) {
          _fetchAndSaveStaffPhone(userModel.userId);
        }

        return Right(userModel);
      } else {
        throw ApiException(message: body?['message'] ?? 'Login failed');
      }
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  /// Fetches the current staff member's profile to get their phone number.
  /// This is a fire-and-forget call that runs after login.
  void _fetchAndSaveStaffPhone(String userId) async {
    try {
      await StaffPhoneResolver.getOrFetchStaffPhone(
        apiClient: apiClient,
        prefs: sharedPreferences,
      );
    } catch (e) {
      debugPrint('Failed to fetch staff phone: $e');
    }
  }

  @override
  Future<Either<Failure, void>> verifyMail(String email) async {
    try {
      final verifyUrl = '${ApiUrl.identityService}/auth/verify-mail';

      final response = await apiClient.post(verifyUrl, data: {'email': email});

      final body = response.data;
      if (body != null &&
          (body['success'] == true || response.statusCode == 200)) {
        return const Right(null);
      } else {
        throw ApiException(
          message: body?['message'] ?? 'Failed to send reset link',
        );
      }
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword(
    String email,
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final resetUrl = '${ApiUrl.identityService}/auth/reset-password';

      final response = await apiClient.post(
        resetUrl,
        data: {
          'email': email,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );

      final body = response.data;
      if (body != null &&
          (body['success'] == true || response.statusCode == 200)) {
        return const Right(null);
      } else {
        throw ApiException(
          message: body?['message'] ?? 'Failed to reset password',
        );
      }
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, User>> loginWithOAuthCode(
    String code,
    String codeVerifier,
  ) async {
    try {
      final service = oauthService ?? sl<OAuthService>();
      final user = await service.exchangeAuthorizationCode(
        code: code,
        codeVerifier: codeVerifier,
      );
      return Right(user);
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, String>> refreshOAuthToken() async {
    try {
      final service = oauthService ?? sl<OAuthService>();
      final newToken = await service.refreshToken();
      if (newToken != null && newToken.isNotEmpty) {
        return Right(newToken);
      }
      return Left(ServerFailure('Failed to refresh authentication token'));
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> logout({String? fcmToken}) async {
    try {
      final service = oauthService ?? (sl.isRegistered<OAuthService>() ? sl<OAuthService>() : null);
      if (service != null) {
        await service.logout();
      }

      final logoutUrl = '${ApiUrl.identityService}/auth/logout';
      String? token = fcmToken;
      if (token == null || token.isEmpty) {
        token = await FcmService.instance.getToken();
      }

      try {
        await apiClient.post(
          logoutUrl,
          data: {'fcmToken': token ?? ''},
        );
      } catch (_) {}

      // Clear tokens and cached privileges
      if (secureTokenStorage != null) {
        await secureTokenStorage!.clearTokens();
      } else if (sl.isRegistered<SecureTokenStorage>()) {
        await sl<SecureTokenStorage>().clearTokens();
      }
      await sharedPreferences.remove('token');
      await sharedPreferences.remove('cached_privileges');

      return const Right(null);
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, UserProfile>> getProfile() async {
    try {
      final profileUrl = '${ApiUrl.identityService}/auth/profile';
      final response = await apiClient.get(profileUrl);
      final body = response.data;
      if (body != null && body['success'] == true && body['data'] != null) {
        final profile = UserProfile.fromJson(body['data']);
        if (profile.organizationId.isNotEmpty) {
          await sharedPreferences.setString('organizationId', profile.organizationId);
        }
        if (profile.fullName.isNotEmpty) {
          await sharedPreferences.setString('userName', profile.fullName);
        }
        if (profile.email.isNotEmpty) {
          await sharedPreferences.setString('userEmail', profile.email);
        }
        if (profile.roles.isNotEmpty) {
          await sharedPreferences.setString(
            'userRole',
            profile.roles.join(', '),
          );
        } else if (profile.designation != null &&
            profile.designation!.isNotEmpty) {
          await sharedPreferences.setString('userRole', profile.designation!);
        }
        try {
          final privs = PrivilegeService.parsePrivilegeList(body['data']);
          if (privs.isNotEmpty && sl.isRegistered<PrivilegeService>()) {
            sl<PrivilegeService>().setPrivileges(privs, replace: true);
          }
        } catch (_) {}
        return Right(profile);
      } else {
        throw ApiException(
          message: body?['message'] ?? 'Failed to fetch profile',
        );
      }
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
  

  @override
  Future<Either<Failure, UserProfile>> updateProfile(String name) async {
    try {
      final profileUrl = '${ApiUrl.identityService}/auth/profile';
      final response = await apiClient.put(profileUrl, data: {'Name': name});
      final body = response.data;
      if (body != null &&
          (body['success'] == true || response.statusCode == 200)) {
        if (body['data'] != null) {
          final profile = UserProfile.fromJson(body['data']);
          if (profile.fullName.isNotEmpty) {
            await sharedPreferences.setString('userName', profile.fullName);
          }
          return Right(profile);
        }
        return await getProfile();
      } else {
        throw ApiException(
          message: body?['message'] ?? 'Failed to update profile',
        );
      }
    } catch (e) {
      return Left(ErrorHandler.mapExceptionToFailure(e));
    }
  }
}
