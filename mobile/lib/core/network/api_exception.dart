/// Uniform exception thrown by services when an API call fails, carrying a
/// human-readable message (taken from the backend's `message` field when
/// available) so screens can show it directly.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final List<dynamic>? details;

  ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() => message;
}
