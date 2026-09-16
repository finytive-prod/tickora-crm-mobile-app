import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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

    test('Entering 11th digit at end when 10 digits exist caps to 10 digits', () {
      final oldValue = TextEditingValue(text: '9090909090', selection: TextSelection.collapsed(offset: 10));
      final newValue = TextEditingValue(text: '90909090901', selection: TextSelection.collapsed(offset: 11));
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, equals('9090909090'));
      expect(result.selection.baseOffset, equals(10));
    });

    test('Editing first digit by inserting at offset 0 when 10 digits exist replaces first digit and preserves last digit', () {
      final oldValue = TextEditingValue(text: '6369644498', selection: TextSelection.collapsed(offset: 0));
      final newValue = TextEditingValue(text: '96369644498', selection: TextSelection.collapsed(offset: 1));
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, equals('9369644498'));
      expect(result.selection.baseOffset, equals(1));
    });

    test('Editing middle digit when 10 digits exist preserves end digits', () {
      final oldValue = TextEditingValue(text: '6369644498', selection: TextSelection.collapsed(offset: 5));
      final newValue = TextEditingValue(text: '63696044498', selection: TextSelection.collapsed(offset: 6));
      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, equals('6369604498'));
      expect(result.selection.baseOffset, equals(6));
    });
  });
}
