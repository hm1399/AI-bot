import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/app_config.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/config_provider.dart';
import '../service/api_service.dart';
import '../service/ws_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAddress();
  }

  Future<void> _loadSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('serverAddress') ?? '';
    if (address.isNotEmpty) {
      final parts = address.split(':');
      setState(() {
        _ipController.text = parts[0];
        if (parts.length > 1) _portController.text = parts[1];
      });
    }
  }

  Future<void> _reconnect() async {
    final address = '${_ipController.text}:${_portController.text}';
    setState(() => _isConnecting = true);

    final api = ApiService('http://$address');
    final ok = await api.healthCheck();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法连接到服务端')),
      );
      setState(() => _isConnecting = false);
      return;
    }

    // 保存新地址
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverAddress', address);

    // 重新连接 WebSocket
    WebSocketService().disconnect();
    await WebSocketService().connect(address);

    // 重新注册处理器（需要在连接后重新注册）
    // 这里简化处理，实际应该在连接后由主页面重新注册

    setState(() => _isConnecting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已重新连接')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);

    return Scaffold(
      appBar: AppBar(title: Text('设置')),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('服务端连接', style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 8),
                  TextField(
                    controller: _ipController,
                    decoration: InputDecoration(labelText: 'IP 地址'),
                  ),
                  TextField(
                    controller: _portController,
                    decoration: InputDecoration(labelText: '端口'),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _isConnecting ? null : _reconnect,
                    child: _isConnecting ? CircularProgressIndicator() : Text('重新连接'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LLM 配置', style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 8),
                  TextFormField(
                    initialValue: config?.llmApiKey ?? '',
                    decoration: InputDecoration(labelText: 'API Key'),
                    obscureText: true,
                    onChanged: (value) {
                      // 更新配置（需要通过 API 保存）
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: config?.model,
                    items: ['gpt-3.5-turbo', 'gpt-4'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (value) {},
                    decoration: InputDecoration(labelText: '模型'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('语音配置', style: Theme.of(context).textTheme.titleMedium),
                  // ... 类似其他配置项
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于', style: Theme.of(context).textTheme.titleMedium),
                  ListTile(
                    title: Text('版本'),
                    trailing: Text('1.0.0'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on AppConfig? {
  String? get model => null;
}