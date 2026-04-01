import '../../constants/api_constants.dart';
import '../../models/connect/bootstrap_model.dart';
import '../api/api_client.dart';

class BootstrapService {
  BootstrapService(this._apiClient);

  final ApiClient _apiClient;

  Future<BootstrapModel> fetchBootstrap() {
    return _apiClient.get(
      ApiConstants.bootstrapPath,
      parser: (dynamic data) => BootstrapModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }

  Future<CapabilitiesModel> fetchCapabilities() {
    return _apiClient.get(
      ApiConstants.capabilitiesPath,
      parser: (dynamic data) => CapabilitiesModel.fromJson(
        data is Map<String, dynamic> ? data : <String, dynamic>{},
      ),
    );
  }
}
