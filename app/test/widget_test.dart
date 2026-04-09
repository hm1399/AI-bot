import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:ai_bot_app/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiBotApp()));
    await tester.pumpAndSettle();

    expect(find.text('AI Bot Workspace'), findsOneWidget);
    expect(find.text('Connect the operator console.'), findsOneWidget);
    expect(find.text('Try Demo Mode'), findsOneWidget);
    expect(find.text('Validate Connection'), findsOneWidget);
  });
}
