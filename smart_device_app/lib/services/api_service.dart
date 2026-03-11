import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_config.dart';
import '../models/device_status.dart';
import '../models/message.dart';
import '../models/task.dart';
import '../models/event.dart';

class ApiService {
  final String baseUrl;
  final http.Client _client;
  
  ApiService({required this.baseUrl}) : _client = http.Client();
  
  // 获取配置
  Future<AppConfig> getConfig() async {
    try {
      final response = await _client.get(Uri.parse('http://$baseUrl/api/config'));
      _checkResponse(response);
      return AppConfig.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 更新配置
  Future<void> updateConfig(AppConfig config) async {
    try {
      final response = await _client.put(
        Uri.parse('http://$baseUrl/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config.toJson()),
      );
      _checkResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 获取设备状态
  Future<DeviceStatus> getDeviceStatus() async {
    try {
      final response = await _client.get(Uri.parse('http://$baseUrl/api/device/status'));
      _checkResponse(response);
      return DeviceStatus.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 获取历史消息
  Future<List<Message>> getHistory() async {
    try {
      final response = await _client.get(Uri.parse('http://$baseUrl/api/history'));
      _checkResponse(response);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Message.fromJson(json)).toList();
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 发送聊天消息
  Future<void> sendChatMessage(String content) async {
    try {
      final response = await _client.post(
        Uri.parse('http://$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': content}),
      );
      _checkResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 获取任务列表
  Future<List<Task>> getTasks() async {
    try {
      final response = await _client.get(Uri.parse('http://$baseUrl/api/tasks'));
      _checkResponse(response);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 创建任务
  Future<Task> createTask(Task task) async {
    try {
      final response = await _client.post(
        Uri.parse('http://$baseUrl/api/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(task.toJson()),
      );
      _checkResponse(response);
      return Task.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 更新任务
  Future<Task> updateTask(Task task) async {
    try {
      final response = await _client.put(
        Uri.parse('http://$baseUrl/api/tasks/${task.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(task.toJson()),
      );
      _checkResponse(response);
      return Task.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 删除任务
  Future<void> deleteTask(String taskId) async {
    try {
      final response = await _client.delete(Uri.parse('http://$baseUrl/api/tasks/$taskId'));
      _checkResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 获取事件列表
  Future<List<Event>> getEvents() async {
    try {
      final response = await _client.get(Uri.parse('http://$baseUrl/api/events'));
      _checkResponse(response);
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Event.fromJson(json)).toList();
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 创建事件
  Future<Event> createEvent(Event event) async {
    try {
      final response = await _client.post(
        Uri.parse('http://$baseUrl/api/events'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(event.toJson()),
      );
      _checkResponse(response);
      return Event.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 更新事件
  Future<Event> updateEvent(Event event) async {
    try {
      final response = await _client.put(
        Uri.parse('http://$baseUrl/api/events/${event.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(event.toJson()),
      );
      _checkResponse(response);
      return Event.fromJson(jsonDecode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 删除事件
  Future<void> deleteEvent(String eventId) async {
    try {
      final response = await _client.delete(Uri.parse('http://$baseUrl/api/events/$eventId'));
      _checkResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // 检查响应状态
  void _checkResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'API Error: ${response.statusCode}',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }
  
  // 处理错误
  Exception _handleError(dynamic e) {
    if (e is ApiException) {
      return e;
    } else if (e is http.ClientException) {
      return ApiException('Network error: ${e.message}');
    } else {
      return ApiException('Unknown error: $e');
    }
  }
  
  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;
  
  ApiException(this.message, {this.statusCode, this.body});
  
  @override
  String toString() {
    return 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
  }
}