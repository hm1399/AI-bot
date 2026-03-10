import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  String? _baseUrl;  // 例如 'http://192.168.1.100:8000/api'

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  // 通用請求方法
  Future<Map<String, dynamic>> _request(String method, String endpoint, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl/$endpoint');
    http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(uri);
      } else if (method == 'POST') {
        response = await http.post(uri, body: jsonEncode(body), headers: {'Content-Type': 'application/json'});
      } else if (method == 'PUT') {
        response = await http.put(uri, body: jsonEncode(body), headers: {'Content-Type': 'application/json'});
      } else {
        throw Exception('Unsupported method');
      }
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // GET /api/config
  Future<Map<String, dynamic>> getConfig() async {
    return _request('GET', 'config');
  }

  // PUT /api/config
  Future<void> updateConfig(Map<String, dynamic> config) async {
    await _request('PUT', 'config', body: config);
  }

  // GET /api/device/status
  Future<Map<String, dynamic>> getDeviceStatus() async {
    return _request('GET', 'device/status');
  }

  // GET /api/history
  Future<List<dynamic>> getHistory() async {
    final data = await _request('GET', 'history');
    return data['history'] as List<dynamic>;  // 假設回應有 history 陣列
  }

  // POST /api/chat
  Future<Map<String, dynamic>> postChat(String message) async {
    return _request('POST', 'chat', body: {'message': message});
  }
}
