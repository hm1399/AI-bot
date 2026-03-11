import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/config_provider.dart';
import '../services/discovery_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final DiscoveryService _discoveryService = DiscoveryService();
  bool _isScanning = false;
  bool _isConnecting = false;
  List<String> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    final config = ref.read(configProvider);
    _ipController.text = config.serverIp;
    _portController.text = config.serverPort.toString();
    _apiKeyController.text = config.llmApiKey;
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
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
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e')),
      );
    }
  }

  Future<void> _connectToDevice(String ip) async {
    setState(() {
      _isConnecting = true;
    });

    try {
      final configNotifier = ref.read(configProvider.notifier);
      await configNotifier.updateServerConnection(ip, int.parse(_portController.text));
      
      // 保存设备信息
      await _discoveryService.saveDeviceIp(ip, int.parse(_portController.text));
      
      setState(() {
        _ipController.text = ip;
        _isConnecting = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接成功')),
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败: $e')),
      );
    }
  }

  Future<void> _saveConnectionSettings() async {
    if (_ipController.text.isEmpty || _portController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整的连接信息')),
      );
      return;
    }

    try {
      final configNotifier = ref.read(configProvider.notifier);
      await configNotifier.updateServerConnection(
        _ipController.text,
        int.parse(_portController.text),
      );
      
      // 保存设备信息
      await _discoveryService.saveDeviceIp(
        _ipController.text,
        int.parse(_portController.text),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接信息已保存')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _saveLlmSettings() async {
    try {
      final configNotifier = ref.read(configProvider.notifier);
      await configNotifier.updateLlmConfig(
        apiKey: _apiKeyController.text,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LLM配置已保存')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _resetSettings() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置设置'),
        content: const Text('确定要重置所有设置吗？这将清除所有配置信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final configNotifier = ref.read(configProvider.notifier);
                await configNotifier.resetToDefault();
                await _discoveryService.clearSavedDeviceIp();
                _loadConfig();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置已重置')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('重置失败: $e')),
                );
              }
            },
            child: const Text('重置'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 服务端连接设置
              Card(
                elevation: 2.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '服务端连接',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      
                      // 自动扫描
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isScanning ? null : _scanDevices,
                              style: ElevatedButton.styleFrom(
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
                          ),
                        ],
                      ),
                      
                      // 发现的设备列表
                      if (_discoveredDevices.isNotEmpty) ...[
                        const SizedBox(height: 16.0),
                        Text(
                          '发现的设备:',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8.0),
                        ..._discoveredDevices.map((device) => ListTile(
                          title: Text(device),
                          trailing: _isConnecting && _ipController.text == device
                              ? const SizedBox(
                                  width: 20.0,
                                  height: 20.0,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          onTap: () => _connectToDevice(device),
                        )),
                      ],
                      
                      const SizedBox(height: 16.0),
                      
                      // 手动输入
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: '服务器IP',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: '端口',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton(
                        onPressed: _saveConnectionSettings,
                        child: const Text('保存连接设置'),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24.0),
              
              // LLM配置
              Card(
                elevation: 2.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LLM配置',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      TextField(
                        controller: _apiKeyController,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk-...',
                          border: const OutlineInputBorder(),
                          helperText: '当前显示: ${config.maskedApiKey}',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16.0),
                      DropdownButtonFormField<String>(
                        value: config.llmModel,
                        decoration: const InputDecoration(
                          labelText: '模型',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'gpt-3.5-turbo',
                            child: Text('GPT-3.5 Turbo'),
                          ),
                          DropdownMenuItem(
                            value: 'gpt-4',
                            child: Text('GPT-4'),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            try {
                              final configNotifier = ref.read(configProvider.notifier);
                              await configNotifier.updateLlmConfig(model: value);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('模型已更新')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('更新失败: $e')),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton(
                        onPressed: _saveLlmSettings,
                        child: const Text('保存LLM配置'),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24.0),
              
              // 语音配置
              Card(
                elevation: 2.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '语音配置',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      DropdownButtonFormField<String>(
                        value: config.ttsVoice,
                        decoration: const InputDecoration(
                          labelText: '语音角色',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'default',
                            child: Text('默认'),
                          ),
                          DropdownMenuItem(
                            value: 'male',
                            child: Text('男声'),
                          ),
                          DropdownMenuItem(
                            value: 'female',
                            child: Text('女声'),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            try {
                              final configNotifier = ref.read(configProvider.notifier);
                              await configNotifier.updateVoiceConfig(voice: value);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('语音角色已更新')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('更新失败: $e')),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 16.0),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('语速: ${config.ttsSpeed.toStringAsFixed(1)}x'),
                          Slider(
                            value: config.ttsSpeed,
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            onChanged: (value) async {
                              try {
                                final configNotifier = ref.read(configProvider.notifier);
                                await configNotifier.updateVoiceConfig(speed: value);
                              } catch (e) {
                                print('更新语速失败: $e');
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24.0),
              
              // 设备配置
              Card(
                elevation: 2.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设备配置',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('音量: ${config.deviceVolume}%'),
                          Slider(
                            value: config.deviceVolume.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 10,
                            onChanged: (value) async {
                              try {
                                final configNotifier = ref.read(configProvider.notifier);
                                await configNotifier.updateDeviceConfig(volume: value.toInt());
                              } catch (e) {
                                print('更新音量失败: $e');
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16.0),
                      DropdownButtonFormField<String>(
                        value: config.ledMode,
                        decoration: const InputDecoration(
                          labelText: 'LED灯效模式',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('正常'),
                          ),
                          DropdownMenuItem(
                            value: 'breathing',
                            child: Text('呼吸灯'),
                          ),
                          DropdownMenuItem(
                            value: 'off',
                            child: Text('关闭'),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            try {
                              final configNotifier = ref.read(configProvider.notifier);
                              await configNotifier.updateDeviceConfig(ledMode: value);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('LED模式已更新')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('更新失败: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24.0),
              
              // 关于
              Card(
                elevation: 2.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '关于',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      _buildInfoRow(context, 'App版本', '1.0.0'),
                      _buildInfoRow(context, '连接状态', config.serverIp.isNotEmpty ? '已配置' : '未配置'),
                      _buildInfoRow(context, '服务器地址', '${config.serverIp}:${config.serverPort}'),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24.0),
              
              // 重置设置
              ElevatedButton(
                onPressed: _resetSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('重置所有设置'),
              ),
              
              const SizedBox(height: 48.0),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 3, // 设置
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/home');
            break;
          case 1:
            context.go('/chat');
            break;
          case 2:
            context.go('/tasks');
            break;
          case 3:
            context.go('/settings');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: '首页',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat),
          label: '对话',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.task),
          label: '任务',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    _discoveryService.dispose();
    super.dispose();
  }
}