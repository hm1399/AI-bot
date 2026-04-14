import '../../constants/api_constants.dart';
import '../../models/api/api_error.dart';
import '../../models/experience/experience_model.dart';
import '../api/api_client.dart';

class ExperienceService {
  ExperienceService(this._apiClient);

  final ApiClient _apiClient;

  static String get _experiencePath => '${ApiConstants.basePath}/experience';

  Future<ExperienceCatalogModel> getCatalog() {
    return _apiClient.get(
      _experiencePath,
      parser: (dynamic data) => ExperienceCatalogModel.fromJson(
        _extractExperiencePayload(_coerceMap(data)),
      ),
    );
  }

  Future<SessionExperienceOverrideModel> patchSessionExperience(
    String sessionId,
    SessionExperienceOverrideModel draft,
  ) async {
    final sessionExperiencePath =
        '${ApiConstants.sessionsPath}/$sessionId/experience';
    final body = draft.toJson();

    try {
      return await _apiClient.patch(
        sessionExperiencePath,
        body: body,
        parser: (dynamic data) =>
            _parseSessionExperienceResponse(_coerceMap(data), fallback: draft),
      );
    } on ApiError catch (error) {
      if (!error.isBackendNotReady) {
        rethrow;
      }
    }

    return _apiClient.patch(
      '${ApiConstants.sessionsPath}/$sessionId',
      body: body,
      parser: (dynamic data) =>
          _parseSessionExperienceResponse(_coerceMap(data), fallback: draft),
    );
  }

  SessionExperienceOverrideModel extractSessionExperience(dynamic data) {
    return _parseSessionExperienceResponse(
      _coerceMap(data),
      fallback: const SessionExperienceOverrideModel(),
    );
  }
}

SessionExperienceOverrideModel _parseSessionExperienceResponse(
  Map<String, dynamic> json, {
  required SessionExperienceOverrideModel fallback,
}) {
  final direct = _extractExperiencePayload(json);
  if (_looksLikeSessionExperience(direct)) {
    return SessionExperienceOverrideModel.fromJson(direct);
  }

  final session = _coerceMap(json['session']);
  if (session.isNotEmpty) {
    final metadata = _coerceMap(session['metadata']);
    if (_looksLikeSessionExperience(metadata)) {
      return SessionExperienceOverrideModel.fromJson(metadata);
    }
    if (_looksLikeSessionExperience(session)) {
      return SessionExperienceOverrideModel.fromJson(session);
    }
  }

  return fallback;
}

Map<String, dynamic> _extractExperiencePayload(Map<String, dynamic> json) {
  for (final key in const <String>[
    'experience',
    'data',
    'payload',
    'session_experience',
  ]) {
    final value = _coerceMap(json[key]);
    if (value.isNotEmpty) {
      if (key == 'data') {
        final nested = _extractExperiencePayload(value);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
      if (_looksLikeExperience(value)) {
        return value;
      }
    }
  }
  return _looksLikeExperience(json) ? json : <String, dynamic>{};
}

bool _looksLikeExperience(Map<String, dynamic> json) {
  return json.containsKey('default_scene_mode') ||
      json.containsKey('active_scene_mode') ||
      json.containsKey('scene_mode') ||
      json.containsKey('active_persona') ||
      json.containsKey('persona_profile') ||
      json.containsKey('persona_fields') ||
      json.containsKey('physical_interaction');
}

bool _looksLikeSessionExperience(Map<String, dynamic> json) {
  return json.containsKey('scene_mode') ||
      json.containsKey('persona_profile') ||
      json.containsKey('persona_profile_id') ||
      json.containsKey('persona_fields');
}

Map<String, dynamic> _coerceMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (Object? key, Object? item) => MapEntry(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}
