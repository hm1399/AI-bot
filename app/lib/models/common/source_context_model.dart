class SourceContextModel {
  const SourceContextModel({
    required this.label,
    required this.sourceChannel,
    required this.interactionSurface,
    required this.captureSource,
    required this.createdVia,
    required this.sceneMode,
    required this.personaProfileId,
    required this.personaVoiceStyle,
    required this.interactionKind,
    required this.interactionMode,
    required this.approvalSource,
  });

  final String label;
  final String? sourceChannel;
  final String? interactionSurface;
  final String? captureSource;
  final String? createdVia;
  final String? sceneMode;
  final String? personaProfileId;
  final String? personaVoiceStyle;
  final String? interactionKind;
  final String? interactionMode;
  final String? approvalSource;

  bool get hasLabel => label.isNotEmpty;

  bool get hasExperienceMetadata =>
      sceneMode != null ||
      personaProfileId != null ||
      personaVoiceStyle != null ||
      interactionKind != null ||
      interactionMode != null;

  factory SourceContextModel.fromMetadata({
    String? sourceChannel,
    String? interactionSurface,
    String? captureSource,
    String? createdVia,
    String? sceneMode,
    String? personaProfileId,
    String? personaVoiceStyle,
    String? interactionKind,
    String? interactionMode,
    String? approvalSource,
  }) {
    final normalizedChannel = _normalize(sourceChannel);
    final normalizedSurface = _normalize(interactionSurface);
    final normalizedCapture = _normalize(captureSource);
    final normalizedCreatedVia = _normalize(createdVia);
    final normalizedSceneMode = _normalize(sceneMode);
    final normalizedPersonaProfileId = _normalize(personaProfileId);
    final normalizedPersonaVoiceStyle = _normalize(personaVoiceStyle);
    final normalizedInteractionKind = _normalize(interactionKind);
    final normalizedInteractionMode = _normalize(interactionMode);
    final normalizedApprovalSource = _normalize(approvalSource);

    return SourceContextModel(
      label: _deriveLabel(
        sourceChannel: normalizedChannel,
        interactionSurface: normalizedSurface,
        captureSource: normalizedCapture,
        createdVia: normalizedCreatedVia,
      ),
      sourceChannel: normalizedChannel,
      interactionSurface: normalizedSurface,
      captureSource: normalizedCapture,
      createdVia: normalizedCreatedVia,
      sceneMode: normalizedSceneMode,
      personaProfileId: normalizedPersonaProfileId,
      personaVoiceStyle: normalizedPersonaVoiceStyle,
      interactionKind: normalizedInteractionKind,
      interactionMode: normalizedInteractionMode,
      approvalSource: normalizedApprovalSource,
    );
  }

  static String _deriveLabel({
    String? sourceChannel,
    String? interactionSurface,
    String? captureSource,
    String? createdVia,
  }) {
    if (interactionSurface == 'device_press') {
      if (captureSource == 'device_mic') {
        return 'Device direct voice';
      }
      return 'Device press-to-talk';
    }
    if (sourceChannel == 'app') {
      return 'App text';
    }
    if (sourceChannel == 'desktop_voice') {
      return 'Direct voice';
    }
    if (sourceChannel == 'device') {
      if (captureSource == 'device_mic') {
        return 'Device direct voice';
      }
      return 'Device';
    }
    switch (sourceChannel) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'telegram':
        return 'Telegram';
      case 'slack':
        return 'Slack';
      case 'discord':
        return 'Discord';
    }
    if (sourceChannel != null &&
        sourceChannel.isNotEmpty &&
        !<String>{'app', 'device', 'desktop_voice'}.contains(sourceChannel)) {
      return _humanizeSourceChannel(sourceChannel);
    }
    if (<String>{
      'app_manual',
      'manual',
      'chat',
      'app_text',
    }.contains(createdVia)) {
      return 'App text';
    }
    if (createdVia == 'voice') {
      return 'Direct voice';
    }
    return '';
  }

  static String? _normalize(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }
    return cleaned;
  }

  static String _humanizeSourceChannel(String value) {
    return value
        .split(RegExp(r'[_\-]+'))
        .where((String part) => part.isNotEmpty)
        .map(
          (String part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
