import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:dio/dio.dart';

class DummyApiClient implements ApiClient {
  @override
  Future<Response> get(String url, {Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onReceiveProgress}) async {
    return Response(requestOptions: RequestOptions(path: url), data: {'success': true, 'data': {'privileges': ['STAFF_READ', 'DASHBOARD_READ']}});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('PrivilegeService returns true when privileges list is empty to prevent UI items disappearing', () {
    final service = PrivilegeService(
      apiClient: DummyApiClient(),
      logger: Logger(),
    );

    expect(service.hasPrivilege('DASHBOARD_READ'), isTrue);
    expect(service.hasPrivilege('LEAD_READ'), isTrue);
    expect(service.hasPrivilege('SETTINGS_READ'), isTrue);
  });

  test('PrivilegeService matches STAFF_READ correctly', () async {
    final service = PrivilegeService(
      apiClient: DummyApiClient(),
      logger: Logger(),
    );

    await service.fetchPrivileges();
    expect(service.hasPrivilege('STAFF_READ'), isTrue);
  });
}
