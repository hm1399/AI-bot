import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DiscoveryService {
  static const String _savedIpKey = 'device_ip';
  static const String _savedPortKey = 'device_port';
  static const int _defaultPort = 8080;
  static const Duration _scanTimeout = Duration(seconds: 2);
  static const Duration _healthCheckTimeout = Duration(seconds: 1);
  
  final http.Client _client;
  
  DiscoveryService() : _client = http.Client();
  
  // 扫描局域网设备
  Future<List<String>> scanDevices() async {
    final List<String> discoveredDevices = [];
    final Completer<List<String>> completer = Completer<List<String>>();
    
    // 获取设备IP地址
    final interfaces = await NetworkInterface.list();
    final List<Future<void>> scanFutures = [];
    
    for (var interface in interfaces) {
      for (var address in interface.addresses) {
        if (address.type == InternetAddressType.IPv4) {
          final String subnet = _getSubnet(address.address);
          final Future<void> scanFuture = _scanSubnet(subnet, discoveredDevices);
          scanFutures.add(scanFuture);
        }
      }
    }
    
    // 等待所有扫描完成
    Future.wait(scanFutures).then((_) {
      completer.complete(discoveredDevices);
    }).catchError((error) {
      print('Error scanning network: $error');
      completer.complete(discoveredDevices);
    });
    
    // 设置超时
    Timer(_scanTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(discoveredDevices);
      }
    });
    
    return completer.future;
  }
  
  // 扫描子网
  Future<void> _scanSubnet(String subnet, List<String> discoveredDevices) async {
    final List<Future<void>> pingFutures = [];
    
    // 扫描子网中的所有IP（简化版，实际可能需要更复杂的逻辑）
    for (int i = 1; i <= 254; i++) {
      final String ip = '$subnet.$i';
      final Future<void> pingFuture = _checkDevice(ip, _defaultPort)
          .then((isAlive) {
            if (isAlive && !discoveredDevices.contains(ip)) {
              discoveredDevices.add(ip);
            }
          });
      pingFutures.add(pingFuture);
    }
    
    await Future.wait(pingFutures);
  }
  
  // 获取子网地址
  String _getSubnet(String ip) {
    final parts = ip.split('.');
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }
  
  // 检查设备是否在线
  Future<bool> isDeviceOnline(String ip, int port) async {
    return _checkDevice(ip, port);
  }
  
  // 检查设备是否为我们的目标设备
  Future<bool> _checkDevice(String ip, int port) async {
    try {
      final response = await _client.get(
        Uri.parse('http://$ip:$port/api/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(_healthCheckTimeout);
      
      if (response.statusCode == 200) {
        // 验证响应是否来自我们的设备
        try {
          final Map<String, dynamic> data = response.body as Map<String, dynamic>;
          return data.containsKey('deviceType') && data['deviceType'] == 'smartAssistant';
        } catch (e) {
          // 如果响应不是JSON或不包含预期字段，仍认为是有效设备
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  // 保存设备IP和端口
  Future<void> saveDeviceIp(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedIpKey, ip);
    await prefs.setInt(_savedPortKey, port);
  }
  
  // 获取保存的设备IP和端口
  Future<Map<String, dynamic>?> getSavedDeviceIp() async {
    final prefs = await SharedPreferences.getInstance();
    final String? ip = prefs.getString(_savedIpKey);
    final int? port = prefs.getInt(_savedPortKey);
    
    if (ip != null && port != null) {
      return {'ip': ip, 'port': port};
    }
    return null;
  }
  
  // 清除保存的设备IP和端口
  Future<void> clearSavedDeviceIp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedIpKey);
    await prefs.remove(_savedPortKey);
  }
  
  void dispose() {
    _client.close();
  }
}