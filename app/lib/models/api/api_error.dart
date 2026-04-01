class ApiError implements Exception {
  ApiError({
    required this.code,
    required this.message,
    required this.statusCode,
    this.requestId,
  });

  final String code;
  final String message;
  final int statusCode;
  final String? requestId;

  bool get isUnauthorized => code == 'UNAUTHORIZED' || statusCode == 401;

  bool get isBackendNotReady =>
      statusCode == 404 || statusCode == 501 || code == 'NOT_IMPLEMENTED';

  @override
  String toString() => '$code ($statusCode): $message';
}
