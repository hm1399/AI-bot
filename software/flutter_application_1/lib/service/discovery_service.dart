import 'dart:io';
import 'package:http/http.dart' as http;

class DiscoveryService {
  static const int timeoutSeconds = 2;
  static const String healthPath = '/api/health';

  /// 扫描局域网，返回第一个响应的服务端地址 (ip:port)
  static Future<String?> discoverServer() async {
    // 获取本机IP和子网掩码（简化：扫描192.168.1.x 或根据实际网络调整）
    final localIp = await _getLocalIp();
    if (localIp == null) return null;

    final parts = localIp.split('.');
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.';

    // 并发扫描 1..254
    final List<Future<String?>> futures = [];
    for (int i = 1; i <= 254; i++) {
      final ip = subnet + i.toString();
      futures.add(_checkIp(ip));
    }

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result != null) return result;
    }
    return null;
  }

  static Future<String?> _checkIp(String ip) async {
    try {
      final url = Uri.parse('http://$ip:8080$healthPath'); // 假设端口8080
      final response = await http.get(url).timeout(Duration(seconds: timeoutSeconds));
      if (response.statusCode == 200) {
        return '$ip:8080';
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _getLocalIp() async {
    // 获取本机IP（简单实现，可根据平台优化）
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }
}