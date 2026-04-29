import 'package:ai_bot_app/models/chat/message_model.dart';
import 'package:ai_bot_app/widgets/chat/conversation_message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<MessageModel> buildMessages(String sessionId, String prefix) {
    return List<MessageModel>.generate(30, (int index) {
      return MessageModel(
        id: '$sessionId-$index',
        sessionId: sessionId,
        role: index.isEven ? 'assistant' : 'user',
        text: '$prefix message $index\n${'detail ' * 12}',
        status: 'completed',
        createdAt: DateTime(2026, 4, 22, 10, index % 60).toIso8601String(),
      );
    });
  }

  Future<void> pumpList(
    WidgetTester tester, {
    required String sessionId,
    required List<MessageModel> messages,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: ConversationMessageList(
              sessionId: sessionId,
              messages: messages,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
  }

  testWidgets('defaults to the latest message on initial load', (
    WidgetTester tester,
  ) async {
    await pumpList(
      tester,
      sessionId: 'app:main',
      messages: buildMessages('app:main', 'Current'),
    );

    expect(find.textContaining('Current message 29'), findsOneWidget);
    expect(find.textContaining('Current message 0'), findsNothing);
  });

  testWidgets('switching sessions resets the list to the newest message', (
    WidgetTester tester,
  ) async {
    await pumpList(
      tester,
      sessionId: 'app:main',
      messages: buildMessages('app:main', 'Current'),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current message 29'), findsNothing);

    await pumpList(
      tester,
      sessionId: 'app:other',
      messages: buildMessages('app:other', 'Other'),
    );

    expect(find.textContaining('Other message 29'), findsOneWidget);
    expect(find.textContaining('Other message 0'), findsNothing);
  });
}
