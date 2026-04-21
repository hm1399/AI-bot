import 'package:ai_bot_app/models/planning/planning_editor_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validatePlanningEventWindow', () {
    test('rejects invalid start time', () {
      expect(
        validatePlanningEventWindow(startAt: '1', endAt: '2026-04-10T10:00:00'),
        'Event start time must be a valid date and time.',
      );
    });

    test('rejects invalid end time', () {
      expect(
        validatePlanningEventWindow(startAt: '2026-04-10T09:00:00', endAt: '2'),
        'Event end time must be a valid date and time.',
      );
    });

    test('rejects windows that do not move forward in time', () {
      expect(
        validatePlanningEventWindow(
          startAt: '2026-04-10T10:00:00',
          endAt: '2026-04-10T09:00:00',
        ),
        'Event end time must be later than the start time.',
      );
    });

    test('accepts a valid event window', () {
      expect(
        validatePlanningEventWindow(
          startAt: '2026-04-10T09:00:00',
          endAt: '2026-04-10T10:00:00',
        ),
        isNull,
      );
    });
  });
}
