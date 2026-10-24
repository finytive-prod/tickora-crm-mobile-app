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

  /// Validates standard email addresses and rejects emojis, spaces, and invalid domains
  static String? validateEmail(String? value, {bool isRequired = false}) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? 'Email address is required' : null;
    }

    final email = value.trim();

    if (hasEmoji(email)) {
      return 'Email cannot contain emojis';
    }

    if (email.contains(' ')) {
      return 'Email cannot contain spaces';
    }

    if (email.contains('..')) {
      return 'Please enter a valid email address';
    }

    // Validates standard email addresses (user@domain.tld)
    final emailRegExp = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$',
      caseSensitive: false,
    );

    if (!emailRegExp.hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    final parts = email.split('@');
    if (parts.length != 2) return 'Please enter a valid email address';
    final localPart = parts[0];
    if (localPart.startsWith('.') || localPart.endsWith('.')) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validates 10-digit mobile numbers and rejects emojis
  static String? validateMobile(
    String? value, {
    bool isRequired = false,
    String fieldName = 'Phone number',
  }) {
    if (value == null || value.trim().isEmpty) {
      return isRequired ? '$fieldName is required' : null;
    }

    if (hasEmoji(value)) {
      return '$fieldName cannot contain emojis';
    }
    
    final phone = value.trim();

    if (!RegExp(r'^\d+$').hasMatch(phone)) {
      return '$fieldName must contain only digits';
    }
    
    if (phone.length != 10) {
      return '$fieldName must be exactly 10 digits';
    }
    
    if (!phone.startsWith(RegExp(r'[6-9]'))) {
      return '$fieldName must start with 6, 7, 8, or 9';
    }

    if (RegExp(r'^(\d)\1{9}$').hasMatch(phone)) {
      return 'Please enter a valid $fieldName';
    }
    
    return null;
  }
}

class AppInputFormatters {
  static List<TextInputFormatter> get nameFormatters => [];
  
  static List<TextInputFormatter> get phoneFormatters => [
    MobileNumberInputFormatter(),
  ];

  /// Denies all emoji inputs
  static TextInputFormatter get denyEmoji =>
    FilteringTextInputFormatter.deny(AppValidators.emojiRegExp);

  static List<TextInputFormatter> get noEmojiFormatters => [
    FilteringTextInputFormatter.deny(AppValidators.emojiRegExp),
  ];
}

class MobileNumberInputFormatter extends TextInputFormatter {
  final int maxLength;

  MobileNumberInputFormatter({this.maxLength = 10});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String input = newValue.text;
    if (input.isEmpty) return newValue;

    // Remove all non-digit characters
    String digits = input.replaceAll(RegExp(r'[^\d]'), '');

    // Handle country code stripping for pasted or typed numbers >= 11 digits
    if (digits.length > maxLength) {
      if (digits.startsWith('91') && digits.length >= 11) {
        digits = digits.substring(2);
      }
      if (digits.startsWith('0') && digits.length > maxLength) {
        digits = digits.substring(1);
      }
    }

    // Compute cursor offset relative to digits before cursor
    int rawOffset = newValue.selection.baseOffset;
    if (rawOffset < 0) rawOffset = 0;
    if (rawOffset > newValue.text.length) rawOffset = newValue.text.length;

    final textBeforeCursor = newValue.text.substring(0, rawOffset);
    int digitsBeforeCursor = textBeforeCursor.replaceAll(RegExp(r'[^\d]'), '').length;

    if (digits.length > maxLength) {
      String oldDigits = oldValue.text.replaceAll(RegExp(r'[^\d]'), '');

      // If a single character was inserted into an already full field (e.g. editing first digit or middle digit)
      if (oldDigits.length == maxLength && digits.length == maxLength + 1 && digitsBeforeCursor <= maxLength) {
        // Replace the digit right after the insertion cursor, rather than truncating the last digit
        int removeIndex = digitsBeforeCursor;
        if (removeIndex < digits.length) {
          digits = digits.substring(0, removeIndex) + digits.substring(removeIndex + 1);
        } else {
          digits = digits.substring(0, maxLength);
        }
      } else {
        // Multi-character paste or overflow at end: cap to maxLength
        digits = digits.substring(0, maxLength);
      }
    }

    if (digitsBeforeCursor > digits.length) {
      digitsBeforeCursor = digits.length;
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digitsBeforeCursor),
    );
  }
}
