import 'package:ai_bot_app/models/chat/session_model.dart';
import 'package:ai_bot_app/models/experience/experience_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime parser reads shake mode and top-level daily shake state', () {
    final runtime = ExperienceRuntimeModel.fromJson(<String, dynamic>{
      'physical_interaction': <String, dynamic>{
        'enabled': true,
        'shake_enabled': true,
        'tap_confirmation_enabled': true,
        'hold_to_talk_available': true,
        'ready': true,
        'status': 'ready',
        'shake_mode': 'fortune',
      },
      'daily_shake_state': <String, dynamic>{
        'date': '2026-04-14',
        'valid_shake_count': 2,
        'first_result_mode': 'fortune',
        'last_mode': 'random',
        'last_valid_shake_at': '2026-04-14T10:30:00+08:00',
      },
    });

    expect(runtime.physicalInteraction.shakeMode, 'fortune');
    expect(runtime.physicalInteraction.dailyShakeDate, '2026-04-14');
    expect(runtime.physicalInteraction.dailyShakeCount, 2);
    expect(runtime.physicalInteraction.dailyShakeFirstResultMode, 'fortune');
    expect(runtime.physicalInteraction.dailyShakeLastMode, 'random');
    expect(
      runtime.physicalInteraction.dailyShakeLastInteractionAt,
      contains('2026-04-14T10:30:00'),
    );
    expect(runtime.physicalInteraction.firstShakeUsedToday, isTrue);
    expect(runtime.physicalInteraction.recentShakeMode, 'random');
  });

  test(
    'session override parser preserves persona preset id from object payload',
    () {
      final override = SessionExperienceOverrideModel.fromJson(
        <String, dynamic>{
          'scene_mode': 'meeting',
          'persona_profile': <String, dynamic>{
            'preset': 'meeting_brief',
            'tone_style': 'formal',
            'reply_length': 'short',
            'proactivity': 'low',
            'voice_style': 'quiet',
          },
        },
      );

      expect(override.sceneMode, 'meeting');
      expect(override.personaProfileId, 'meeting_brief');
      expect(override.persona?.voiceStyle, 'quiet');
      expect(override.toJson()['persona_profile'], 'meeting_brief');
      expect(override.toJson().containsKey('persona_fields'), isFalse);
    },
  );

  test('session model captures embedded experience override payload', () {
    final session = SessionModel.fromJson(<String, dynamic>{
      'session_id': 'app:main',
      'channel': 'app',
      'title': 'Main',
      'summary': '',
      'message_count': 0,
      'pinned': false,
      'archived': false,
      'active': true,
      'scene_mode': 'offwork',
      'persona_profile': <String, dynamic>{
        'preset': 'companion_warm',
        'tone_style': 'warm',
        'reply_length': 'medium',
        'proactivity': 'high',
        'voice_style': 'bright',
      },
    });

    expect(session.experienceOverride.hasOverrides, isTrue);
    expect(session.experienceOverride.sceneMode, 'offwork');
    expect(session.experienceOverride.personaProfileId, 'companion_warm');
    expect(session.experienceOverride.persona?.toneStyle, 'warm');
  });
}
