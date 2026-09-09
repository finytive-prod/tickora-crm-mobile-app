import 'package:flutter_test/flutter_test.dart';
import 'package:crm_mobile/core/utils/validators.dart';

void main() {
  group('MobileNumberInputFormatter tests', () {
    final formatter = MobileNumberInputFormatter();

    String format(String text, {String old = ''}) {
      final oldValue = TextEditingValue(text: old);
      final newValue = TextEditingValue(text: text);
      return formatter.formatEditUpdate(oldValue, newValue).text;
    }

    test('Pasting +91 9090909090 yields 9090909090', () {
      expect(format('+91 9090909090'), equals('9090909090'));
    });

    test('Pasting +919090909090 yields 9090909090', () {
      expect(format('+919090909090'), equals('9090909090'));
    });

    test('Pasting 919090909090 yields 9090909090', () {
      expect(format('919090909090'), equals('9090909090'));
    });

    test('Pasting 09090909090 yields 9090909090', () {
      expect(format('09090909090'), equals('9090909090'));
    });

    test('Pasting +91 09090909090 yields 9090909090', () {
      expect(format('+91 09090909090'), equals('9090909090'));
    });

    test('Typing 9090909090 digit by digit yields 9090909090', () {
      expect(format('9090909090'), equals('9090909090'));
    });

    test('Entering 11th digit when 10 digits exist caps to 10 digits', () {
      expect(format('90909090901', old: '9090909090'), equals('9090909090'));
    });
  });
}
