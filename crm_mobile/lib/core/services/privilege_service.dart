import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/injection/injection.dart';

class PrivilegeService {
  final ApiClient apiClient;
  final Logger logger;
  
  List<String> _privileges = [];
  bool _hasLoadedFromCache = false;

  PrivilegeService({required this.apiClient, required this.logger}) {
    _loadFromCacheSync();
  }

  void _loadFromCacheSync() {
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        final prefs = sl<SharedPreferences>();
        final cached = prefs.getStringList('cached_privileges');
        if (cached != null && cached.isNotEmpty) {
          _privileges = cached;
          _hasLoadedFromCache = true;
          logger.i('Loaded ${_privileges.length} privileges from cache');
        }
      }
    } catch (e) {
      logger.e('Error loading cached privileges: $e');
    }
  }

  List<String> get privileges => List.unmodifiable(_privileges);

  bool hasPrivilege(String feature) {
    // If privileges list is empty (e.g. offline, initial launch, or API fetch error),
    // allow access by default so UI menu items do not disappear unexpectedly.
    if (_privileges.isEmpty) {
      logger.d('Privilege list empty; allowing $feature by default');
      return true;
    }
    final result = _privileges.contains(feature);
    logger.d('Checking privilege: $feature -> $result. Total privileges: ${_privileges.length}');
    return result;
  }

  Future<void> fetchPrivileges() async {
    if (_privileges.isEmpty && !_hasLoadedFromCache) {
      _loadFromCacheSync();
    }

    try {
      final privilegesUrl = '${ApiUrl.identityService}/auth/privileges';

      final response = await apiClient.get(privilegesUrl);
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        final data = body['data'];
        if (data != null && data['privileges'] != null) {
          final privilegesList = data['privileges'] as List<dynamic>;
          _privileges = privilegesList.map((e) => e.toString()).toList();
          logger.i('Fetched ${_privileges.length} privileges');

          // Save to SharedPreferences for persistent offline/launch availability
          try {
            if (sl.isRegistered<SharedPreferences>()) {
              final prefs = sl<SharedPreferences>();
              await prefs.setStringList('cached_privileges', _privileges);
            }
          } catch (e) {
            logger.e('Error saving privileges to cache: $e');
          }
        }
      } else {
        logger.e('Failed to fetch privileges: ${body?['message']}');
      }
    } catch (e) {
      logger.e('Error fetching privileges: $e');
    }
  }

  void clearPrivileges() {
    _privileges = [];
    _hasLoadedFromCache = false;
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        final prefs = sl<SharedPreferences>();
        prefs.remove('cached_privileges');
      }
    } catch (_) {}
  }
}
