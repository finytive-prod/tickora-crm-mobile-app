import 'package:flutter/services.dart';

class AppValidators {
  static String? validateEmail(String? value, {bool isRequired = false}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? 'Email is required' : null;
    }
    
    // Validates standard email addresses ending with specific domains
    final emailRegExp = RegExp(
      r'^[a-zA-Z0-9._%+-]+@(gmail\.com|yahoo\.com|outlook\.com|hotmail\.com)$',
      caseSensitive: false,
    );

    if (!emailRegExp.hasMatch(value.trim())) {
      return 'Email must end with @gmail.com, @yahoo.com, etc.';
    }
    return null;
  }

  static String? validateMobile(String? value, {bool isRequired = false}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? 'Mobile number is required' : null;
    }
    
    final phone = value.trim();
    
    if (phone.length != 10) {
      return 'Mobile number must be exactly 10 digits';
    }
    
    if (!phone.startsWith(RegExp(r'[6-9]'))) {
      return 'Mobile number must start with 6, 7, 8, or 9';
    }
    
    return null;
  }
}

class AppInputFormatters {
  static List<TextInputFormatter> get nameFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
  ];
  
  static List<TextInputFormatter> get phoneFormatters => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];
}
