import '../../models/control/computer_action_model.dart';
import '../api/api_client.dart';

class ComputerControlService {
  ComputerControlService(this._apiClient);

  final ApiClient _apiClient;

  static const String _computerBasePath = '/api/app/v1/computer';

  Future<ComputerControlStateModel> getState({
    List<String> fallbackSupportedActions = const <String>[],
  }) {
    return _apiClient.get(
      '$_computerBasePath/state',
      parser: (dynamic data) => ComputerControlStateModel.fromJson(
        _coerceMap(data),
        fallbackSupportedActions: fallbackSupportedActions,
      ),
    );
  }

  Future<List<ComputerActionModel>> getRecentActions() {
    return _apiClient.get(
      '$_computerBasePath/actions/recent',
      parser: (dynamic data) {
        final payload = _coerceMap(data);
        final recent = payload['recent_actions'] ?? payload['items'];
        if (recent is List) {
          return recent
              .map((dynamic item) => ComputerActionModel.fromDynamic(item))
              .toList();
        }
        if (data is List) {
          return data
              .map((dynamic item) => ComputerActionModel.fromDynamic(item))
              .toList();
        }
        return const <ComputerActionModel>[];
      },
    );
  }

  Future<ComputerActionModel> createAction(ComputerActionRequest request) {
    return _apiClient.post(
      '$_computerBasePath/actions',
      body: request.toJson(),
      parser: (dynamic data) => ComputerActionModel.fromJson(_coerceMap(data)),
    );
  }

  Future<ComputerActionModel> confirmAction(String actionId) {
    return _apiClient.post(
      '$_computerBasePath/actions/$actionId/confirm',
      parser: (dynamic data) => ComputerActionModel.fromJson(_coerceMap(data)),
    );
  }

  Future<ComputerActionModel> cancelAction(String actionId) {
    return _apiClient.post(
      '$_computerBasePath/actions/$actionId/cancel',
      parser: (dynamic data) => ComputerActionModel.fromJson(_coerceMap(data)),
    );
  }
}

Map<String, dynamic> _coerceMap(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  return <String, dynamic>{};
}
