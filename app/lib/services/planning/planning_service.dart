import '../../constants/api_constants.dart';
import '../../models/planning/planning_conflict_model.dart';
import '../../models/planning/planning_overview_model.dart';
import '../../models/planning/planning_timeline_item_model.dart';
import '../api/api_client.dart';

class PlanningService {
  PlanningService(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> createBundle(Map<String, dynamic> body) {
    return _apiClient.post(
      ApiConstants.planningBundlesPath,
      body: body,
      parser: (dynamic data) =>
          data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
  }

  Future<PlanningOverviewModel> fetchOverview({Map<String, String>? query}) {
    return _apiClient.get(
      ApiConstants.planningOverviewPath,
      query: query,
      parser: (dynamic data) =>
          PlanningOverviewModel.fromJson(_coerceMap(data)),
    );
  }

  Future<List<PlanningTimelineItemModel>> fetchTimeline({
    Map<String, String>? query,
  }) {
    return _apiClient.get(
      ApiConstants.planningTimelinePath,
      query: query,
      parser: (dynamic data) =>
          _extractItems(data, const <String>['items', 'timeline']).map((
            dynamic item,
          ) {
            return PlanningTimelineItemModel.fromJson(
              item is Map<String, dynamic> ? item : <String, dynamic>{},
            );
          }).toList(),
    );
  }

  Future<List<PlanningConflictModel>> fetchConflicts({
    Map<String, String>? query,
  }) {
    return _apiClient.get(
      ApiConstants.planningConflictsPath,
      query: query,
      parser: (dynamic data) =>
          _extractItems(data, const <String>['items', 'conflicts']).map((
            dynamic item,
          ) {
            return PlanningConflictModel.fromJson(
              item is Map<String, dynamic> ? item : <String, dynamic>{},
            );
          }).toList(),
    );
  }
}

Map<String, dynamic> _coerceMap(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  return <String, dynamic>{};
}

List<dynamic> _extractItems(dynamic data, List<String> keys) {
  if (data is List) {
    return data;
  }
  if (data is Map<String, dynamic>) {
    for (final key in keys) {
      final value = data[key];
      if (value is List) {
        return value;
      }
    }
  }
  return const <dynamic>[];
}
