import 'package:ai_bot_app/models/home/runtime_state_model.dart';
import 'package:ai_bot_app/widgets/home/device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'device card shows snapshot freshness and computer weather source',
    (WidgetTester tester) async {
      final status = DeviceStatusModel.fromJson(<String, dynamic>{
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DeviceCard(status: status)),
          ),
        ),
      );

      expect(find.text('Unknown'), findsWidgets);
      expect(find.textContaining('-44 dBm'), findsOneWidget);
      expect(find.text('19:36:19'), findsWidgets);
      expect(find.text('Computer · Open-Meteo'), findsOneWidget);
      expect(find.text('toggle_led · failed'), findsOneWidget);
    },
  );
}
