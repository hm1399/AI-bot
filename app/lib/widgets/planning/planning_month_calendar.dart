import 'package:flutter/material.dart';

import '../../models/planning/planning_agenda_entry_model.dart';
import '../../theme/linear_tokens.dart';

class PlanningMonthCalendar extends StatelessWidget {
  const PlanningMonthCalendar({
    required this.visibleMonth,
    required this.selectedDay,
    required this.entries,
    required this.onDaySelected,
    required this.onMonthChanged,
    super.key,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final List<PlanningAgendaEntryModel> entries;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final firstDayOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final firstCell = firstDayOfMonth.subtract(
      Duration(days: firstDayOfMonth.weekday - 1),
    );
    final buckets = _buildBuckets(entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => onMonthChanged(
                DateTime(visibleMonth.year, visibleMonth.month - 1, 1),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _monthLabel(visibleMonth),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => onMonthChanged(
                DateTime(visibleMonth.year, visibleMonth.month + 1, 1),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: LinearSpacing.sm),
        Row(
          children: _weekdayLabels.map((String label) {
            return Expanded(
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: chrome.textTertiary),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: LinearSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (BuildContext context, int index) {
            final day = DateTime(
              firstCell.year,
              firstCell.month,
              firstCell.day + index,
            );
            final bucket = buckets[_bucketKey(day)];
            final inVisibleMonth = day.month == visibleMonth.month;
            return _CalendarDayCell(
              day: day,
              bucket: bucket,
              inVisibleMonth: inVisibleMonth,
              selected: _isSameDay(day, selectedDay),
              today: _isSameDay(day, DateTime.now()),
              onTap: () => onDaySelected(day),
            );
          },
        ),
        const SizedBox(height: LinearSpacing.sm),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: const <Widget>[
            _CalendarLegend(
              label: 'Event',
              kind: PlanningAgendaEntryKind.event,
            ),
            _CalendarLegend(
              label: 'Reminder',
              kind: PlanningAgendaEntryKind.reminder,
            ),
            _CalendarLegend(label: 'Task', kind: PlanningAgendaEntryKind.task),
          ],
        ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.inVisibleMonth,
    required this.selected,
    required this.today,
    required this.onTap,
    this.bucket,
  });

  final DateTime day;
  final _PlanningDayBucket? bucket;
  final bool inVisibleMonth;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final hasEntries = bucket != null && bucket!.totalCount > 0;
    final background = selected
        ? chrome.accent.withValues(alpha: 0.12)
        : today
        ? chrome.panel
        : chrome.surface;
    final borderColor = selected
        ? chrome.accent
        : today
        ? chrome.borderStandard
        : chrome.borderSubtle;
    final dayColor = !inVisibleMonth
        ? chrome.textQuaternary
        : selected
        ? chrome.accent
        : chrome.textPrimary;

    return InkWell(
      borderRadius: LinearRadius.card,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: LinearRadius.card,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${day.day}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: dayColor),
                  ),
                ),
                if (hasEntries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: chrome.panel,
                      borderRadius: LinearRadius.pill,
                    ),
                    child: Text(
                      '${bucket!.totalCount}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            if (hasEntries)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: bucket!.kinds.map((PlanningAgendaEntryKind kind) {
                  return _KindDot(kind: kind);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _KindDot extends StatelessWidget {
  const _KindDot({required this.kind});

  final PlanningAgendaEntryKind kind;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      PlanningAgendaEntryKind.event => context.linear.accent,
      PlanningAgendaEntryKind.reminder => context.linear.warning,
      PlanningAgendaEntryKind.task => context.linear.success,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.label, required this.kind});

  final String label;
  final PlanningAgendaEntryKind kind;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _KindDot(kind: kind),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: context.linear.textTertiary),
        ),
      ],
    );
  }
}

class _PlanningDayBucket {
  const _PlanningDayBucket({required this.totalCount, required this.kinds});

  final int totalCount;
  final List<PlanningAgendaEntryKind> kinds;
}

Map<String, _PlanningDayBucket> _buildBuckets(
  List<PlanningAgendaEntryModel> entries,
) {
  final grouped = <String, List<PlanningAgendaEntryModel>>{};
  for (final entry in entries) {
    grouped
        .putIfAbsent(
          _bucketKey(entry.scheduledAt),
          () => <PlanningAgendaEntryModel>[],
        )
        .add(entry);
  }

  return grouped.map((String key, List<PlanningAgendaEntryModel> value) {
    final kinds = <PlanningAgendaEntryKind>{};
    for (final entry in value) {
      kinds.add(entry.kind);
    }
    return MapEntry(
      key,
      _PlanningDayBucket(
        totalCount: value.length,
        kinds: kinds.toList()
          ..sort(
            (PlanningAgendaEntryKind left, PlanningAgendaEntryKind right) =>
                _kindOrder(left).compareTo(_kindOrder(right)),
          ),
      ),
    );
  });
}

String _bucketKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

int _kindOrder(PlanningAgendaEntryKind kind) {
  return switch (kind) {
    PlanningAgendaEntryKind.event => 0,
    PlanningAgendaEntryKind.reminder => 1,
    PlanningAgendaEntryKind.task => 2,
  };
}

String _monthLabel(DateTime month) {
  return '${_monthNames[month.month - 1]} ${month.year}';
}

const List<String> _weekdayLabels = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _monthNames = <String>[
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
