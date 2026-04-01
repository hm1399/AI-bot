import 'package:flutter/material.dart';

import '../../models/home/runtime_state_model.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({required this.status, super.key});

  final DeviceStatusModel status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Device Snapshot',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _MetricChip(label: 'State', value: status.state),
                _MetricChip(label: 'Battery', value: '${status.battery}%'),
                _MetricChip(label: 'Wi-Fi', value: '${status.wifiSignal}%'),
                _MetricChip(
                  label: 'Charging',
                  value: status.charging ? 'Yes' : 'No',
                ),
                _MetricChip(
                  label: 'Connected',
                  value: status.connected ? 'Yes' : 'No',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
