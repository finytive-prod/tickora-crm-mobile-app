import 'package:flutter/services.dart';

class AppValidators {
  /// Regular expression matching standard Unicode emojis and symbols
  static final RegExp emojiRegExp = RegExp(
    r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]|[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F700}-\u{1F7FF}\u{1F800}-\u{1F8FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{1F004}\u{1F0CF}\u{1F170}-\u{1F19A}])',
    unicode: true,
  );

  /// Checks if the input string contains any emoji character
  static bool hasEmoji(String? value) {
    if (value == null || value.isEmpty) return false;
    return emojiRegExp.hasMatch(value);
  }

  /// Validates that input contains no emojis
  static String? validateNoEmoji(String? value, {String fieldName = 'This field'}) {
    if (hasEmoji(value)) {
      return '$fieldName cannot contain emojis';
    }
    return null;
  }

  /// Validates text fields (checks required and emoji presence)
  static String? validateText(String? value, {String fieldName = 'This field', bool isRequired = false}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? '$fieldName is required' : null;
    }
    if (hasEmoji(value)) {
      return '$fieldName cannot contain emojis';
    }
    return null;
  }

  /// Validates standard email addresses and rejects emojis
  static String? validateEmail(String? value, {bool isRequired = false}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? 'Email is required' : null;
    }

    if (hasEmoji(value)) {
      return 'Email cannot contain emojis';
    }
    
    // Validates standard email addresses
    final emailRegExp = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      caseSensitive: false,
    );

    if (!emailRegExp.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Validates 10-digit mobile numbers and rejects emojis
  static String? validateMobile(String? value, {bool isRequired = false}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? 'Mobile number is required' : null;
    }

    if (hasEmoji(value)) {
      return 'Mobile number cannot contain emojis';
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

  /// Denies all emoji inputs
  static TextInputFormatter get denyEmoji =>
    FilteringTextInputFormatter.deny(AppValidators.emojiRegExp);

  static List<TextInputFormatter> get noEmojiFormatters => [
    FilteringTextInputFormatter.deny(AppValidators.emojiRegExp),
  ];
}
