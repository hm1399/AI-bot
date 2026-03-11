import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/discovery_service.dart';
import '../providers/config_provider.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8080');
  final DiscoveryService _discoveryService = DiscoveryService();
  List<String> _discoveredDevices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkSavedConnection();
  }

  Future<void> _checkSavedConnection() async {
    final savedDevice = await _discoveryService.getSavedDeviceIp();
    if (savedDevice != null) {
      _ipController.text = savedDevice['ip'] as String;
      _portController.text = savedDevice['port'].toString();
    }
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _discoveredDevices = [];
    });

    try {
      final devices = await _discoveryService.scanDevices();
      setState(() {
        _discoveredDevices = devices;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '扫描设备失败: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(String ip, String port) async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final configNotifier = ref.read(configProvider.notifier);
      
      // 更新服务器连接信息
      await configNotifier.updateServerConnection(ip, int.parse(port));
      
      // 尝试同步服务器配置
      try {
        await configNotifier.syncConfigFromServer(ip, int.parse(port));
      } catch (e) {
        print('无法同步服务器配置，使用默认配置');
      }
      
      // 保存设备信息
      await _discoveryService.saveDeviceIp(ip, int.parse(port));
      
      // 导航到首页
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '连接失败: $e';
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设备'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32.0),
            Center(
              child: Icon(
                Icons.bluetooth_searching,
                size: 80.0,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16.0),
            Center(
              child: Text(
                '连接到智能设备',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 32.0),
            
            // 手动输入部分
            Card(
              elevation: 2.0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '手动输入设备地址',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'IP地址',
                        hintText: '例如: 192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.ipAddress,
                    ),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '例如: 8080',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24.0),
                    ElevatedButton(
                      onPressed: _isConnecting 
                          ? null 
                          : () => _connectToDevice(_ipController.text, _portController.text),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                      ),
                      child: _isConnecting 
                          ? const SizedBox(
                              width: 20.0,
                              height: 20.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: Colors.white,
                              ),
                            )
                          : const Text('连接'),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24.0),
            
            // 自动扫描部分
            Card(
              elevation: 2.0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '或自动扫描设备',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16.0),
                    ElevatedButton(
                      onPressed: _isScanning ? null : _scanDevices,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                      ),
                      child: _isScanning 
                          ? const SizedBox(
                              width: 20.0,
                              height: 20.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: Colors.white,
                              ),
                            )
                          : const Text('扫描设备'),
                    ),
                    
                    if (_discoveredDevices.isNotEmpty) ...[
                      const SizedBox(height: 16.0),
                      Text(
                        '发现的设备:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8.0),
                      ..._discoveredDevices.map((device) => ListTile(
                        title: Text(device),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () => _connectToDevice(device, _portController.text),
                      )),
                    ],
                  ],
                ),
              ),
            ),
            
            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 16.0),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _discoveryService.dispose();
    super.dispose();
  }
}