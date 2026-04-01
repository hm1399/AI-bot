import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../models/api/api_error.dart';
import '../../models/connect/connection_config_model.dart';

typedef JsonMap = Map<String, dynamic>;

class ApiClient {
  ConnectionConfigModel _connection = ConnectionConfigModel.empty();
  final http.Client _httpClient = http.Client();

  void setConnection(ConnectionConfigModel connection) {
    _connection = connection;
  }

  void clearConnection() {
    _connection = ConnectionConfigModel.empty();
  }

  Uri _buildUri(String path, [Map<String, String>? query]) {
    if (!_connection.hasServer) {
      throw ApiError(
        code: 'NOT_CONNECTED',
        message: 'Connect to the backend first.',
        statusCode: 400,
      );
    }
    return Uri(
      scheme: 'http',
      host: _connection.host,
      port: _connection.port,
      path: path,
      queryParameters: query,
    );
  }

  Map<String, String> _headers() {
    final token = _connection.token.trim();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (token.isNotEmpty) 'X-App-Token': token,
    };
  }

  Future<JsonMap> getRaw(
    String path, {
    Duration? timeout,
    Map<String, String>? query,
  }) async {
    return _send(
      () => _httpClient.get(_buildUri(path, query), headers: _headers()),
      skipEnvelope: true,
      timeout: timeout,
    );
  }

  Future<T> get<T>(
    String path, {
    required T Function(dynamic data) parser,
    Map<String, String>? query,
  }) async {
    final payload = await _send(
      () => _httpClient.get(_buildUri(path, query), headers: _headers()),
    );
    return parser(payload['data']);
  }

  Future<T> post<T>(
    String path, {
    required T Function(dynamic data) parser,
    Object? body,
    Map<String, String>? query,
  }) async {
    final payload = await _send(
      () => _httpClient.post(
        _buildUri(path, query),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return parser(payload['data']);
  }

  Future<T> put<T>(
    String path, {
    required T Function(dynamic data) parser,
    Object? body,
  }) async {
    final payload = await _send(
      () => _httpClient.put(
        _buildUri(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return parser(payload['data']);
  }

  Future<T> patch<T>(
    String path, {
    required T Function(dynamic data) parser,
    Object? body,
  }) async {
    final payload = await _send(
      () => _httpClient.patch(
        _buildUri(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return parser(payload['data']);
  }

  Future<void> delete(String path) async {
    await _send(() => _httpClient.delete(_buildUri(path), headers: _headers()));
  }

  Future<JsonMap> _send(
    Future<http.Response> Function() sender, {
    bool skipEnvelope = false,
    Duration? timeout,
  }) async {
    try {
      final response = await sender().timeout(
        timeout ?? AppConfig.requestTimeout,
      );
      final body = response.body.trim().isEmpty
          ? null
          : jsonDecode(response.body) as dynamic;
      final json = body is Map<String, dynamic> ? body : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiError(
          code:
              json['error']?['code']?.toString() ??
              (response.statusCode == 404 ? 'NOT_IMPLEMENTED' : 'HTTP_ERROR'),
          message:
              json['error']?['message']?.toString() ??
              response.reasonPhrase ??
              'Request failed',
          statusCode: response.statusCode,
          requestId: json['request_id']?.toString(),
        );
      }

      if (skipEnvelope) {
        return json;
      }

      if (json['ok'] != true) {
        throw ApiError(
          code: json['error']?['code']?.toString() ?? 'UNKNOWN_ERROR',
          message: json['error']?['message']?.toString() ?? 'Request failed',
          statusCode: response.statusCode,
          requestId: json['request_id']?.toString(),
        );
      }
      return json;
    } on TimeoutException {
      throw ApiError(
        code: 'TIMEOUT',
        message: 'Request timed out.',
        statusCode: 408,
      );
    } on ApiError {
      rethrow;
    } catch (error) {
      throw ApiError(
        code: 'NETWORK_ERROR',
        message: error.toString(),
        statusCode: 0,
      );
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
