import 'package:dio/dio.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'token_storage.dart';

/// Callback invoked when the server tells us the session is no longer valid
/// (expired/invalid token, deactivated account). Wired up in main.dart to
/// force a return to the login screen.
typedef OnUnauthorized = void Function();

class DioClient {
  DioClient._internal();
  static final DioClient instance = DioClient._internal();

  late final Dio dio = _build();
  OnUnauthorized? onUnauthorized;

  Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.instance.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (DioException e, handler) {
          if (e.response?.statusCode == 401) {
            onUnauthorized?.call();
          }
          handler.next(e);
        },
      ),
    );

    return dio;
  }

  /// Converts any DioException into a friendly [ApiException] with the
  /// backend's message, or a sensible fallback for network/timeout issues.
  ApiException mapError(Object error) {
    if (error is DioException) {
      final response = error.response;
      if (response != null && response.data is Map) {
        final data = response.data as Map;
        final message = data['message']?.toString() ?? 'Something went wrong.';
        final details = data['details'] as List<dynamic>?;
        return ApiException(message, statusCode: response.statusCode, details: details);
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException('Request timed out. Check your connection and try again.');
        case DioExceptionType.connectionError:
          return ApiException('No internet connection. Please check your network and retry.');
        default:
          return ApiException('Something went wrong. Please try again.');
      }
    }
    return ApiException('Unexpected error: $error');
  }
}
