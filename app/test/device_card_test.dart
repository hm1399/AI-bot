import 'package:ai_bot_app/models/home/runtime_state_model.dart';
import 'package:ai_bot_app/widgets/home/device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DeviceStatusModel buildNotWiredStatus() {
    return DeviceStatusModel.fromJson(<String, dynamic>{
      'connected': true,
      'state': 'IDLE',
      'battery': -1,
      'battery_capability': false,
      'battery_validity': 'unavailable',
      'wifi_rssi': -44,
      'charging': false,
      'charging_capability': false,
      'charging_validity': 'unavailable',
      'reconnect_count': 2,
      'last_seen_at': '2026-04-10T19:36:19+08:00',
      'display_capabilities': <String, dynamic>{
        'status_bar_available': false,
        'weather_available': true,
        'battery_available': false,
        'charging_available': false,
      },
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

  DeviceStatusModel buildUnknownTelemetryStatus() {
    return DeviceStatusModel.fromJson(<String, dynamic>{
      'connected': true,
      'state': 'IDLE',
      'battery': -1,
      'battery_capability': true,
      'battery_validity': 'unavailable',
      'wifi_rssi': -44,
      'charging': false,
      'charging_capability': true,
      'charging_validity': 'unavailable',
      'reconnect_count': 2,
      'last_seen_at': '2026-04-10T19:36:19+08:00',
      'display_capabilities': <String, dynamic>{
        'battery_available': true,
        'charging_available': true,
      },
      'controls': <String, dynamic>{
        'volume': 35,
        'muted': false,
        'sleeping': false,
        'led_enabled': true,
        'led_brightness': 50,
        'led_color': '#2563eb',
      },
      'status_bar': <String, dynamic>{'weather_status': 'unsupported'},
      'last_command': <String, dynamic>{'status': 'idle'},
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

  testWidgets('device card shows app weather and not-wired telemetry states', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, buildNotWiredStatus());

    expect(find.text('Not Wired'), findsNWidgets(2));
    expect(find.text('25°C'), findsOneWidget);
    expect(find.textContaining('-44 dBm'), findsOneWidget);
    expect(find.text('19:36:19'), findsWidgets);
    expect(find.text('Computer · Open-Meteo'), findsOneWidget);
    expect(find.text('toggle_led · failed'), findsOneWidget);
  });

  testWidgets(
    'device card shows unknown when telemetry is present but invalid',
    (WidgetTester tester) async {
      await pumpCard(tester, buildUnknownTelemetryStatus());

      expect(find.text('Unknown'), findsNWidgets(2));
    },
  );

  testWidgets('device card metric chips keep a consistent height', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, buildNotWiredStatus());

    final stateChipSize = chipSizeForLabel(tester, 'State');
    final weatherChipSize = chipSizeForLabel(tester, 'Weather');
    final commandChipSize = chipSizeForLabel(tester, 'Last Command');

    expect(stateChipSize.height, weatherChipSize.height);
    expect(stateChipSize.height, commandChipSize.height);
  });
}
