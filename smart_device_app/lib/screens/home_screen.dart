import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/device_provider.dart';
import '../widgets/device_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 初始加载设备状态
    ref.read(deviceProvider.notifier).refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceProvider);
    final deviceNotifier = ref.read(deviceProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 设备状态卡片
              DeviceCard(
                status: deviceState.status,
                isLoading: deviceState.isLoading,
                onRefresh: () => deviceNotifier.refreshStatus(),
                onMuteToggle: () => deviceNotifier.toggleMute(),
                onLedToggle: () => deviceNotifier.toggleLed(),
                onRestart: () => _showRestartConfirmation(),
              ),
              
              const SizedBox(height: 24.0),
              
              // 快捷操作卡片
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
                        '快捷操作',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16.0,
                        mainAxisSpacing: 16.0,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildQuickActionButton(
                            context,
                            Icons.chat,
                            '对话',
                            Colors.blue,
                            () => context.go('/chat'),
                          ),
                          _buildQuickActionButton(
                            context,
                            Icons.task,
                            '任务',
                            Colors.green,
                            () => context.go('/tasks'),
                          ),
                          _buildQuickActionButton(
                            context,
                            Icons.event,
                            '日程',
                            Colors.purple,
                            () => context.go('/events'),
                          ),
                          _buildQuickActionButton(
                            context,
                            Icons.settings,
                            '设置',
                            Colors.grey,
                            () => context.go('/settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24.0),
              
              // 状态信息卡片
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
                        '系统信息',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16.0),
                      _buildInfoRow(
                        context,
                        '设备连接',
                        deviceState.status?.isOnline ?? false 
                            ? '已连接' 
                            : '未连接',
                        deviceState.status?.isOnline ?? false 
                            ? Colors.green 
                            : Colors.red,
                      ),
                      _buildInfoRow(
                        context,
                        '设备状态',
                        deviceState.status != null 
                            ? _getDeviceStateText(deviceState.status!.state)
                            : '未知',
                        Colors.blue,
                      ),
                      _buildInfoRow(
                        context,
                        'App版本',
                        '1.0.0',
                        Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(16.0),
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 32.0,
          ),
          const SizedBox(height: 8.0),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, Color color) {
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
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  String _getDeviceStateText(DeviceState state) {
    switch (state) {
      case DeviceState.standby:
        return '待机';
      case DeviceState.recording:
        return '录音中';
      case DeviceState.playing:
        return '播放中';
      default:
        return '未知';
    }
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0, // 首页
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

  void _showRestartConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重启设备'),
        content: const Text('确定要重启设备吗？这将中断当前所有操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(deviceProvider.notifier).restartDevice();
            },
            child: const Text('确定'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}