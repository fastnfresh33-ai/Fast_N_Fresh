/// Central place to configure the backend API URL.
///
/// Production backend:
/// https://fast-n-fresh-backend.onrender.com/api
///
/// The API URL can be overridden at build time using:
///
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
///
/// Production APK:
///
/// flutter build apk --release --dart-define=API_BASE_URL=https://fast-n-fresh-backend.onrender.com/api

class ApiConfig {
  ApiConfig._();

  /// Backend API base URL.
  ///
  /// For production, the default is the Render backend.
  /// You can override it at build time using API_BASE_URL.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://fast-n-fresh-backend.onrender.com/api',
  );

  /// Maximum time allowed to establish a connection.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Maximum time allowed to receive a response.
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// The backend host without the trailing `/api`.
  ///
  /// Example:
  /// baseUrl:
  /// https://fast-n-fresh-backend.onrender.com/api
  ///
  /// assetHost:
  /// https://fast-n-fresh-backend.onrender.com
  ///
  /// This is useful for resolving relative asset URLs such as:
  /// /uploads/products/example.jpg
  static String get assetHost {
    if (baseUrl.endsWith('/api')) {
      return baseUrl.substring(0, baseUrl.length - 4);
    }

    return baseUrl;
  }

  /// Resolves a relative or absolute URL.
  ///
  /// Example:
  ///
  /// resolveAssetUrl('/uploads/products/example.jpg')
  ///
  /// returns:
  ///
  /// https://fast-n-fresh-backend.onrender.com/uploads/products/example.jpg
  ///
  /// If the URL is already absolute, it is returned unchanged.
  static String resolveAssetUrl(String relativeOrAbsolute) {
    if (relativeOrAbsolute.isEmpty) {
      return relativeOrAbsolute;
    }

    if (relativeOrAbsolute.startsWith('http://') ||
        relativeOrAbsolute.startsWith('https://')) {
      return relativeOrAbsolute;
    }

    if (relativeOrAbsolute.startsWith('/')) {
      return '$assetHost$relativeOrAbsolute';
    }

    return '$assetHost/$relativeOrAbsolute';
  }
}