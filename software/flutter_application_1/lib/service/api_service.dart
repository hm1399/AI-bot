import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/device_status.dart';
import '../models/app_config.dart';
import '../models/message.dart';

class ApiService {
  final String baseUrl; // 例如 "http://192.168.1.100:8080"

  ApiService(this.baseUrl);

  // 健康检查
  Future<bool> healthCheck() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 获取设备状态
  Future<DeviceStatus> getDeviceStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/device/status'));
    if (response.statusCode == 200) {
      return DeviceStatus.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load device status');
    }
  }

  // 获取配置
  Future<AppConfig> getConfig() async {
    final response = await http.get(Uri.parse('$baseUrl/api/config'));
    if (response.statusCode == 200) {
      return AppConfig.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load config');
    }
  }

  // 更新配置
  Future<void> updateConfig(AppConfig config) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update config');
    }
  }

  // 获取对话历史
  Future<List<Message>> getChatHistory() async {
    final response = await http.get(Uri.parse('$baseUrl/api/history'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Message.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load history');
    }
  }
}