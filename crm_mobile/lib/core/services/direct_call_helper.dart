import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

class DirectCallHelper {
  static const MethodChannel _channel = MethodChannel('com.example.crm_mobile/call_recording');

  static Future<bool> makeCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.trim();
    if (cleanPhone.isEmpty) return false;

    try {
      if (Platform.isAndroid) {
        final bool? success = await _channel.invokeMethod<bool>('makeDirectCall', {
          'phoneNumber': cleanPhone,
        });
        if (success == true) {
          return true;
        }
      }
      return (await FlutterPhoneDirectCaller.callNumber(cleanPhone)) ?? false;
    } catch (e) {
      debugPrint('Error placing direct call via method channel: $e');
      try {
        return (await FlutterPhoneDirectCaller.callNumber(cleanPhone)) ?? false;
      } catch (ex) {
        debugPrint('Error with FlutterPhoneDirectCaller fallback: $ex');
        return false;
      }
    }
  }
}
