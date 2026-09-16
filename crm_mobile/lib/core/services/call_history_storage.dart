import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crm_mobile/models/call_history.dart';

/// Storage service to persist app call history logs locally
class CallHistoryStorage {
  static const String _storageKey = 'tracked_call_history_v1';

  static Future<List<CallHistory>> loadCallHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) return [];

      final List<dynamic> list = jsonDecode(jsonString);
      return list
          .map((e) => CallHistory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('Error loading call history: $e');
      return [];
    }
  }

  static Future<void> saveCallHistory(List<CallHistory> historyList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(historyList.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error saving call history: $e');
    }
  }

  static Future<void> addOrUpdateCall(CallHistory entry) async {
    try {
      final list = await loadCallHistory();
      final index = list.indexWhere((e) => e.id == entry.id);
      if (index >= 0) {
        list[index] = entry;
      } else {
        list.insert(0, entry);
      }
      await saveCallHistory(list);
    } catch (e) {
      debugPrint('Error adding call history entry: $e');
    }
  }
}
