import 'package:flutter/material.dart';

import '../../models/home/runtime_state_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({required this.status, super.key});

  final DeviceStatusModel status;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Device Snapshot',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                label: status.connected ? 'Online' : 'Offline',
                tone: status.connected
                    ? StatusPillTone.success
                    : StatusPillTone.danger,
              ),
            ],
          ),
          const SizedBox(height: LinearSpacing.sm),
          Text(
            'Live hardware state from the runtime channel.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.md),
          Wrap(
            spacing: LinearSpacing.sm,
            runSpacing: LinearSpacing.sm,
            children: <Widget>[
              _MetricChip(label: 'State', value: status.state),
              _MetricChip(
                label: 'Battery',
                value: status.battery < 0 ? 'Unknown' : '${status.battery}%',
              ),
              _MetricChip(label: 'Wi-Fi', value: '${status.wifiSignal}%'),
              _MetricChip(
                label: 'Charging',
                value: status.charging ? 'Yes' : 'No',
              ),
              _MetricChip(
                label: 'Connected',
                value: status.connected ? 'Yes' : 'No',
              ),
              _MetricChip(
                label: 'Reconnects',
                value: '${status.reconnectCount}',
              ),
              _MetricChip(label: 'Volume', value: '${status.controls.volume}'),
              _MetricChip(
                label: 'Audio',
                value: status.controls.muted ? 'Muted' : 'Live',
              ),
              _MetricChip(
                label: 'Power',
                value: status.controls.sleeping ? 'Sleeping' : 'Awake',
              ),
              _MetricChip(
                label: 'LED',
                value:
                    '${status.controls.ledBrightness}% · ${status.controls.ledColor.toUpperCase()}',
              ),
              _MetricChip(
                label: 'Clock',
                value: status.statusBar.time ?? '--:--',
              ),
              _MetricChip(
                label: 'Weather',
                value: switch (status.statusBar.weatherStatus) {
                  'ready' => status.statusBar.weather ?? 'Ready',
                  'missing_api_key' => 'Key missing',
                  'fetch_failed' => 'Retry needed',
                  _ => 'Waiting',
                },
              ),
              _MetricChip(
                label: 'Last Command',
                value: status.lastCommand.command == null
                    ? status.lastCommand.status
                    : '${status.lastCommand.command} · ${status.lastCommand.status}',
              ),
            ],
          ),
          if (status.lastCommand.error != null) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Text(
              status.lastCommand.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.danger),
            ),
          ],
        ],
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
    final chrome = context.linear;
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.control,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: chrome.textPrimary),
          ),
        ],
      ),
    );
  }
}
