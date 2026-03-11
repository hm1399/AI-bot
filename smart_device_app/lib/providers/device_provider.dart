import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_status.dart';
import '../services/ws_service.dart';
import '../services/api_service.dart';

final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceState>((ref) {
  final wsService = ref.watch(wsServiceProvider);
  final apiService = ref.watch(apiServiceProvider);
  return DeviceNotifier(wsService, apiService);
});

class DeviceState {
  final DeviceStatus? status;
  final bool isLoading;
  final String? error;
  
  DeviceState({
    this.status,
    this.isLoading = false,
    this.error
  });
  
  DeviceState copyWith({
    DeviceStatus? status,
    bool? isLoading,
    String? error,
  }) {
    return DeviceState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class DeviceNotifier extends StateNotifier<DeviceState> {
  final WSService _wsService;
  final ApiService _apiService;
  Timer? _refreshTimer;
  
  DeviceNotifier(this._wsService, this._apiService) 
    : super(DeviceState()) {
    _startPeriodicRefresh();
    _setupListeners();
  }
  
  // 刷新设备状态
  Future<void> refreshStatus() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final status = await _apiService.getDeviceStatus();
      state = state.copyWith(status: status, isLoading: false);
    } catch (e) {
      print('Error refreshing device status: $e');
      state = state.copyWith(
        isLoading: false, 
        error: 'Failed to refresh device status',
        // 保持之前的状态，但标记为离线
        status: state.status?.copyWith(
          isOnline: false,
          lastUpdated: DateTime.now(),
        ),
      );
    }
  }
  
  // 发送设备命令
  Future<void> sendCommand(String command, [Map<String, dynamic>? params]) async {
    try {
      final message = {
        'type': 'command',
        'command': command,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      if (params != null) {
        message.addAll(params);
      }
      
      _wsService.sendMessage(message);
      
      // 立即更新本地状态（乐观更新）
      if (command == 'mute') {
        // 处理静音命令
      } else if (command == 'led') {
        // 处理LED命令
      } else if (command == 'restart') {
        // 处理重启命令
        state = state.copyWith(
          status: state.status?.copyWith(
            state: DeviceState.standby,
            lastUpdated: DateTime.now(),
          ),
        );
      }
      
      // 刷新状态以获取最新信息
      await Future.delayed(const Duration(seconds: 1));
      await refreshStatus();
    } catch (e) {
      print('Error sending command: $e');
      state = state.copyWith(error: 'Failed to send command');
    }
  }
  
  // 切换静音状态
  Future<void> toggleMute() async {
    await sendCommand('mute', {'toggle': true});
  }
  
  // 切换LED状态
  Future<void> toggleLed() async {
    await sendCommand('led', {'toggle': true});
  }
  
  // 重启设备
  Future<void> restartDevice() async {
    await sendCommand('restart');
  }
  
  // 定期刷新设备状态
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      refreshStatus();
    });
  }
  
  // 设置WebSocket监听器
  void _setupListeners() {
    // 监听设备状态更新
    _wsService.messageStream.listen((data) {
      if (data['type'] == 'deviceStatus') {
        try {
          final status = DeviceStatus.fromJson(data);
          state = state.copyWith(status: status, error: null);
        } catch (e) {
          print('Error parsing device status: $e');
        }
      }
    });
    
    // 监听连接状态变化
    _wsService.connectionStatusStream.listen((isConnected) {
      if (!isConnected && state.status != null) {
        // 连接断开，更新设备状态为离线
        state = state.copyWith(
          status: state.status?.copyWith(
            isOnline: false,
            lastUpdated: DateTime.now(),
          ),
        );
      } else if (isConnected) {
        // 连接恢复，刷新设备状态
        refreshStatus();
      }
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}