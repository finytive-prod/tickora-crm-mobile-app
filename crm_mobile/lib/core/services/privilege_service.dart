import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:crm_mobile/core/network/api_client.dart';

class PrivilegeService {
  final ApiClient apiClient;
  final Logger logger;
  
  List<String> _privileges = [];

  PrivilegeService({required this.apiClient, required this.logger});

  List<String> get privileges => List.unmodifiable(_privileges);

  bool hasPrivilege(String feature) {
    logger.d('Checking privilege: $feature. Total privileges: ${_privileges.length}');
    return _privileges.contains(feature);
  }

  Future<void> fetchPrivileges() async {
    try {
      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      String privilegesUrl = baseUrl;
      if (baseUrl.contains('/api/crm/lead-service')) {
        privilegesUrl = baseUrl.replaceAll('/api/crm/lead-service', '/api/crm/identity-service/auth/privileges');
      } else {
        final uri = Uri.parse(baseUrl);
        privilegesUrl = '${uri.scheme}://${uri.host}:${uri.port}/api/crm/identity-service/auth/privileges';
      }

      final response = await apiClient.get(privilegesUrl);
      
      final body = response.data;
      if (body != null && body['success'] == true) {
        final data = body['data'];
        if (data != null && data['privileges'] != null) {
          final privilegesList = data['privileges'] as List<dynamic>;
          _privileges = privilegesList.map((e) => e.toString()).toList();
          logger.i('Fetched ${_privileges.length} privileges');
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
  }
}
