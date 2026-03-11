import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class DiscoveryService {
  static const String _serviceType = '_http._tcp';  // 假設 AI-Bot 註冊此服務
  String? _discoveredUrl;

  // mDNS 發現
  Future<String?> discover() async {
    final prefs = await SharedPreferences.getInstance();
    _discoveredUrl = prefs.getString('server_url');
    if (_discoveredUrl != null) return _discoveredUrl;

    final client = MDnsClient();
    await client.start();
    await for (final PtrDomainNameRecord ptr in client.lookup<PtrDomainNameRecord>(ResourceRecordQuery.serverPointer(_serviceType))) {
      await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
        await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
          final url = 'http://${ip.address.address}:${srv.port}/api/health';
          if (await _checkHealth(url)) {
            _discoveredUrl = 'http://${ip.address.address}:${srv.port}/api';
            prefs.setString('server_url', _discoveredUrl!);
            client.stop();
            return _discoveredUrl;
          }
        }
      }
    }
    client.stop();
    return null;
  }

  // 檢查 /api/health
  Future<bool> _checkHealth(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // 手動輸入備用
  Future<void> manualInput(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    _discoveredUrl = 'http://$ip:$port/api';
    prefs.setString('server_url', _discoveredUrl!);
  }
}
