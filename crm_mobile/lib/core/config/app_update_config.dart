class AppUpdateConfig {
  /// Minimum supported app version required to continue using the application.
  /// Can be fetched dynamically from backend / Firebase Remote Config in the future.
  static const String minimumSupportedVersion = "1.3.0+30";

  /// Application Package ID for Android (from android/app/build.gradle.kts)
  static const String androidPackageName = "com.tickora.crm";

  /// Play Store Web URL fallback
  static String get playStoreWebUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackageName';

  /// Native Play Store Market URI
  static String get playStoreMarketUrl =>
      'market://details?id=$androidPackageName';

  /// iOS App Store URL (if iOS app ID is available in the future)
  static const String appStoreUrl = '';
}
