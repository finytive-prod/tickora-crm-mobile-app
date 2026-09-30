import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
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

/// Result model for comprehensive app update status check.
class AppUpdateCheckResult {
  final bool isUpdateRequired;
  final String currentVersion;
  final String requiredVersion;

  AppUpdateCheckResult({
    required this.isUpdateRequired,
    required this.currentVersion,
    required this.requiredVersion,
  });
}

/// Service responsible for checking app version updates and directing users to store.
class AppUpdateService {
  /// Checks if Google Play Store has an update available for the app.
  Future<bool> isPlayStoreUpdateAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      return updateInfo.updateAvailability == UpdateAvailability.updateAvailable;
    } catch (e, stack) {
      if (kDebugMode) {
        developer.log('Play Store update availability check error: $e',
            error: e, stackTrace: stack);
      }
    }
    return false;
  }

  /// Checks Google Play Store for an update on Android devices.
  /// Triggers Google Play's native immediate force update flow if available.
  /// Returns [true] if a Play Store update flow was initiated/handled.
  Future<bool> performPlayStoreUpdateCheck() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (updateInfo.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        developer.log('Play Store in-app update check skipped/failed: $e',
            error: e, stackTrace: stack);
      }
    }
    return false;
  }

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

  /// Comprehensive update check comparing installed version against minimum required and Play Store available versions.
  Future<AppUpdateCheckResult> checkAppUpdate(
      {String minVersionStr = AppUpdateConfig.minimumSupportedVersion}) async {
    final installedStr = await getInstalledVersion();
    final installedVersion = AppVersion.parse(installedStr);

    String targetRequiredStr = minVersionStr;
    bool playStoreHasUpdate = false;
    int? playStoreBuildCode;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final updateInfo = await InAppUpdate.checkForUpdate();
        if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
          playStoreHasUpdate = true;
          playStoreBuildCode = updateInfo.availableVersionCode;
          if (playStoreBuildCode != null && playStoreBuildCode > 0) {
            final mainVersion = installedStr.split('+').first;
            targetRequiredStr = '$mainVersion+$playStoreBuildCode';
          }
        }
      } catch (e) {
        if (kDebugMode) {
          developer.log('Play Store in-app update check exception: $e');
        }
      }
    }

    var targetVersion = AppVersion.parse(targetRequiredStr);

    // If Play Store indicates an update is available but targetVersion <= installedVersion,
    // ensure targetRequiredStr reflects the higher deployed build number.
    if (playStoreHasUpdate && targetVersion <= installedVersion) {
      final mainVersion = installedStr.split('+').first;
      final installedBuild =
          installedVersion.parts.length > 3 ? installedVersion.parts[3] : 0;
      final targetBuild = (playStoreBuildCode != null && playStoreBuildCode > installedBuild)
          ? playStoreBuildCode
          : (installedBuild + 1);
      targetRequiredStr = '$mainVersion+$targetBuild';
      targetVersion = AppVersion.parse(targetRequiredStr);
    }

    // Force update ONLY if installed version is strictly below target required version
    final isRequired = installedVersion < targetVersion;

    return AppUpdateCheckResult(
      isUpdateRequired: isRequired,
      currentVersion: installedStr,
      requiredVersion: targetRequiredStr,
    );
  }

  /// Checks if the installed version is lower than the minimum required version.
  Future<bool> isUpdateRequired(
      {String minVersionStr = AppUpdateConfig.minimumSupportedVersion}) async {
    try {
      final result = await checkAppUpdate(minVersionStr: minVersionStr);
      return result.isUpdateRequired;
    } catch (e, stack) {
      if (kDebugMode) {
        developer.log('Error performing version update check: $e',
            error: e, stackTrace: stack);
      }
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
