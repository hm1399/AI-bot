import '../../constants/api_constants.dart';
import '../../models/home/runtime_state_model.dart';
import '../api/api_client.dart';

class DeviceService {
  DeviceService(this._apiClient);

  final ApiClient _apiClient;

  Future<DeviceStatusModel> getDevice() {
    return _apiClient.get(
      ApiConstants.devicePath,
      parser: (dynamic data) => DeviceStatusModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<Map<String, dynamic>> speak(String text) {
    return _apiClient.post(
      ApiConstants.deviceSpeakPath,
      body: <String, dynamic>{'text': text},
      parser: (dynamic data) =>
          data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> sendCommand(
    String command, {
    Map<String, dynamic>? params,
    String? clientCommandId,
  }) {
    return _apiClient.post(
      ApiConstants.deviceCommandsPath,
      body: <String, dynamic>{
        'command': command,
        if (params != null) 'params': params,
        if (clientCommandId != null) 'client_command_id': clientCommandId,
      },
      parser: (dynamic data) =>
          data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
  }
}
