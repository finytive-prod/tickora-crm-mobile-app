import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:dio/dio.dart';

class DummyApiClient implements ApiClient {
  final dynamic mockData;
  DummyApiClient({this.mockData});

  @override
  Future<Response> get(String url, {Map<String, dynamic>? queryParameters, Options? options, CancelToken? cancelToken, ProgressCallback? onReceiveProgress}) async {
    return Response(
      requestOptions: RequestOptions(path: url),
      data: mockData ?? {'success': true, 'data': {'privileges': ['STAFF_READ', 'DASHBOARD_READ']}},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('PrivilegeService matches STAFF_READ correctly', () async {
    final service = PrivilegeService(
      apiClient: DummyApiClient(),
      logger: Logger(),
    );

    await service.fetchPrivileges();
    expect(service.hasPrivilege('STAFF_READ'), isTrue);
  });

  test('PrivilegeService correctly parses backend module matrix and restricts unassigned permissions', () {
    final matrixData = [
      {'module': 'Lead Custom Fields', 'read': false, 'create': false, 'update': false, 'delete': false},
      {'module': 'Customers', 'read': true, 'create': true, 'update': true, 'delete': false},
      {'module': 'Leads', 'read': true, 'create': true, 'update': true, 'delete': false},
      {'module': 'Lead Assignments', 'read': false, 'create': false, 'update': false, 'delete': false},
      {'module': 'Reports', 'read': true, 'create': false, 'update': false, 'delete': false},
      {'module': 'Calendars', 'read': true, 'create': true, 'update': true, 'delete': false},
      {'module': 'Permissions', 'read': false, 'create': false, 'update': false, 'delete': false},
      {'module': 'Staffs', 'read': true, 'create': false, 'update': false, 'delete': true},
      {'module': 'Lead Sources', 'read': false, 'create': false, 'update': false, 'delete': false},
      {'module': 'Dashboards', 'read': true, 'create': true, 'update': true, 'delete': false},
    ];

    final parsed = PrivilegeService.parsePrivilegeList(matrixData);
    final service = PrivilegeService(
      apiClient: DummyApiClient(),
      logger: Logger(),
    );
    service.setPrivileges(parsed, replace: true);

    // Granted permissions
    expect(service.hasPrivilege('LEAD_READ'), isTrue);
    expect(service.hasPrivilege('CUSTOMER_READ'), isTrue);
    expect(service.hasPrivilege('REPORT_READ'), isTrue);
    expect(service.hasPrivilege('CALENDAR_READ'), isTrue);
    expect(service.hasPrivilege('STAFF_READ'), isTrue);
    expect(service.hasPrivilege('STAFF_DELETE'), isTrue);

    // Denied permissions (must NOT leak from LEAD_READ)
    expect(service.hasPrivilege('STAFF_UPDATE'), isFalse);
    expect(service.hasPrivilege('STAFF_CREATE'), isFalse);
    expect(service.hasPrivilege('LEAD_SOURCES_READ'), isFalse);
    expect(service.hasPrivilege('LEAD_SOURCE_READ'), isFalse);
    expect(service.hasPrivilege('LEAD_STATUS_READ'), isFalse);
    expect(service.hasPrivilege('LEAD_CUSTOM_FIELDS_READ'), isFalse);
    expect(service.hasPrivilege('PERMISSIONS_READ'), isFalse);
    expect(service.hasPrivilege('ROLES_READ'), isFalse);
    expect(service.canAssignLeads(), isFalse);
  });
}
