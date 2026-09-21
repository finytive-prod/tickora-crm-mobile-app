import 'package:flutter_test/flutter_test.dart';
import 'package:crm_mobile/core/utils/phone_number_utils.dart';

void main() {
  group('sanitizeLeadSearchQuery', () {
    test('removes +91 country code prefix cleanly', () {
      expect(sanitizeLeadSearchQuery('+919090909090'), '9090909090');
    });

    test('removes +91 with space and hyphens', () {
      expect(sanitizeLeadSearchQuery('+91 9090909090'), '9090909090');
      expect(sanitizeLeadSearchQuery('+91-90909-09090'), '9090909090');
    });

    test('removes 91 prefix when 12 digits', () {
      expect(sanitizeLeadSearchQuery('919090909090'), '9090909090');
    });

    test('removes leading zero when 11 digits', () {
      expect(sanitizeLeadSearchQuery('09090909090'), '9090909090');
    });

    test('keeps 10 digit number intact without stripping digits', () {
      expect(sanitizeLeadSearchQuery('9090909090'), '9090909090');
    });

    test('preserves non-phone text searches', () {
      expect(sanitizeLeadSearchQuery('Rahul Sharma'), 'Rahul Sharma');
      expect(sanitizeLeadSearchQuery('Lead 123'), 'Lead 123');
    });

    test('handles empty input', () {
      expect(sanitizeLeadSearchQuery(''), '');
      expect(sanitizeLeadSearchQuery('   '), '');
    });
  });
}
