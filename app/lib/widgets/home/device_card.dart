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
    final batteryTelemetryMissing = status.battery < 0;
    final lastSeenValue = _formatSnapshotTime(
      status.lastSeenAt,
      fallback: status.connected ? 'Waiting' : 'Offline',
    );
    final weatherSource = _buildWeatherSourceLabel(
      status.statusBar.weatherMeta,
    );
    final weatherFreshness = _buildWeatherFreshnessLabel(
      status.statusBar.weatherMeta,
    );
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
            status.connected
                ? 'Live hardware state from the runtime channel.'
                : 'Device offline. Waiting for the hardware to reconnect.',
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
                value: batteryTelemetryMissing
                    ? 'Unknown'
                    : '${status.battery}%',
                detail: batteryTelemetryMissing ? 'Telemetry not wired' : null,
              ),
              _MetricChip(
                label: 'Wi-Fi',
                value: '${status.wifiSignal}%',
                detail: status.wifiRssi == 0 ? null : '${status.wifiRssi} dBm',
              ),
              _MetricChip(
                label: 'Charging',
                value: batteryTelemetryMissing
                    ? 'Unknown'
                    : (status.charging ? 'Yes' : 'No'),
                detail: batteryTelemetryMissing ? 'Demo placeholder' : null,
              ),
              _MetricChip(
                label: 'Connected',
                value: status.connected ? 'Yes' : 'No',
              ),
              _MetricChip(label: 'Last Seen', value: lastSeenValue),
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
                detail: status.statusBar.updatedAt == null ? null : 'Updated',
                caption: _formatSnapshotTimeOrNull(status.statusBar.updatedAt),
              ),
              _MetricChip(
                label: 'Weather',
                value: switch (status.statusBar.weatherStatus) {
                  'ready' => status.statusBar.weather ?? 'Ready',
                  'missing_api_key' => 'Key missing',
                  'fetch_failed' => 'Retry needed',
                  _ => 'Waiting',
                },
                detail: weatherSource,
                caption: weatherFreshness,
              ),
              _MetricChip(
                label: 'Last Command',
                value: status.lastCommand.command == null
                    ? status.lastCommand.status
                    : '${status.lastCommand.command} · ${status.lastCommand.status}',
                detail: status.lastCommand.updatedAt == null ? null : 'Updated',
                caption: _formatSnapshotTimeOrNull(
                  status.lastCommand.updatedAt,
                ),
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
  const _MetricChip({
    required this.label,
    required this.value,
    this.detail,
    this.caption,
  });

  final String label;
  final String value;
  final String? detail;
  final String? caption;

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
          if (detail case final String detailText
              when detailText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              detailText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
            ),
          ],
          if (caption case final String captionText
              when captionText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              captionText,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatSnapshotTime(String? value, {required String fallback}) {
  return _formatSnapshotTimeOrNull(value) ?? fallback;
}

String? _formatSnapshotTimeOrNull(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String? _buildWeatherSourceLabel(DeviceWeatherMetaModel weatherMeta) {
  final sourceLabel = switch (weatherMeta.source) {
    'computer_fetch' => 'Computer',
    final String source when source.trim().isNotEmpty => source.trim(),
    _ => null,
  };
  final providerLabel = switch (weatherMeta.provider) {
    'open-meteo-fallback' => 'Open-Meteo',
    'openweather' => 'OpenWeather',
    final String provider when provider.trim().isNotEmpty => provider.trim(),
    _ => null,
  };
  if (sourceLabel == null && providerLabel == null) {
    return null;
  }
  if (sourceLabel == null) {
    return providerLabel;
  }
  if (providerLabel == null) {
    return sourceLabel;
  }
  return '$sourceLabel · $providerLabel';
}

String? _buildWeatherFreshnessLabel(DeviceWeatherMetaModel weatherMeta) {
  final parts = <String>[];
  final city = weatherMeta.city?.trim();
  if (city != null && city.isNotEmpty) {
    parts.add(city);
  }
  final fetchedAt = _formatSnapshotTimeOrNull(weatherMeta.fetchedAt);
  if (fetchedAt != null) {
    parts.add(fetchedAt);
  }
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' · ');
}
