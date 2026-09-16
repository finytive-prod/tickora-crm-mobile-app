import 'package:flutter_test/flutter_test.dart';
import 'package:crm_mobile/core/services/app_update_service.dart';

void main() {
  group('AppVersion Semantic Comparison Tests', () {
    test('Installed 1.0.0 < Minimum 1.2.0 -> Update Required', () {
      final vInstalled = AppVersion.parse('1.0.0');
      final vMin = AppVersion.parse('1.2.0');
      expect(vInstalled < vMin, isTrue);
    });

    test('Installed 1.2.0 == Minimum 1.2.0 -> Continue (No Update Required)', () {
      final vInstalled = AppVersion.parse('1.2.0');
      final vMin = AppVersion.parse('1.2.0');
      expect(vInstalled < vMin, isFalse);
      expect(vInstalled == vMin, isTrue);
    });

    test('Installed 1.5.0 > Minimum 1.2.0 -> Continue (No Update Required)', () {
      final vInstalled = AppVersion.parse('1.5.0');
      final vMin = AppVersion.parse('1.2.0');
      expect(vInstalled < vMin, isFalse);
      expect(vInstalled > vMin, isTrue);
    });

    test('Installed 1.9.0 < Minimum 1.10.0 -> Update Required (Semantic Versioning)', () {
      final vInstalled = AppVersion.parse('1.9.0');
      final vMin = AppVersion.parse('1.10.0');
      expect(vInstalled < vMin, isTrue);
    });

    test('Installed 1.10.0 > Minimum 1.9.0 -> Continue', () {
      final vInstalled = AppVersion.parse('1.10.0');
      final vMin = AppVersion.parse('1.9.0');
      expect(vInstalled < vMin, isFalse);
      expect(vInstalled > vMin, isTrue);
    });

    test('Installed 1.2.0+7 < Minimum 1.2.0+8 -> Update Required (Build Number Comparison)', () {
      final vInstalled = AppVersion.parse('1.2.0+7');
      final vMin = AppVersion.parse('1.2.0+8');
      expect(vInstalled < vMin, isTrue);
    });

    test('Installed 1.2.0+8 >= Minimum 1.2.0+7 -> Continue (No Update Required)', () {
      final vInstalled = AppVersion.parse('1.2.0+8');
      final vMin = AppVersion.parse('1.2.0+7');
      expect(vInstalled < vMin, isFalse);
      expect(vInstalled >= vMin, isTrue);
    });

    test('Installed 1.2.0+7 == Minimum 1.2.0+7 -> Continue', () {
      final vInstalled = AppVersion.parse('1.2.0+7');
      final vMin = AppVersion.parse('1.2.0+7');
      expect(vInstalled == vMin, isTrue);
    });

    test('Handles version string with single/double components (e.g. 1.2 vs 1.2.0)', () {
      final vInstalled = AppVersion.parse('1.2');
      final vMin = AppVersion.parse('1.2.0');
      expect(vInstalled == vMin, isTrue);
    });
  });
}
