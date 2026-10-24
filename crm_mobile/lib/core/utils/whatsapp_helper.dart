import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsAppHelper {
  static const String defaultCountryCode = '91';

  /// Sanitizes any raw phone string into pure digits with country code (e.g. "919003971873")
  static String sanitizePhone(String? rawPhone, {String countryCode = defaultCountryCode}) {
    if (rawPhone == null || rawPhone.trim().isEmpty) return '';

    String digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), ''); // Strip trunk 0

    if (digits.length == 10) {
      digits = countryCode.replaceAll('+', '') + digits;
    }
    return digits;
  }

  /// Replaces {{firstName}}, {{company}}, {{dealValue}}, {{agentName}}
  static String interpolate(String template, Map<String, String> variables) {
    String result = template;
    variables.forEach((key, value) {
      result = result.replaceAll('{{$key}}', value);
    });
    return result;
  }

  /// Opens WhatsApp with the message, copying it to clipboard first as a safety net
  static Future<bool> openWhatsApp(
    BuildContext context, {
    required String phoneNumber,
    String? message,
  }) async {
    final formattedPhone = sanitizePhone(phoneNumber);
    if (formattedPhone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid phone number for WhatsApp.')),
        );
      }
      return false;
    }

    // Safety net: copy to clipboard
    if (message != null && message.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: message.trim()));
    }

    final encodedMsg = (message != null && message.trim().isNotEmpty)
        ? Uri.encodeComponent(message.trim())
        : null;

    final appUri = Uri.parse(
      'whatsapp://send?phone=$formattedPhone${encodedMsg != null ? '&text=$encodedMsg' : ''}',
    );
    final webUri = Uri.parse(
      'https://wa.me/$formattedPhone${encodedMsg != null ? '?text=$encodedMsg' : ''}',
    );

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return true;
      }
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return true;
      }
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return launched;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening WhatsApp: $e')),
        );
      }
      return false;
    }
  }
}
