import 'package:flutter/material.dart';

import '../../models/planning/planning_agenda_entry_model.dart';
import '../../models/reminders/reminder_model.dart';
import '../../providers/app_state.dart';
import '../../theme/linear_tokens.dart';

class PlanningDaySchedule extends StatelessWidget {
  const PlanningDaySchedule({
    required this.selectedDay,
    required this.entries,
    required this.hiddenReminders,
    required this.timelineStatus,
    required this.timelineMessage,
    required this.degraded,
    required this.onEditEntry,
    super.key,
  });

  final DateTime selectedDay;
  final List<PlanningAgendaEntryModel> entries;
  final List<ReminderModel> hiddenReminders;
  final FeatureStatus timelineStatus;
  final String? timelineMessage;
  final bool degraded;
  final ValueChanged<PlanningAgendaEntryModel> onEditEntry;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderStandard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _formatDayLabel(selectedDay),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Events, reminders, and due tasks for the selected day.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          if (timelineStatus == FeatureStatus.notReady ||
              timelineStatus == FeatureStatus.error ||
              degraded) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _AgendaBanner(
              message:
                  timelineMessage ??
                  (timelineStatus == FeatureStatus.notReady
                      ? 'Planning timeline is not ready. Day view is using dated tasks, events, and reminders only.'
                      : 'Planning timeline is degraded. Some reminders may stay hidden until the backend provides next trigger dates.'),
              tone: timelineStatus == FeatureStatus.error
                  ? _AgendaBannerTone.danger
                  : _AgendaBannerTone.warning,
            ),
          ],
          if (hiddenReminders.isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.md),
            _AgendaBanner(
              message:
                  '${hiddenReminders.length} reminder(s) are omitted from the calendar because no reliable day could be resolved from next trigger data.',
              tone: _AgendaBannerTone.neutral,
            ),
          ],
          const SizedBox(height: LinearSpacing.md),
          if (entries.isEmpty)
            _EmptySchedule(
              message:
                  'No scheduled items for ${_formatDayLabel(selectedDay)}.',
            )
          else
            Column(
              children: entries.map((PlanningAgendaEntryModel entry) {
                return _AgendaEntryCard(
                  entry: entry,
                  onEdit: () => onEditEntry(entry),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _AgendaEntryCard extends StatelessWidget {
  const _AgendaEntryCard({required this.entry, required this.onEdit});

  final PlanningAgendaEntryModel entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _iconForEntry(entry.kind),
                size: 18,
                color: chrome.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Edit ${entry.kind.name}',
                onPressed: entry.canEdit ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ScheduleTag(label: _kindLabel(entry.kind)),
              _ScheduleTag(label: _formatTimeLabel(entry)),
              if (_secondaryLabel(entry) case final String label)
                _ScheduleTag(label: label),
              if (_statusLabel(entry) case final String status)
                _ScheduleTag(label: status),
              if (_sourceLabel(entry) case final String source)
                _ScheduleTag(label: source),
              if (entry.bundleId?.isNotEmpty == true)
                _ScheduleTag(label: 'Bundle ${entry.bundleId!}'),
            ],
          ),
          if (entry.description?.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              entry.description!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleTag extends StatelessWidget {
  const _ScheduleTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chrome.surface,
        borderRadius: LinearRadius.pill,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
      ),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.xl),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.card,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
      ),
    );
  }
}

enum _AgendaBannerTone { neutral, warning, danger }

class _AgendaBanner extends StatelessWidget {
  const _AgendaBanner({required this.message, required this.tone});

  final String message;
  final _AgendaBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final background = switch (tone) {
      _AgendaBannerTone.neutral => chrome.panel,
      _AgendaBannerTone.warning => chrome.warning.withValues(alpha: 0.08),
      _AgendaBannerTone.danger => chrome.danger.withValues(alpha: 0.08),
    };
    final border = switch (tone) {
      _AgendaBannerTone.neutral => chrome.borderSubtle,
      _AgendaBannerTone.warning => chrome.warning.withValues(alpha: 0.36),
      _AgendaBannerTone.danger => chrome.danger.withValues(alpha: 0.36),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: LinearRadius.card,
        border: Border.all(color: border),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

String _formatDayLabel(DateTime value) {
  const monthLabels = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${monthLabels[value.month - 1]} ${value.day}, ${value.year}';
}

String _formatTimeLabel(PlanningAgendaEntryModel entry) {
  switch (entry.kind) {
    case PlanningAgendaEntryKind.event:
      return _formatRange(
        entry.scheduledAt,
        entry.endsAt,
        allDay: entry.allDay,
      );
    case PlanningAgendaEntryKind.task:
      return 'Due ${_formatTime(entry.scheduledAt)}';
    case PlanningAgendaEntryKind.reminder:
      return 'Reminder ${_formatTime(entry.scheduledAt)}';
  }
}

String _formatRange(DateTime start, DateTime? end, {required bool allDay}) {
  if (allDay) {
    return 'All day';
  }
  if (end == null) {
    return _formatTime(start);
  }
  return '${_formatTime(start)} - ${_formatTime(end)}';
}

String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${value.minute.toString().padLeft(2, '0')} $suffix';
}

String _kindLabel(PlanningAgendaEntryKind kind) {
  return switch (kind) {
    PlanningAgendaEntryKind.event => 'Event',
    PlanningAgendaEntryKind.task => 'Task',
    PlanningAgendaEntryKind.reminder => 'Reminder',
  };
}

IconData _iconForEntry(PlanningAgendaEntryKind kind) {
  return switch (kind) {
    PlanningAgendaEntryKind.event => Icons.event_outlined,
    PlanningAgendaEntryKind.task => Icons.task_alt_outlined,
    PlanningAgendaEntryKind.reminder => Icons.alarm_outlined,
  };
}

String? _secondaryLabel(PlanningAgendaEntryModel entry) {
  return switch (entry.kind) {
    PlanningAgendaEntryKind.event => _nonEmpty(entry.location),
    PlanningAgendaEntryKind.task => _nonEmpty(entry.priority),
    PlanningAgendaEntryKind.reminder => _nonEmpty(entry.repeat),
  };
}

String? _statusLabel(PlanningAgendaEntryModel entry) {
  if (entry.kind == PlanningAgendaEntryKind.task) {
    if (entry.completed) {
      return 'Completed';
    }
    if (entry.overdue) {
      return 'Overdue';
    }
  }
  return _nonEmpty(entry.status);
}

String? _sourceLabel(PlanningAgendaEntryModel entry) {
  final createdVia = _nonEmpty(entry.createdVia);
  final sourceChannel = _nonEmpty(entry.sourceChannel);
  if (createdVia == null && sourceChannel == null) {
    return null;
  }
  if (createdVia != null && sourceChannel != null) {
    return '$createdVia · $sourceChannel';
  }
  return createdVia ?? sourceChannel;
}

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
