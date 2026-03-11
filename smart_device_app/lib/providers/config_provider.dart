import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';
import '../services/api_service.dart';

final configProvider = StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  return ConfigNotifier();
});

class ConfigNotifier extends StateNotifier<AppConfig> {
  static const String _configKey = 'app_config';
  
  ConfigNotifier() : super(_getDefaultConfig()) {
    _loadConfig();
  }
  
  // 加载配置
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configKey);
      
      if (configJson != null) {
        final config = AppConfig.fromJson(configJson as Map<String, dynamic>);
        state = config;
      }
    } catch (e) {
      print('Error loading config: $e');
    }
  }
  
  // 保存配置
  Future<void> _saveConfig(AppConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, config.toJson().toString());
    } catch (e) {
      print('Error saving config: $e');
    }
  }
  
  // 从服务器同步配置
  Future<void> syncConfigFromServer(String serverIp, int serverPort) async {
    try {
      final apiService = ApiService(baseUrl: '$serverIp:$serverPort');
      final serverConfig = await apiService.getConfig();
      
      // 保留本地的服务器IP和端口
      final updatedConfig = serverConfig.copyWith(
        serverIp: serverIp,
        serverPort: serverPort,
      );
      
      state = updatedConfig;
      await _saveConfig(updatedConfig);
    } catch (e) {
      print('Error syncing config from server: $e');
      throw Exception('Failed to sync config from server');
    }
  }
  
  // 更新配置
  Future<void> updateConfig(AppConfig newConfig) async {
    try {
      // 先更新本地状态
      state = newConfig;
      await _saveConfig(newConfig);
      
      // 然后尝试更新服务器配置
      final apiService = ApiService(baseUrl: '${newConfig.serverIp}:${newConfig.serverPort}');
      await apiService.updateConfig(newConfig);
    } catch (e) {
      print('Error updating config: $e');
      throw Exception('Failed to update config');
    }
  }
  
  // 更新服务器连接信息
  Future<void> updateServerConnection(String serverIp, int serverPort) async {
    final newConfig = state.copyWith(
      serverIp: serverIp,
      serverPort: serverPort,
    );
    
    state = newConfig;
    await _saveConfig(newConfig);
  }
  
  // 更新LLM配置
  Future<void> updateLlmConfig({
    String? apiKey,
    String? model,
  }) async {
    final newConfig = state.copyWith(
      llmApiKey: apiKey ?? state.llmApiKey,
      llmModel: model ?? state.llmModel,
    );
    
    await updateConfig(newConfig);
  }
  
  // 更新语音配置
  Future<void> updateVoiceConfig({
    String? voice,
    double? speed,
  }) async {
    final newConfig = state.copyWith(
      ttsVoice: voice ?? state.ttsVoice,
      ttsSpeed: speed ?? state.ttsSpeed,
    );
    
    await updateConfig(newConfig);
  }
  
  // 更新设备配置
  Future<void> updateDeviceConfig({
    int? volume,
    String? ledMode,
  }) async {
    final newConfig = state.copyWith(
      deviceVolume: volume ?? state.deviceVolume,
      ledMode: ledMode ?? state.ledMode,
    );
    
    await updateConfig(newConfig);
  }
  
  // 重置为默认配置
  Future<void> resetToDefault() async {
    final defaultConfig = _getDefaultConfig();
    state = defaultConfig;
    await _saveConfig(defaultConfig);
  }
  
  // 获取默认配置
  static AppConfig _getDefaultConfig() {
    return AppConfig(
      serverIp: '192.168.1.1',
      serverPort: 8080,
      llmApiKey: '',
      llmModel: 'gpt-3.5-turbo',
      ttsVoice: 'default',
      ttsSpeed: 1.0,
      deviceVolume: 80,
      ledMode: 'normal',
    );
  }
}