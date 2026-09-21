String sanitizeLeadSearchQuery(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';

  final hasPlus = trimmed.startsWith('+');
  final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
  final isNumericLike = RegExp(r'^[\+\d\s\-\(\)]+$').hasMatch(trimmed);

  if (hasPlus || (isNumericLike && digitsOnly.isNotEmpty)) {
    String cleaned = trimmed;
    
    // Strip explicit +91 country code prefix if present
    if (cleaned.startsWith('+91')) {
      cleaned = cleaned.substring(3).trim();
    } else if (cleaned.startsWith('+')) {
      // For general + country code prefix (e.g., +1, +44, +91)
      final d = cleaned.replaceAll(RegExp(r'[^\d]'), '');
      if (d.length > 10) {
        return d.substring(d.length - 10);
      }
    }

    final dOnly = cleaned.replaceAll(RegExp(r'[^\d]'), '');

    // Handle prefixed numbers without + sign (e.g., 919090909090 or 09090909090)
    if (dOnly.length > 10) {
      if (dOnly.length == 12 && dOnly.startsWith('91')) {
        return dOnly.substring(2);
      } else if (dOnly.length == 11 && dOnly.startsWith('0')) {
        return dOnly.substring(1);
      } else {
        return dOnly.substring(dOnly.length - 10);
      }
    }

    if (dOnly.length == 10) {
      return dOnly;
    } else if (hasPlus || (isNumericLike && digitsOnly.length > 10)) {
      return dOnly;
    }
  }

  return trimmed;
}
