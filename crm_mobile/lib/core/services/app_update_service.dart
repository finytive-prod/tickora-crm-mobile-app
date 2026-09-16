import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_update_config.dart';

/// Represents a parsed semantic version for robust comparison.
class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;

  AppVersion(this.parts);

  /// Parses a version string such as "1.2.0" or "1.2.0+7" into AppVersion.
  /// Formats semantic parts and build number: [major, minor, patch, buildNumber]
  factory AppVersion.parse(String versionStr) {
    if (versionStr.isEmpty) return AppVersion([0, 0, 0, 0]);

    final String mainPart;
    final int buildNumber;

    if (versionStr.contains('+')) {
      final split = versionStr.split('+');
      mainPart = split.first.trim();
      final buildStr = split.last.replaceAll(RegExp(r'[^0-9]'), '');
      buildNumber = int.tryParse(buildStr) ?? 0;
    } else {
      mainPart = versionStr.trim();
      buildNumber = 0;
    }

    final cleanVersion = mainPart.split('-').first.trim();
    final segments = cleanVersion.split('.');

    final numbers = <int>[];
    for (final seg in segments) {
      final parsed = int.tryParse(seg.replaceAll(RegExp(r'[^0-9]'), ''));
      numbers.add(parsed ?? 0);
    }

    while (numbers.length < 3) {
      numbers.add(0);
    }

    numbers.add(buildNumber);

    return AppVersion(numbers);
  }

  @override
  int compareTo(AppVersion other) {
    final maxLen =
        parts.length > other.parts.length ? parts.length : other.parts.length;

    for (int i = 0; i < maxLen; i++) {
      final partA = i < parts.length ? parts[i] : 0;
      final partB = i < other.parts.length ? other.parts[i] : 0;

      if (partA != partB) {
        return partA.compareTo(partB);
      }
    }
    return 0;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode => parts.hashCode;

  @override
  String toString() => parts.join('.');
}

/// Service responsible for checking app version updates and directing users to store.
class AppUpdateService {
  /// Fetches installed app version string including build number (e.g. "1.2.0+7")
  Future<String> getInstalledVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      final buildNumber = packageInfo.buildNumber;
      if (buildNumber.isNotEmpty) {
        return '$version+$buildNumber';
      }
      return version;
    } catch (e, stack) {
      if (kDebugMode) {
        developer.log('Failed to fetch installed package version: $e',
            error: e, stackTrace: stack);
      }
      return '0.0.0+0';
    }
  }

  /// Checks if the installed version is lower than the minimum required version.
  /// [minVersionStr] allows dynamic minimum version checking (e.g. from Remote Config / API).
  Future<bool> isUpdateRequired(
      {String minVersionStr = AppUpdateConfig.minimumSupportedVersion}) async {
    try {
      final installedStr = await getInstalledVersion();
      final installedVersion = AppVersion.parse(installedStr);
      final minimumVersion = AppVersion.parse(minVersionStr);

      final isRequired = installedVersion < minimumVersion;

      if (kDebugMode) {
        developer.log(
            'AppVersion check -> Installed: $installedStr ($installedVersion), Minimum: $minVersionStr ($minimumVersion), Required: $isRequired');
      }

      return isRequired;
    } catch (e, stack) {
      if (kDebugMode) {
        developer.log('Error performing version update check: $e',
            error: e, stackTrace: stack);
      }
      // Fail safe: if version check fails due to unforeseen error, do not block user
      return false;
    }
  }

  /// Launches the store page (Google Play Store on Android, App Store on iOS).
  /// Attempts native app market URI first, falls back to web HTTPS URL.
  Future<bool> launchAppStore() async {
    final marketUri = Uri.parse(AppUpdateConfig.playStoreMarketUrl);
    final webUri = Uri.parse(AppUpdateConfig.playStoreWebUrl);

    try {
      // Try native market URI
      if (await canLaunchUrl(marketUri)) {
        final launched = await launchUrl(
          marketUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log('Market URI launch failed: $e, trying web fallback...');
      }
    }

    // Fallback to Web URL
    try {
      if (await canLaunchUrl(webUri)) {
        return await launchUrl(
          webUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log('Web URL launch failed: $e');
      }
    }

    return false;
  }
}
