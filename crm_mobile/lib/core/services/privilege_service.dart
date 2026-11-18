import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';
import 'package:crm_mobile/injection/injection.dart';

class PrivilegeService extends ChangeNotifier {
  final ApiClient apiClient;
  final Logger logger;

  List<String> _privileges = [];
  bool _hasLoadedFromCache = false;
  Future<void>? _inFlightFetch;
  DateTime? _lastFetchTime;

  PrivilegeService({required this.apiClient, required this.logger}) {
    _loadFromCacheSync();
  }

  void _loadFromCacheSync() {
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        final prefs = sl<SharedPreferences>();
        final cached = prefs.getStringList('cached_privileges');
        if (cached != null && cached.isNotEmpty) {
          _privileges = cached
              .map((e) => e.trim().toUpperCase())
              .where((e) => e.isNotEmpty && e != 'LEAD_ASSIGN' && e != 'LEADS_ASSIGN')
              .toList();
          _hasLoadedFromCache = true;
          logger.i('Loaded ${_privileges.length} privileges from cache');
        }
      }
    } catch (e) {
      logger.e('Error loading cached privileges: $e');
    }
  }

  List<String> get privileges => List.unmodifiable(_privileges);

  String _getUserRole() {
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        return sl<SharedPreferences>().getString('userRole')?.trim() ?? '';
      }
    } catch (_) {}
    return '';
  }

  bool isAdminOrSuperAdmin() {
    final role = _getUserRole().toUpperCase();
    if (role.contains('SUPERADMIN') ||
        role.contains('ADMIN') ||
        role.contains('SUPER_ADMIN') ||
        role.contains('8780EDFE-2C9D-4F23-AD3D-CA2A605E5BF9')) {
      return true;
    }
    if (_privileges.any((p) {
      final up = p.toUpperCase();
      return up == 'ROLE_SUPERADMIN' ||
          up == 'ROLE_ADMIN' ||
          up == 'SUPERADMIN' ||
          up == 'ADMIN' ||
          up == 'ALL' ||
          up == '*';
    })) {
      return true;
    }
    return false;
  }

  void setPrivileges(List<String> privs, {bool replace = false}) {
    final clean = privs
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty && e != 'LEAD_ASSIGN' && e != 'LEADS_ASSIGN')
        .toList();
    if (replace) {
      _privileges = clean.toSet().toList();
    } else {
      if (clean.isEmpty) return;
      final Set<String> combined = Set.from(_privileges)..addAll(clean);
      _privileges = combined.toList();
    }
    _saveToCache();
    notifyListeners();
  }

  void _saveToCache() {
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        final prefs = sl<SharedPreferences>();
        prefs.setStringList('cached_privileges', _privileges);
      }
    } catch (e) {
      logger.e('Error saving privileges to cache: $e');
    }
  }

  static List<String> parsePrivilegeList(dynamic data) {
    final List<String> result = [];
    if (data == null) return result;

    void addPrivilege(String p) {
      final clean = p.trim().toUpperCase();
      if (clean.isNotEmpty && !result.contains(clean)) {
        result.add(clean);
      }
    }

    void processItem(dynamic item) {
      if (item == null) return;
      if (item is String) {
        if (item.contains(',') || item.contains(' ')) {
          final parts = item.split(RegExp(r'[, ]+'));
          for (final part in parts) {
            addPrivilege(part);
          }
        } else {
          addPrivilege(item);
        }
      } else if (item is Map) {
        final rawModule = (item['module'] ?? item['moduleName'] ?? item['name'] ?? item['code'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (rawModule.isNotEmpty) {
          final module = rawModule.replaceAll(RegExp(r'\s+'), '_');
          final String pluralModule = module.endsWith('STATUS')
              ? '${module}ES'
              : (module.endsWith('S') ? module : '${module}S');
          final String singularModule = module.endsWith('STATUSES')
              ? module.substring(0, module.length - 2)
              : (module.endsWith('S') ? module.substring(0, module.length - 1) : module);

          final Set<String> aliases = {module, pluralModule, singularModule};
          if (module.contains('PERMISSION') || module.contains('ROLE')) {
            aliases.addAll(['PERMISSIONS', 'PERMISSION', 'ROLES', 'ROLE']);
          }
          if (module.contains('ASSIGN')) {
            aliases.addAll(['LEAD_ASSIGNMENTS', 'LEAD_ASSIGNMENT', 'ASSIGNED_LEADS', 'ASSIGNED_LEAD']);
          }
          if (module.contains('SOURCE')) {
            aliases.addAll(['LEAD_SOURCES', 'LEAD_SOURCE']);
          }
          if (module.contains('CUSTOM_FIELD') || module.contains('CUSTOM_FORM')) {
            aliases.addAll(['LEAD_CUSTOM_FIELDS', 'LEAD_CUSTOM_FIELD', 'LEAD_CUSTOM_FORMS', 'LEAD_CUSTOM_FORM', 'CUSTOM_FIELDS', 'CUSTOM_FIELD']);
          }
          if (module.contains('STATUS')) {
            aliases.addAll(['LEAD_STATUS', 'LEAD_STATUSES']);
          }

          final bool hasRead = item['read'] == true;
          final bool hasCreate = item['create'] == true;
          final bool hasUpdate = item['update'] == true;
          final bool hasDelete = item['delete'] == true;
          final bool hasExplicitCrud = item.containsKey('read') || item.containsKey('create') || item.containsKey('update') || item.containsKey('delete');

          if (hasRead) {
            for (final a in aliases) {
              addPrivilege('${a}_READ');
            }
          }
          if (hasCreate) {
            for (final a in aliases) {
              addPrivilege('${a}_CREATE');
            }
          }
          if (hasUpdate) {
            for (final a in aliases) {
              addPrivilege('${a}_UPDATE');
            }
          }
          if (hasDelete) {
            for (final a in aliases) {
              addPrivilege('${a}_DELETE');
            }
          }

          if (!hasExplicitCrud) {
            for (final a in aliases) {
              addPrivilege(a);
            }
          }
        }
        if (item['privilegeName'] != null) addPrivilege(item['privilegeName'].toString());
        if (item['authority'] != null) addPrivilege(item['authority'].toString());
        if (item['role'] != null) addPrivilege(item['role'].toString());
        if (item['roleCode'] != null) addPrivilege(item['roleCode'].toString());
        if (item['privileges'] is List) {
          for (final sub in item['privileges'] as List) {
            processItem(sub);
          }
        }
        if (item['permissions'] is List) {
          for (final sub in item['permissions'] as List) {
            processItem(sub);
          }
        }
        if (item['rolePermissions'] is List) {
          for (final sub in item['rolePermissions'] as List) {
            processItem(sub);
          }
        }
      } else if (item is List) {
        for (final sub in item) {
          processItem(sub);
        }
      }
    }

    if (data is Map) {
      if (data['data'] != null) {
        processItem(data['data']);
      }
      if (data['privileges'] != null) {
        processItem(data['privileges']);
      }
      if (data['permissions'] != null) {
        processItem(data['permissions']);
      }
      if (data['rolePermissions'] != null) {
        processItem(data['rolePermissions']);
      }
      if (data['content'] != null) {
        processItem(data['content']);
      }
    } else if (data is List) {
      for (final item in data) {
        processItem(item);
      }
    } else {
      processItem(data);
    }

    return result;
  }

  bool hasPrivilege(String feature) {
    if (isAdminOrSuperAdmin()) return true;

    if (_privileges.any((p) {
      final up = p.toUpperCase();
      return up == '*' || up == 'ALL' || up.contains('SUPERADMIN') || up.contains('ADMIN');
    })) {
      return true;
    }

    if (_privileges.isEmpty) {
      return false;
    }

    final target = feature.trim().toUpperCase().replaceAll(' ', '_');
    if (_privileges.contains(target)) return true;

    final lastUnderscore = target.lastIndexOf('_');
    if (lastUnderscore != -1) {
      final module = target.substring(0, lastUnderscore);
      final action = target.substring(lastUnderscore + 1);
      final String pluralModule = module.endsWith('STATUS')
          ? '${module}ES'
          : (module.endsWith('S') ? module : '${module}S');
      final String singularModule = module.endsWith('STATUSES')
          ? module.substring(0, module.length - 2)
          : (module.endsWith('S') ? module.substring(0, module.length - 1) : module);

      final variations = [
        '${module}_$action',
        '${pluralModule}_$action',
        '${singularModule}_$action',
        '${action}_$module',
        '${action}_$pluralModule',
        '${action}_$singularModule',
        '$module:$action',
        '$pluralModule:$action',
        '$singularModule:$action',
      ];

      for (final v in variations) {
        if (_privileges.contains(v)) return true;
      }
    }

    if (target.contains('BLOCKLIST')) {
      if (_privileges.any((p) => p.contains('BLOCK'))) return true;
    }
    if (target.contains('CALL')) {
      if (_privileges.any((p) => p.contains('CALL'))) return true;
      if (_privileges.contains('DASHBOARD_READ') ||
          _privileges.contains('LEAD_READ') ||
          _privileges.contains('LEADS_READ')) {
        return true;
      }
    }

    return false;
  }

  bool canAssignLeads() {
    // Admin and Superadmin roles can always assign leads
    if (isAdminOrSuperAdmin()) return true;

    // For other roles, assign permission is strictly based on the Assigned Leads privilege
    return hasPrivilege('LEAD_ASSIGNMENTS_READ') ||
        hasPrivilege('LEAD_ASSIGNMENTS_UPDATE') ||
        hasPrivilege('LEAD_ASSIGNMENTS_CREATE') ||
        hasPrivilege('ASSIGNED_LEADS_READ') ||
        hasPrivilege('ASSIGNED_LEADS_UPDATE') ||
        hasPrivilege('ASSIGNED_LEADS_CREATE') ||
        hasPrivilege('LEAD_ASSIGN') ||
        hasPrivilege('ASSIGN_LEAD') ||
        hasPrivilege('ASSIGN_TO');
  }

  Future<void> fetchPrivileges({bool force = false}) {
    if (_inFlightFetch != null) {
      return _inFlightFetch!;
    }
    if (!force &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inSeconds < 30 &&
        _privileges.isNotEmpty) {
      return Future.value();
    }

    _inFlightFetch = _fetchPrivilegesInternal().whenComplete(() {
      _inFlightFetch = null;
    });
    return _inFlightFetch!;
  }

  Future<void> _fetchPrivilegesInternal() async {
    if (_privileges.isEmpty && !_hasLoadedFromCache) {
      _loadFromCacheSync();
    }

    try {
      final privilegesUrl = '${ApiUrl.identityService}/auth/privileges';
      final response = await apiClient.get(privilegesUrl);
      final body = response.data;
      if (body != null) {
        final parsed = parsePrivilegeList(body);
        setPrivileges(parsed, replace: true);
        _lastFetchTime = DateTime.now();
        logger.i('Fetched ${parsed.length} privileges from /auth/privileges');
        return;
      }
    } catch (e) {
      logger.d('Fetch privileges primary endpoint: $e');
    }

    try {
      final permissionsUrl = '${ApiUrl.identityService}/auth/permissions';
      final response = await apiClient.get(permissionsUrl);
      final body = response.data;
      if (body != null) {
        final parsed = parsePrivilegeList(body);
        setPrivileges(parsed, replace: true);
        _lastFetchTime = DateTime.now();
        logger.i('Fetched ${parsed.length} privileges from /auth/permissions');
        return;
      }
    } catch (_) {}

    try {
      final profileUrl = '${ApiUrl.identityService}/auth/profile';
      final response = await apiClient.get(profileUrl);
      final body = response.data;
      if (body != null && body['data'] != null) {
        final parsed = parsePrivilegeList(body['data']);
        setPrivileges(parsed, replace: true);
        _lastFetchTime = DateTime.now();
        logger.i('Fetched ${parsed.length} privileges from /auth/profile');
        return;
      }
    } catch (_) {}
  }

  void clearPrivileges() {
    _privileges = [];
    _hasLoadedFromCache = false;
    _lastFetchTime = null;
    try {
      if (sl.isRegistered<SharedPreferences>()) {
        final prefs = sl<SharedPreferences>();
        prefs.remove('cached_privileges');
        prefs.remove('userRole');
      }
    } catch (_) {}
    notifyListeners();
  }
}
