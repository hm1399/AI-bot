import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/discovery_service.dart';
import '../service/api_service.dart';
import '../service/ws_service.dart';
import '../providers/ws_handlers.dart'; // 导入所有处理器

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  _ConnectScreenState createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  bool _isScanning = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _autoDiscover() async {
    setState(() => _isScanning = true);
    final server = await DiscoveryService.discoverServer();
    setState(() => _isScanning = false);
    if (server != null) {
      final parts = server.split(':');
      _ipController.text = parts[0];
      _portController.text = parts[1];
      _connect(server);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('未发现服务端，请手动输入')),
      );
    }
  }

  Future<void> _connect(String address) async {
    // 构建 baseUrl
    final baseUrl = 'http://$address';
    final api = ApiService(baseUrl);

    // 验证连接
    final ok = await api.healthCheck();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法连接到服务端，请检查地址')),
      );
      return;
    }

    // 保存地址到 SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', address);

    // 初始化 WebSocket 连接
    final wsService = WebSocketService();
    await wsService.connect(address);

    // 注册所有消息处理器
    wsService.addHandler(ref.read(chatWsHandlerProvider as ProviderListenable<MessageHandler>));
    wsService.addHandler(ref.read(deviceWsHandlerProvider as ProviderListenable<MessageHandler>));
    wsService.addHandler(ref.read(taskWsHandlerProvider as ProviderListenable<MessageHandler>));
    wsService.addHandler(ref.read(eventWsHandlerProvider as ProviderListenable<MessageHandler>));
    wsService.addHandler(ref.read(configWsHandlerProvider as ProviderListenable<MessageHandler>));

    // 跳转到主页
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('连接设备')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'IP 地址',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: '端口',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isScanning ? null : _autoDiscover,
                    child: _isScanning
                        ? CircularProgressIndicator()
                        : Text('自动发现'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final address = '${_ipController.text}:${_portController.text}';
                      _connect(address);
                    },
                    child: Text('连接'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}