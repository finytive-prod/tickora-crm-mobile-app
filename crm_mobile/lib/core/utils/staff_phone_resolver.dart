import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/injection/injection.dart';

class StaffPhoneResolver {
  /// Ensures the logged-in staff member's phone number is retrieved and saved in SharedPreferences.
  /// Checks SharedPreferences first, then queries identity-service APIs if missing.
  static Future<String> getOrFetchStaffPhone({
    ApiClient? apiClient,
    SharedPreferences? prefs,
  }) async {
    try {
      final sharedPrefs = prefs ?? (sl.isRegistered<SharedPreferences>() ? sl<SharedPreferences>() : await SharedPreferences.getInstance());

      // 1. Check if userPhone is already cached in SharedPreferences
      String phone = sharedPrefs.getString('userPhone')?.trim() ?? '';
      if (phone.isNotEmpty) {
        return phone;
      }

      final userId = sharedPrefs.getString('userId')?.trim() ?? '';
      final userEmail = sharedPrefs.getString('userEmail')?.trim() ?? '';
      if (userId.isEmpty && userEmail.isEmpty) {
        return '';
      }

      final client = apiClient ?? (sl.isRegistered<ApiClient>() ? sl<ApiClient>() : null);
      if (client == null) return '';
      final identityBaseUrl = ApiUrl.identityService;

      // 2. Try GET /identity/users/$userId
      if (userId.isNotEmpty) {
        try {
          final response = await client.get('$identityBaseUrl/users/$userId');
          final body = response.data;
          final phoneFound = _extractPhoneFromJson(body);
          if (phoneFound.isNotEmpty) {
            await sharedPrefs.setString('userPhone', phoneFound);
            debugPrint('StaffPhoneResolver: Found phone via /users/$userId -> $phoneFound');
            return phoneFound;
          }
        } catch (e) {
          debugPrint('StaffPhoneResolver: Failed /users/$userId: $e');
        }
      }

      // 3. Try GET /identity/users/staff (search staff list for matching userId or email)
      try {
        final response = await client.get('$identityBaseUrl/users/staff', queryParameters: {'size': 1000});
        final body = response.data;
        if (body != null && body['data'] != null) {
          final List<dynamic> content;
          if (body['data'] is List) {
            content = body['data'];
          } else if (body['data'] is Map && body['data']['content'] is List) {
            content = body['data']['content'];
          } else {
            content = [];
          }

          for (final item in content) {
            if (item is Map<String, dynamic>) {
              final itemId = (item['id'] ?? item['userId'] ?? item['userCode'] ?? '').toString();
              final itemEmail = (item['email'] ?? item['username'] ?? item['emailAddress'] ?? '').toString();
              if ((userId.isNotEmpty && itemId == userId) ||
                  (userEmail.isNotEmpty && itemEmail.toLowerCase() == userEmail.toLowerCase())) {
                final phoneFound = _extractPhoneFromJson(item);
                if (phoneFound.isNotEmpty) {
                  await sharedPrefs.setString('userPhone', phoneFound);
                  debugPrint('StaffPhoneResolver: Found phone via /users/staff -> $phoneFound');
                  return phoneFound;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('StaffPhoneResolver: Failed /users/staff: $e');
      }

      // 4. Try GET /identity/users/me
      try {
        final response = await client.get('$identityBaseUrl/users/me');
        final body = response.data;
        final phoneFound = _extractPhoneFromJson(body);
        if (phoneFound.isNotEmpty) {
          await sharedPrefs.setString('userPhone', phoneFound);
          debugPrint('StaffPhoneResolver: Found phone via /users/me -> $phoneFound');
          return phoneFound;
        }
      } catch (e) {
        debugPrint('StaffPhoneResolver: Failed /users/me: $e');
      }

    } catch (e) {
      debugPrint('StaffPhoneResolver error: $e');
    }

    return '';
  }

  static String _extractPhoneFromJson(dynamic json) {
    if (json == null) return '';
    Map<String, dynamic>? targetMap;
    if (json is Map<String, dynamic>) {
      if (json['data'] is Map<String, dynamic>) {
        targetMap = json['data'] as Map<String, dynamic>;
      } else {
        targetMap = json;
      }
    }
    if (targetMap == null) return '';

    final keys = [
      'phone',
      'phoneNumber',
      'mobile',
      'contactNumber',
      'phoneNo',
      'mobileNumber',
      'contact',
      'userPhone',
      'officialPhone',
      'workPhone'
    ];
    for (final key in keys) {
      final val = targetMap[key]?.toString().trim() ?? '';
      if (val.isNotEmpty && val != 'null') {
        return val;
      }
    }
    return '';
  }
}
