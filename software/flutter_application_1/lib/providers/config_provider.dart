import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/app_config.dart';
import '../services/api_service.dart';

class ConfigNotifier extends StateNotifier<AppConfig?> {
  ConfigNotifier() : super(null);

  void setConfig(AppConfig config) {
    state = config;
  }

  // 从服务端加载配置
  Future<void> loadConfig(ApiService api) async {
    try {
      final config = await api.getConfig();
      setConfig(config);
    } catch (e) {
      print('Failed to load config: $e');
    }
  }

  // 更新配置（本地+远程）
  Future<void> updateConfig(AppConfig newConfig, ApiService api) async {
    try {
      await api.updateConfig(newConfig);
      setConfig(newConfig);
    } catch (e) {
      print('Failed to update config: $e');
    }
  }

  void handleWsMessage(Map<String, dynamic> message) {
    if (message['type'] == 'config_update') {
      final config = AppConfig.fromJson(message['data']);
      setConfig(config);
    }
  }
}

final configProvider = StateNotifierProvider<ConfigNotifier, AppConfig?>((ref) {
  return ConfigNotifier();
});

final configWsHandlerProvider = Provider<Function>((ref) {
  return (Map<String, dynamic> message) {
    ref.read(configProvider.notifier).handleWsMessage(message);
  };
});