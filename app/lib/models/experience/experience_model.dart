class SceneModeModel {
  const SceneModeModel({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  factory SceneModeModel.fromJson(Map<String, dynamic> json) {
    final id = _cleanString(
      json['id'] ?? json['scene_mode'] ?? json['scene'] ?? json['value'],
    );
    return SceneModeModel(
      id: id ?? 'focus',
      label: _cleanString(json['label']) ?? _sceneLabel(id),
      description: _cleanString(json['description']) ?? _sceneDescription(id),
    );
  }

  static List<SceneModeModel> defaults() {
    return const <SceneModeModel>[
      SceneModeModel(
        id: 'focus',
        label: 'Focus',
        description: 'Shorter replies and fewer non-urgent interruptions.',
      ),
      SceneModeModel(
        id: 'offwork',
        label: 'Off Work',
        description: 'Warmer tone and lighter interaction rules.',
      ),
      SceneModeModel(
        id: 'meeting',
        label: 'Meeting',
        description: 'Keep responses brief and stay as silent as possible.',
      ),
    ];
  }

  static String _sceneLabel(String? id) {
    return switch (id) {
      'focus' => 'Focus',
      'offwork' => 'Off Work',
      'meeting' => 'Meeting',
      _ => _humanize(id ?? 'focus'),
    };
  }

  static String _sceneDescription(String? id) {
    return switch (id) {
      'focus' => 'Shorter replies and fewer non-urgent interruptions.',
      'offwork' => 'Warmer tone and lighter interaction rules.',
      'meeting' => 'Keep responses brief and stay as silent as possible.',
      _ => 'Custom runtime scene.',
    };
  }
}

class PersonaProfileModel {
  const PersonaProfileModel({
    required this.toneStyle,
    required this.replyLength,
    required this.proactivity,
    required this.voiceStyle,
    this.id,
    this.label,
  });

  final String toneStyle;
  final String replyLength;
  final String proactivity;
  final String voiceStyle;
  final String? id;
  final String? label;

  String get displayLabel {
    if (label != null && label!.trim().isNotEmpty) {
      return label!.trim();
    }
    if (id != null && id!.trim().isNotEmpty) {
      return _humanize(id!);
    }
    return '${_humanize(toneStyle)} · ${_humanize(replyLength)}';
  }

  String get summary =>
      '${_humanize(toneStyle)} tone · ${_humanize(replyLength)} replies · ${_humanize(proactivity)} proactivity · ${_humanize(voiceStyle)} voice';

  bool matches(PersonaProfileModel other) {
    return toneStyle == other.toneStyle &&
        replyLength == other.replyLength &&
        proactivity == other.proactivity &&
        voiceStyle == other.voiceStyle;
  }

  PersonaProfileModel copyWith({
    String? toneStyle,
    String? replyLength,
    String? proactivity,
    String? voiceStyle,
    Object? id = _unset,
    Object? label = _unset,
  }) {
    return PersonaProfileModel(
      toneStyle: toneStyle ?? this.toneStyle,
      replyLength: replyLength ?? this.replyLength,
      proactivity: proactivity ?? this.proactivity,
      voiceStyle: voiceStyle ?? this.voiceStyle,
      id: identical(id, _unset) ? this.id : id as String?,
      label: identical(label, _unset) ? this.label : label as String?,
    );
  }

  factory PersonaProfileModel.fromJson(dynamic value) {
    if (value is String) {
      return ExperienceCatalogModel.defaults()
              .personaForId(_normalizePersonaPresetId(value))
              ?.profile ??
          ExperienceCatalogModel.defaultProfile();
    }
    final json = _asMap(value);
    if (json.isEmpty) {
      return ExperienceCatalogModel.defaultProfile();
    }
    final profileId = _normalizePersonaPresetId(
      json['id'] ?? json['persona_profile_id'] ?? json['persona_profile'],
    );
    final preset = profileId == null
        ? null
        : ExperienceCatalogModel.defaults().personaForId(profileId);
    return PersonaProfileModel(
      id: profileId ?? preset?.id,
      label: _cleanString(json['label']) ?? preset?.label,
      toneStyle:
          _normalizePersonaFieldValue(
            'tone_style',
            json['tone_style'] ?? json['persona_tone_style'],
          ) ??
          preset?.profile.toneStyle ??
          ExperienceCatalogModel.defaultProfile().toneStyle,
      replyLength:
          _normalizePersonaFieldValue(
            'reply_length',
            json['reply_length'] ?? json['persona_reply_length'],
          ) ??
          preset?.profile.replyLength ??
          ExperienceCatalogModel.defaultProfile().replyLength,
      proactivity:
          _normalizePersonaFieldValue(
            'proactivity',
            json['proactivity'] ?? json['persona_proactivity'],
          ) ??
          preset?.profile.proactivity ??
          ExperienceCatalogModel.defaultProfile().proactivity,
      voiceStyle:
          _normalizePersonaFieldValue(
            'voice_style',
            json['voice_style'] ?? json['persona_voice_style'],
          ) ??
          preset?.profile.voiceStyle ??
          ExperienceCatalogModel.defaultProfile().voiceStyle,
    );
  }

  static const Object _unset = Object();
}

class PersonaPresetModel {
  const PersonaPresetModel({
    required this.id,
    required this.label,
    required this.profile,
    this.description,
  });

  final String id;
  final String label;
  final PersonaProfileModel profile;
  final String? description;

  factory PersonaPresetModel.fromJson(Map<String, dynamic> json) {
    final id =
        _normalizePersonaPresetId(
          json['id'] ?? json['persona_profile_id'] ?? json['preset'],
        ) ??
        'balanced';
    final profile = PersonaProfileModel.fromJson(
      json['profile'] is Map<String, dynamic> ? json['profile'] : json,
    ).copyWith(id: id, label: _cleanString(json['label']));
    return PersonaPresetModel(
      id: id,
      label: _cleanString(json['label']) ?? _humanize(id),
      description: _cleanString(json['description']),
      profile: profile,
    );
  }
}

class ExperienceCatalogModel {
  const ExperienceCatalogModel({
    required this.available,
    required this.scenes,
    required this.personaPresets,
    this.runtimePath,
    this.settingsPath,
    this.sessionPathTemplate,
  });

  final bool available;
  final List<SceneModeModel> scenes;
  final List<PersonaPresetModel> personaPresets;
  final String? runtimePath;
  final String? settingsPath;
  final String? sessionPathTemplate;

  SceneModeModel sceneForId(String? id) {
    if (id != null) {
      for (final item in scenes) {
        if (item.id == id) {
          return item;
        }
      }
    }
    return scenes.first;
  }

  PersonaPresetModel? personaForId(String? id) {
    final normalizedId = _normalizePersonaPresetId(id);
    if (normalizedId == null || normalizedId.isEmpty) {
      return null;
    }
    for (final item in personaPresets) {
      if (item.id == normalizedId) {
        return item;
      }
    }
    return null;
  }

  PersonaPresetModel? presetForProfile(PersonaProfileModel profile) {
    for (final item in personaPresets) {
      if (item.profile.matches(profile)) {
        return item;
      }
    }
    return null;
  }

  factory ExperienceCatalogModel.fromJson(Map<String, dynamic> json) {
    final sceneItems = _readList(json, const <String>[
      'scene_modes',
      'scenes',
      'scene_options',
    ]);
    final presetItems = _readList(json, const <String>[
      'persona_presets',
      'persona_profiles',
      'persona_options',
    ]);
    return ExperienceCatalogModel(
      available:
          _readBool(json, const <String>['available', 'enabled']) ||
          json.isNotEmpty,
      scenes: sceneItems.isEmpty
          ? ExperienceCatalogModel.defaults().scenes
          : sceneItems
                .map((dynamic item) => SceneModeModel.fromJson(_asMap(item)))
                .toList(),
      personaPresets: presetItems.isEmpty
          ? ExperienceCatalogModel.defaults().personaPresets
          : presetItems
                .map(
                  (dynamic item) => PersonaPresetModel.fromJson(_asMap(item)),
                )
                .toList(),
      runtimePath: _cleanString(json['runtime_path']),
      settingsPath: _cleanString(json['settings_path']),
      sessionPathTemplate: _cleanString(
        json['session_path_template'] ?? json['session_patch_path'],
      ),
    );
  }

  factory ExperienceCatalogModel.defaults() {
    const balanced = PersonaPresetModel(
      id: 'balanced',
      label: 'Balanced',
      description: 'Default operator tone.',
      profile: PersonaProfileModel(
        id: 'balanced',
        label: 'Balanced',
        toneStyle: 'clear',
        replyLength: 'medium',
        proactivity: 'balanced',
        voiceStyle: 'calm',
      ),
    );
    const focusBrief = PersonaPresetModel(
      id: 'focus_brief',
      label: 'Focus Brief',
      description: 'Short, calm, low-interruption replies.',
      profile: PersonaProfileModel(
        id: 'focus_brief',
        label: 'Focus Brief',
        toneStyle: 'concise',
        replyLength: 'short',
        proactivity: 'low',
        voiceStyle: 'quiet',
      ),
    );
    const companionWarm = PersonaPresetModel(
      id: 'companion_warm',
      label: 'Companion Warm',
      description: 'Warmer and more companion-like.',
      profile: PersonaProfileModel(
        id: 'companion_warm',
        label: 'Companion Warm',
        toneStyle: 'warm',
        replyLength: 'expanded',
        proactivity: 'high',
        voiceStyle: 'bright',
      ),
    );
    const meetingBrief = PersonaPresetModel(
      id: 'meeting_brief',
      label: 'Meeting Brief',
      description: 'Formal and very short for meeting-safe replies.',
      profile: PersonaProfileModel(
        id: 'meeting_brief',
        label: 'Meeting Brief',
        toneStyle: 'formal',
        replyLength: 'short',
        proactivity: 'low',
        voiceStyle: 'quiet',
      ),
    );

    return ExperienceCatalogModel(
      available: false,
      scenes: SceneModeModel.defaults(),
      personaPresets: const <PersonaPresetModel>[
        balanced,
        focusBrief,
        companionWarm,
        meetingBrief,
      ],
    );
  }

  static PersonaProfileModel defaultProfile() {
    return ExperienceCatalogModel.defaults().personaPresets.first.profile;
  }
}

class ExperienceSettingsModel {
  const ExperienceSettingsModel({
    required this.defaultSceneMode,
    required this.persona,
    required this.physicalInteractionEnabled,
    required this.shakeEnabled,
    required this.tapConfirmationEnabled,
  });

  final String defaultSceneMode;
  final PersonaProfileModel persona;
  final bool physicalInteractionEnabled;
  final bool shakeEnabled;
  final bool tapConfirmationEnabled;

  factory ExperienceSettingsModel.fromJson(Map<String, dynamic> json) {
    return ExperienceSettingsModel(
      defaultSceneMode:
          _cleanString(json['default_scene_mode']) ??
          ExperienceCatalogModel.defaults().scenes.first.id,
      persona: PersonaProfileModel.fromJson(json),
      physicalInteractionEnabled: _readBool(json, const <String>[
        'physical_interaction_enabled',
      ]),
      shakeEnabled: _readBool(json, const <String>['shake_enabled']),
      tapConfirmationEnabled: _readBool(json, const <String>[
        'tap_confirmation_enabled',
      ]),
    );
  }

  factory ExperienceSettingsModel.defaults() {
    return ExperienceSettingsModel(
      defaultSceneMode: ExperienceCatalogModel.defaults().scenes.first.id,
      persona: ExperienceCatalogModel.defaultProfile(),
      physicalInteractionEnabled: true,
      shakeEnabled: true,
      tapConfirmationEnabled: true,
    );
  }
}

class SessionExperienceOverrideModel {
  const SessionExperienceOverrideModel({
    this.sceneMode,
    this.personaProfileId,
    this.persona,
    this.source = 'session_override',
    this.updatedAt,
  });

  final String? sceneMode;
  final String? personaProfileId;
  final PersonaProfileModel? persona;
  final String source;
  final String? updatedAt;

  bool get hasOverrides =>
      (sceneMode?.isNotEmpty ?? false) ||
      (personaProfileId?.isNotEmpty ?? false) ||
      persona != null;

  SessionExperienceOverrideModel copyWith({
    Object? sceneMode = _unset,
    Object? personaProfileId = _unset,
    Object? persona = _unset,
    String? source,
    Object? updatedAt = _unset,
  }) {
    return SessionExperienceOverrideModel(
      sceneMode: identical(sceneMode, _unset)
          ? this.sceneMode
          : sceneMode as String?,
      personaProfileId: identical(personaProfileId, _unset)
          ? this.personaProfileId
          : personaProfileId as String?,
      persona: identical(persona, _unset)
          ? this.persona
          : persona as PersonaProfileModel?,
      source: source ?? this.source,
      updatedAt: identical(updatedAt, _unset)
          ? this.updatedAt
          : updatedAt as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    if (sceneMode != null && sceneMode!.isNotEmpty) {
      data['scene_mode'] = sceneMode;
    }
    if (personaProfileId != null && personaProfileId!.isNotEmpty) {
      data['persona_profile'] = personaProfileId;
      data['persona_profile_id'] = personaProfileId;
    }
    if (persona != null &&
        (personaProfileId == null || personaProfileId!.isEmpty)) {
      data['persona_fields'] = <String, dynamic>{
        'tone_style': persona!.toneStyle,
        'reply_length': persona!.replyLength,
        'proactivity': persona!.proactivity,
        'voice_style': persona!.voiceStyle,
      };
    }
    return data;
  }

  factory SessionExperienceOverrideModel.fromJson(Map<String, dynamic> json) {
    final personaProfile = _asMap(json['persona_profile']);
    final personaFields = _asMap(json['persona_fields']);
    final personaProfileId = _extractPersonaProfileId(
      json['persona_profile_id'],
      json['persona_profile'],
    );
    final personaPayload = personaFields.isNotEmpty
        ? personaFields
        : (personaProfile.isNotEmpty
              ? personaProfile
              : _asMap(json['persona']));
    final persona = personaPayload.isNotEmpty
        ? PersonaProfileModel.fromJson(
            personaPayload,
          ).copyWith(id: personaProfileId)
        : (personaProfileId == null
              ? null
              : ExperienceCatalogModel.defaults()
                    .personaForId(personaProfileId)
                    ?.profile);

    return SessionExperienceOverrideModel(
      sceneMode: _cleanString(json['scene_mode']),
      personaProfileId: personaProfileId,
      persona: persona,
      source:
          _cleanString(json['source'] ?? json['override_source']) ??
          'session_override',
      updatedAt: _cleanString(json['updated_at']),
    );
  }

  static const Object _unset = Object();
}

class PhysicalInteractionHistoryEntryModel {
  const PhysicalInteractionHistoryEntryModel({
    required this.title,
    required this.summary,
    this.interactionKind,
    this.mode,
    this.createdAt,
    this.status,
  });

  final String title;
  final String summary;
  final String? interactionKind;
  final String? mode;
  final String? createdAt;
  final String? status;

  factory PhysicalInteractionHistoryEntryModel.fromJson(dynamic value) {
    if (value is String) {
      final summary = value.trim();
      return PhysicalInteractionHistoryEntryModel(
        title: summary,
        summary: summary,
      );
    }
    final json = _asMap(value);
    return PhysicalInteractionHistoryEntryModel(
      title:
          _cleanString(json['title']) ??
          _cleanString(json['short_result']) ??
          _cleanString(json['interaction_kind']) ??
          'Interaction',
      summary:
          _cleanString(
            json['summary'] ?? json['display_text'] ?? json['message'],
          ) ??
          'No detail recorded.',
      interactionKind: _cleanString(json['interaction_kind']),
      mode: _cleanString(json['mode']),
      createdAt: _cleanString(
        json['created_at'] ?? json['ts'] ?? json['occurred_at'],
      ),
      status: _cleanString(json['status']),
    );
  }
}

class InteractionResultModel {
  const InteractionResultModel({
    required this.interactionKind,
    required this.mode,
    required this.title,
    required this.shortResult,
    this.displayText,
    this.voiceText,
    this.animationHint,
    this.ledHint,
    this.historyEntry,
    this.createdAt,
    this.raw = const <String, dynamic>{},
  });

  final String interactionKind;
  final String mode;
  final String title;
  final String shortResult;
  final String? displayText;
  final String? voiceText;
  final String? animationHint;
  final String? ledHint;
  final PhysicalInteractionHistoryEntryModel? historyEntry;
  final String? createdAt;
  final Map<String, dynamic> raw;

  bool get hasContent =>
      interactionKind.isNotEmpty ||
      title.isNotEmpty ||
      shortResult.isNotEmpty ||
      (displayText?.isNotEmpty ?? false);

  factory InteractionResultModel.fromJson(Map<String, dynamic> json) {
    return InteractionResultModel(
      interactionKind: _cleanString(json['interaction_kind']) ?? '',
      mode: _cleanString(json['mode']) ?? '',
      title: _cleanString(json['title']) ?? '',
      shortResult:
          _cleanString(
            json['short_result'] ?? json['result'] ?? json['title'],
          ) ??
          '',
      displayText: _cleanString(json['display_text']),
      voiceText: _cleanString(json['voice_text']),
      animationHint: _cleanString(json['animation_hint']),
      ledHint: _cleanString(json['led_hint']),
      historyEntry: json['history_entry'] == null
          ? null
          : PhysicalInteractionHistoryEntryModel.fromJson(
              json['history_entry'],
            ),
      createdAt: _cleanString(
        json['created_at'] ?? json['ts'] ?? json['occurred_at'],
      ),
      raw: Map<String, dynamic>.from(json),
    );
  }

  factory InteractionResultModel.empty() {
    return const InteractionResultModel(
      interactionKind: '',
      mode: '',
      title: '',
      shortResult: '',
    );
  }
}

class PhysicalInteractionStateModel {
  const PhysicalInteractionStateModel({
    required this.enabled,
    required this.shakeEnabled,
    required this.tapConfirmationEnabled,
    required this.holdToTalkAvailable,
    required this.ready,
    required this.status,
    this.statusMessage,
    this.blockedReason,
    this.awaitingConfirmation = false,
    this.latestInteractionAt,
    this.history = const <PhysicalInteractionHistoryEntryModel>[],
    this.debug = const <String, dynamic>{},
  });

  final bool enabled;
  final bool shakeEnabled;
  final bool tapConfirmationEnabled;
  final bool holdToTalkAvailable;
  final bool ready;
  final String status;
  final String? statusMessage;
  final String? blockedReason;
  final bool awaitingConfirmation;
  final String? latestInteractionAt;
  final List<PhysicalInteractionHistoryEntryModel> history;
  final Map<String, dynamic> debug;

  String get readinessLabel {
    if (!enabled) {
      return 'Disabled';
    }
    if (ready) {
      return 'Ready';
    }
    if (blockedReason != null && blockedReason!.isNotEmpty) {
      return _humanize(blockedReason!);
    }
    if (status.isNotEmpty) {
      return _humanize(status);
    }
    return 'Partial';
  }

  factory PhysicalInteractionStateModel.fromJson(Map<String, dynamic> json) {
    final historyItems = _readList(json, const <String>[
      'history',
      'entries',
      'recent_results',
      'events',
    ]);
    return PhysicalInteractionStateModel(
      enabled: _readBool(json, const <String>[
        'enabled',
        'physical_interaction_enabled',
      ]),
      shakeEnabled: _readBool(json, const <String>[
        'shake_enabled',
        'shake_available',
      ]),
      tapConfirmationEnabled: _readBool(json, const <String>[
        'tap_confirmation_enabled',
        'tap_enabled',
        'tap_confirmation_available',
      ]),
      holdToTalkAvailable: _readBool(json, const <String>[
        'hold_to_talk_available',
        'hold_enabled',
      ]),
      ready:
          _readBool(json, const <String>['ready']) ||
          ((_cleanString(json['status']) ?? '') == 'ready'),
      status: _cleanString(json['status'] ?? json['state']) ?? 'unknown',
      statusMessage: _cleanString(
        json['status_message'] ?? json['message'] ?? json['note'],
      ),
      blockedReason: _cleanString(json['blocked_reason'] ?? json['reason']),
      awaitingConfirmation: _readBool(json, const <String>[
        'awaiting_confirmation',
        'pending_confirmation',
      ]),
      latestInteractionAt: _cleanString(
        json['latest_interaction_at'] ?? json['updated_at'],
      ),
      history: historyItems
          .map(PhysicalInteractionHistoryEntryModel.fromJson)
          .toList(),
      debug: _asMap(json['debug']),
    );
  }

  factory PhysicalInteractionStateModel.empty({
    bool enabled = false,
    bool shakeEnabled = false,
    bool tapConfirmationEnabled = false,
  }) {
    return PhysicalInteractionStateModel(
      enabled: enabled,
      shakeEnabled: shakeEnabled,
      tapConfirmationEnabled: tapConfirmationEnabled,
      holdToTalkAvailable: true,
      ready: false,
      status: enabled ? 'waiting' : 'disabled',
    );
  }
}

class ExperienceRuntimeModel {
  const ExperienceRuntimeModel({
    required this.reportedByBackend,
    required this.activeSceneMode,
    required this.activePersona,
    required this.overrideSource,
    required this.physicalInteraction,
    required this.lastInteractionResult,
  });

  final bool reportedByBackend;
  final String activeSceneMode;
  final PersonaProfileModel activePersona;
  final String overrideSource;
  final PhysicalInteractionStateModel physicalInteraction;
  final InteractionResultModel lastInteractionResult;

  factory ExperienceRuntimeModel.fromJson(Map<String, dynamic> json) {
    final personaPayload = _firstMap(json, const <String>[
      'active_persona',
      'persona',
      'persona_fields',
    ]);
    final personaProfileId = _extractPersonaProfileId(
      json['active_persona_profile_id'],
      json['persona_profile_id'],
      json['persona_profile'],
      personaPayload['preset'],
      personaPayload['id'],
    );
    final persona = personaPayload.isNotEmpty
        ? PersonaProfileModel.fromJson(
            personaPayload,
          ).copyWith(id: personaProfileId)
        : PersonaProfileModel.fromJson(
            personaProfileId ??
                _cleanString(json['active_persona'] ?? json['persona_profile']),
          );
    final physicalPayload = _firstMap(json, const <String>[
      'physical_interaction',
      'interaction',
      'physical',
    ]);
    final interactionPayload = _firstMap(json, const <String>[
      'last_interaction_result',
      'interaction_result',
      'last_result',
    ]);

    return ExperienceRuntimeModel(
      reportedByBackend: json.isNotEmpty,
      activeSceneMode:
          _cleanString(json['active_scene_mode'] ?? json['scene_mode']) ??
          ExperienceCatalogModel.defaults().scenes.first.id,
      activePersona: persona,
      overrideSource:
          _cleanString(json['override_source'] ?? json['source']) ?? 'default',
      physicalInteraction: physicalPayload.isEmpty
          ? PhysicalInteractionStateModel.empty(
              enabled: _readBool(json, const <String>[
                'physical_interaction_enabled',
              ]),
              shakeEnabled: _readBool(json, const <String>['shake_enabled']),
              tapConfirmationEnabled: _readBool(json, const <String>[
                'tap_confirmation_enabled',
              ]),
            )
          : PhysicalInteractionStateModel.fromJson(physicalPayload),
      lastInteractionResult: interactionPayload.isEmpty
          ? InteractionResultModel.empty()
          : InteractionResultModel.fromJson(interactionPayload),
    );
  }

  factory ExperienceRuntimeModel.empty() {
    return ExperienceRuntimeModel(
      reportedByBackend: false,
      activeSceneMode: ExperienceCatalogModel.defaults().scenes.first.id,
      activePersona: ExperienceCatalogModel.defaultProfile(),
      overrideSource: 'default',
      physicalInteraction: PhysicalInteractionStateModel.empty(),
      lastInteractionResult: InteractionResultModel.empty(),
    );
  }
}

class ExperienceSurfaceModel {
  const ExperienceSurfaceModel({
    required this.scene,
    required this.persona,
    required this.personaPreset,
    required this.overrideSource,
    required this.physicalInteraction,
    required this.lastInteractionResult,
  });

  final SceneModeModel scene;
  final PersonaProfileModel persona;
  final PersonaPresetModel? personaPreset;
  final String overrideSource;
  final PhysicalInteractionStateModel physicalInteraction;
  final InteractionResultModel lastInteractionResult;

  String get sceneLabel => scene.label;
  String get personaLabel => personaPreset?.label ?? persona.displayLabel;

  String get summary =>
      '$sceneLabel · $personaLabel · ${physicalInteraction.readinessLabel}';

  factory ExperienceSurfaceModel.resolve({
    required ExperienceCatalogModel catalog,
    required ExperienceSettingsModel defaults,
    required ExperienceRuntimeModel runtime,
    SessionExperienceOverrideModel? sessionOverride,
  }) {
    final effectiveSceneId =
        sessionOverride?.sceneMode ??
        runtime.activeSceneMode.takeIfNotEmpty ??
        defaults.defaultSceneMode;
    final effectivePersona =
        sessionOverride?.persona ??
        (sessionOverride?.personaProfileId != null
            ? catalog.personaForId(sessionOverride!.personaProfileId)?.profile
            : null) ??
        runtime.activePersona.takeIfComplete ??
        defaults.persona;
    final effectivePreset = sessionOverride?.personaProfileId != null
        ? catalog.personaForId(sessionOverride!.personaProfileId)
        : catalog.presetForProfile(effectivePersona);
    final source = sessionOverride?.hasOverrides == true
        ? sessionOverride!.source
        : runtime.overrideSource;

    return ExperienceSurfaceModel(
      scene: catalog.sceneForId(effectiveSceneId),
      persona: effectivePersona,
      personaPreset: effectivePreset,
      overrideSource: source.isEmpty ? 'default' : source,
      physicalInteraction: runtime.physicalInteraction,
      lastInteractionResult: runtime.lastInteractionResult,
    );
  }
}

extension on String {
  String? get takeIfNotEmpty => trim().isEmpty ? null : trim();
}

extension on PersonaProfileModel {
  PersonaProfileModel? get takeIfComplete {
    return toneStyle.trim().isEmpty ||
            replyLength.trim().isEmpty ||
            proactivity.trim().isEmpty ||
            voiceStyle.trim().isEmpty
        ? null
        : this;
  }
}

Map<String, dynamic> _asMap(dynamic value) {
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

String? _cleanString(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String? _normalizePersonaPresetId(dynamic value) {
  final cleaned = _cleanString(value)?.toLowerCase().replaceAll(' ', '_');
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  return switch (cleaned) {
    'warm' => 'companion_warm',
    'concise' => 'focus_brief',
    'meeting' => 'meeting_brief',
    _ => cleaned,
  };
}

String? _extractPersonaProfileId(
  dynamic value, [
  dynamic value2,
  dynamic value3,
  dynamic value4,
  dynamic value5,
]) {
  for (final candidate in <dynamic>[value, value2, value3, value4, value5]) {
    final mapped = _asMap(candidate);
    if (mapped.isNotEmpty) {
      final nested = _extractPersonaProfileId(
        mapped['persona_profile_id'],
        mapped['preset'],
        mapped['id'],
      );
      if (nested != null) {
        return nested;
      }
      continue;
    }
    final normalized = _normalizePersonaPresetId(candidate);
    if (normalized != null) {
      return normalized;
    }
  }
  return null;
}

String? _normalizePersonaFieldValue(String key, dynamic value) {
  final cleaned = _cleanString(value)?.toLowerCase().replaceAll(' ', '_');
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  const aliases = <String, Map<String, String>>{
    'tone_style': <String, String>{
      'balanced': 'clear',
      'neutral': 'clear',
      'direct': 'concise',
    },
    'reply_length': <String, String>{'balanced': 'medium', 'long': 'expanded'},
    'proactivity': <String, String>{'medium': 'balanced'},
    'voice_style': <String, String>{
      'natural': 'calm',
      'soft': 'bright',
      'steady': 'calm',
      'discreet': 'quiet',
      'whisper': 'quiet',
      'playful': 'bright',
    },
  };
  const allowed = <String, Set<String>>{
    'tone_style': <String>{'clear', 'warm', 'concise', 'formal'},
    'reply_length': <String>{'short', 'medium', 'expanded'},
    'proactivity': <String>{'low', 'balanced', 'high'},
    'voice_style': <String>{'calm', 'bright', 'quiet'},
  };
  final normalized = aliases[key]?[cleaned] ?? cleaned;
  final supported = allowed[key];
  if (supported == null || supported.contains(normalized)) {
    return normalized;
  }
  return null;
}

bool _readBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    final text = _cleanString(value)?.toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes' || text == 'enabled') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'disabled') {
      return false;
    }
  }
  return false;
}

List<dynamic> _readList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value;
    }
  }
  return const <dynamic>[];
}

Map<String, dynamic> _firstMap(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final candidate = _asMap(json[key]);
    if (candidate.isNotEmpty) {
      return candidate;
    }
  }
  return <String, dynamic>{};
}

String _humanize(String value) {
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((String item) => item.isNotEmpty)
      .map(
        (String item) =>
            '${item.substring(0, 1).toUpperCase()}${item.substring(1).toLowerCase()}',
      )
      .join(' ');
}
