import 'package:ai_bot_app/models/chat/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planning metadata maps delete_event to a readable action label', () {
    final message = MessageModel.fromJson(<String, dynamic>{
      'message_id': 'msg_delete_event',
      'session_id': 'app:main',
      'role': 'assistant',
      'content': '好的，取消了18号考试行程。',
      'metadata': <String, dynamic>{
        'tool_results': <String, dynamic>{
          'planning': <Map<String, dynamic>>[
            <String, dynamic>{
              'action': 'delete_event',
              'resource_ids': <String, dynamic>{'event_id': 'event_exam'},
            },
          ],
        },
      },
    });

    expect(message.planningMetadata.actionLabel, 'Deleted event');
    expect(message.planningMetadata.eventCount, 1);
  });

  test('planning metadata maps delete_reminder to a readable action label', () {
    final message = MessageModel.fromJson(<String, dynamic>{
      'message_id': 'msg_delete_reminder',
      'session_id': 'app:main',
      'role': 'assistant',
      'content': '好的，这条提醒已经取消。',
      'metadata': <String, dynamic>{
        'tool_results': <String, dynamic>{
          'planning': <Map<String, dynamic>>[
            <String, dynamic>{
              'action': 'delete_reminder',
              'resource_ids': <String, dynamic>{'reminder_id': 'rem_exam'},
            },
          ],
        },
      },
    });

    expect(message.planningMetadata.actionLabel, 'Deleted reminder');
    expect(message.planningMetadata.reminderCount, 1);
  });
}
