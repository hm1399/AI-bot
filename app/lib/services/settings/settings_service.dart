import '../../constants/api_constants.dart';
import '../../models/settings/settings_model.dart';
import '../api/api_client.dart';

class SettingsService {
  SettingsService(this._apiClient);

  final ApiClient _apiClient;

  Future<AppSettingsModel> getSettings() {
    return _apiClient.get(
      ApiConstants.settingsPath,
      parser: (dynamic data) => AppSettingsModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<AppSettingsModel> updateSettings(AppSettingsUpdate update) {
    return _apiClient.put(
      ApiConstants.settingsPath,
      body: update.toJson(),
      parser: (dynamic data) => AppSettingsModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<AiConnectionTestModel> testAiConnection({AppSettingsUpdate? draft}) {
    return _apiClient.post(
      ApiConstants.settingsTestPath,
      body: draft?.toJson(),
      parser: (dynamic data) => AiConnectionTestModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }
}
