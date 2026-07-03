import 'backend_endpoint.dart';
import 'attribution_keys.dart';
import 'legal_links.dart';

/// Central facade for bundle identity and timing knobs.
class ProjectConstants {
  static const String bundleId = 'com.coopslide.coopslide';
  static const String storeId = 'com.coopslide.coopslide';
  static const String appName = 'CoopSlide';
  static const String siteUrl = 'https://coopslide.com/';

  /// iOS App Store id — unused on Android builds.
  static const String attributionAppId = '';

  static String get configEndpoint => decodeConfigEndpoint();
  static String get attributionDevKey => decodeAttributionKey();
  static String get firebaseProjectNumber => decodeFirebaseProjectNumber();

  static String get privacyUrl => legalPrivacyUrl;
  static String get supportUrl => legalSupportUrl;

  /// Re-show alerts opt-in after Skip (3 days).
  static const int alertsSnoozeSeconds = 259200;

  /// Wait before GCD retry when first callback is Organic.
  static const int gcdRetryDelaySeconds = 5;

  /// FCM / local notification channel id (must match AndroidManifest).
  static const String alertsChannelId = 'coop_slide_alerts';
}
