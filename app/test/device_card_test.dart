import 'package:ai_bot_app/models/home/runtime_state_model.dart';
import 'package:ai_bot_app/widgets/home/device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DeviceStatusModel buildStatus() {
    return DeviceStatusModel.fromJson(<String, dynamic>{
      'connected': true,
      'state': 'IDLE',
      'battery': -1,
      'wifi_rssi': -44,
      'charging': false,
      'reconnect_count': 2,
      'last_seen_at': '2026-04-10T19:36:19+08:00',
      'controls': <String, dynamic>{
        'volume': 35,
        'muted': false,
        'sleeping': false,
        'led_enabled': true,
        'led_brightness': 50,
        'led_color': '#2563eb',
      },
      'status_bar': <String, dynamic>{
        'time': '19:36',
        'weather': '25°C',
        'weather_status': 'ready',
        'updated_at': '2026-04-10T19:36:19+08:00',
        'weather_meta': <String, dynamic>{
          'provider': 'open-meteo-fallback',
          'city': 'Hong Kong',
          'source': 'computer_fetch',
          'fetched_at': '2026-04-10T19:30:30+08:00',
        },
      },
      'last_command': <String, dynamic>{
        'command': 'toggle_led',
        'status': 'failed',
        'ok': false,
        'error': 'hardware_unavailable',
        'updated_at': '2026-04-10T19:32:50+08:00',
      },
    });
  }

  Future<void> pumpCard(WidgetTester tester, DeviceStatusModel status) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DeviceCard(status: status)),
        ),
      ),
    );
  }

  Size chipSizeForLabel(WidgetTester tester, String label) {
    final textElement = tester.element(find.text(label));
    Element? chipElement;
    textElement.visitAncestorElements((Element element) {
      if (element.widget is Container) {
        chipElement = element;
        return false;
      }
      return true;
    });
    expect(chipElement, isNotNull, reason: 'Missing chip for $label');
    return (chipElement!.renderObject! as RenderBox).size;
  }

  testWidgets(
    'device card shows snapshot freshness and computer weather source',
    (WidgetTester tester) async {
      await pumpCard(tester, buildStatus());

      expect(find.text('Unknown'), findsWidgets);
      expect(find.textContaining('-44 dBm'), findsOneWidget);
      expect(find.text('19:36:19'), findsWidgets);
      expect(find.text('Computer · Open-Meteo'), findsOneWidget);
      expect(find.text('toggle_led · failed'), findsOneWidget);
    },
  );

  testWidgets('device card metric chips keep a consistent height', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, buildStatus());

    final stateChipSize = chipSizeForLabel(tester, 'State');
    final weatherChipSize = chipSizeForLabel(tester, 'Weather');
    final commandChipSize = chipSizeForLabel(tester, 'Last Command');

    expect(stateChipSize.height, weatherChipSize.height);
    expect(stateChipSize.height, commandChipSize.height);
  });
}
