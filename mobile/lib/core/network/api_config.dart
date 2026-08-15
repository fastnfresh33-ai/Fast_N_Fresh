/// Central place to configure the backend API URL.
///
/// IMPORTANT: never hardcode `localhost` and ship it in a release APK —
/// `localhost` on an Android device refers to the device itself, not your
/// development PC.
///
/// - Android Emulator connecting to a backend running on your dev machine:
///     http://10.0.2.2:5000/api
/// - Physical device on the same Wi-Fi as your dev machine:
///     http://10.169.90.212:5000/api
/// - Production:
///     https://your-deployed-api-domain.com/api
///
/// This value can be overridden at build time without editing code:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
///   flutter build apk --release --dart-define=API_BASE_URL=https://api.fastnfreshcafe.com/api

class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.169.90.212:5000/api',
  );

  static const Duration connectTimeout = Duration(seconds: 15);

  static const Duration receiveTimeout = Duration(seconds: 20);

  /// The API root without the trailing /api.
  ///
  /// Used to resolve relative asset URLs such as:
  /// /uploads/products/example.jpg
  ///
  /// This keeps asset URLs consistent with the configured backend.
  static String get assetHost {
    if (baseUrl.endsWith('/api')) {
      return baseUrl.substring(0, baseUrl.length - 4);
    }

    return baseUrl;
  }

  /// Resolves a relative path like:
  /// /uploads/products/xyz.jpg
  ///
  /// into a full URL using the configured backend.
  ///
  /// Already-absolute URLs are returned unchanged.
  static String resolveAssetUrl(String relativeOrAbsolute) {
    if (relativeOrAbsolute.isEmpty) {
      return relativeOrAbsolute;
    }

    if (relativeOrAbsolute.startsWith('http://') ||
        relativeOrAbsolute.startsWith('https://')) {
      return relativeOrAbsolute;
    }

    return '$assetHost$relativeOrAbsolute';
  }
}