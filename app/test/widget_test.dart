import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:ai_bot_app/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AiBotApp()));
    await tester.pumpAndSettle();

    expect(find.text('Connect to AI-Bot'), findsOneWidget);
  });
}
