import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:crm_mobile/core/network/interceptors/auth_interceptor.dart';

void main() {
  group('AuthInterceptor tenant ID & token tests', () {
    test('isValidTenantId correctly identifies valid and invalid IDs', () {
      expect(AuthInterceptor.isValidTenantId(null), isFalse);
      expect(AuthInterceptor.isValidTenantId(''), isFalse);
      expect(AuthInterceptor.isValidTenantId('   '), isFalse);
      expect(AuthInterceptor.isValidTenantId('null'), isFalse);
      expect(AuthInterceptor.isValidTenantId('NULL'), isFalse);
      expect(AuthInterceptor.isValidTenantId('undefined'), isFalse);
      expect(AuthInterceptor.isValidTenantId('none'), isFalse);
      expect(AuthInterceptor.isValidTenantId('{}'), isFalse);

      expect(
        AuthInterceptor.isValidTenantId('b5e1bbd8-df2a-4d88-8e85-bed58db4eec5'),
        isTrue,
      );
      expect(AuthInterceptor.isValidTenantId('org-12345'), isTrue);
    });

    test('extractTenantIdFromToken extracts organizationId from JWT claims', () {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'user-1',
        'organizationId': 'b5e1bbd8-df2a-4d88-8e85-bed58db4eec5',
      })));
      final token = '$header.$payload.fake_sig';

      final tenantId = AuthInterceptor.extractTenantIdFromToken(token);
      expect(tenantId, 'b5e1bbd8-df2a-4d88-8e85-bed58db4eec5');
    });

    test('extractTenantIdFromToken extracts tenantId when organizationId is missing', () {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'user-2',
        'tenantId': 'tenant-uuid-999',
      })));
      final token = '$header.$payload.fake_sig';

      final tenantId = AuthInterceptor.extractTenantIdFromToken(token);
      expect(tenantId, 'tenant-uuid-999');
    });

    test('extractTenantIdFromToken handles null and invalid tenant values safely', () {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'user-3',
        'organizationId': 'null',
        'tenantId': null,
      })));
      final token = '$header.$payload.fake_sig';

      final tenantId = AuthInterceptor.extractTenantIdFromToken(token);
      expect(tenantId, isNull);
    });

    test('extractTenantIdFromToken handles nested user_metadata claims', () {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'sub': 'user-4',
        'user_metadata': {
          'organizationId': 'org-from-metadata-777',
        },
      })));
      final token = '$header.$payload.fake_sig';

      final tenantId = AuthInterceptor.extractTenantIdFromToken(token);
      expect(tenantId, 'org-from-metadata-777');
    });
  });
}
