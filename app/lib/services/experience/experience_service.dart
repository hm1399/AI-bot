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

  Future<InteractionResultModel> triggerPhysicalInteraction({
    required String kind,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    return _apiClient.post(
      '$_experiencePath/interactions',
      body: <String, dynamic>{'kind': kind, 'payload': payload},
      parser: (dynamic data) =>
          _parsePhysicalInteractionResponse(_coerceMap(data)),
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

InteractionResultModel _parsePhysicalInteractionResponse(
  Map<String, dynamic> json,
) {
  final result = _extractInteractionResultPayload(json);
  if (result.isNotEmpty) {
    return InteractionResultModel.fromJson(result);
  }
  return InteractionResultModel.empty();
}

Map<String, dynamic> _extractInteractionResultPayload(
  Map<String, dynamic> json,
) {
  for (final key in const <String>[
    'result',
    'interaction_result',
    'interaction',
    'last_interaction_result',
    'data',
  ]) {
    final value = _coerceMap(json[key]);
    if (value.isEmpty) {
      continue;
    }
    if (key == 'data') {
      final nested = _extractInteractionResultPayload(value);
      if (nested.isNotEmpty) {
        return nested;
      }
    }
    if (_looksLikeInteractionResult(value)) {
      return value;
    }
  }
  return _looksLikeInteractionResult(json) ? json : <String, dynamic>{};
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

bool _looksLikeInteractionResult(Map<String, dynamic> json) {
  return json.containsKey('interaction_kind') ||
      json.containsKey('short_result') ||
      json.containsKey('display_text') ||
      json.containsKey('animation_hint');
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
