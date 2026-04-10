import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../models/events/event_model.dart';
import '../../models/planning/planning_editor_models.dart';
import '../../models/reminders/reminder_model.dart';
import '../../models/tasks/task_model.dart';
import '../../providers/app_providers.dart';

Future<void> showPlanningEditorDialog(
  BuildContext context, {
  required PlanningEditorKind kind,
  required String origin,
  TaskModel? task,
  EventModel? event,
  ReminderModel? reminder,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return PlanningEditorDialog(
        kind: kind,
        origin: origin,
        task: task,
        event: event,
        reminder: reminder,
      );
    },
  );
}

class PlanningEditorDialog extends ConsumerStatefulWidget {
  const PlanningEditorDialog({
    required this.kind,
    required this.origin,
    this.task,
    this.event,
    this.reminder,
    super.key,
  });

  final PlanningEditorKind kind;
  final String origin;
  final TaskModel? task;
  final EventModel? event;
  final ReminderModel? reminder;

  @override
  ConsumerState<PlanningEditorDialog> createState() =>
      _PlanningEditorDialogState();
}

class _PlanningEditorDialogState extends ConsumerState<PlanningEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  late final TextEditingController _dueAtController;
  late final TextEditingController _startAtController;
  late final TextEditingController _endAtController;
  late final TextEditingController _locationController;
  late final TextEditingController _timeController;
  late final TextEditingController _bundleIdController;
  late final TextEditingController _createdViaController;
  late final TextEditingController _sourceChannelController;
  late final TextEditingController _sourceSessionIdController;
  late final TextEditingController _sourceMessageIdController;
  late final TextEditingController _linkedTaskIdController;
  late final TextEditingController _linkedEventIdController;
  late final TextEditingController _linkedReminderIdController;
  late final TextEditingController _linkedReminderTitleController;
  late final TextEditingController _linkedReminderMessageController;
  late final TextEditingController _linkedReminderTimeController;
  late final TextEditingController _linkedTaskTitleController;
  late final TextEditingController _linkedTaskDescriptionController;
  late final TextEditingController _linkedTaskDueAtController;

  late String _priority;
  late String _repeat;
  late String _linkedReminderRepeat;
  late String _linkedTaskPriority;
  late bool _completed;
  late bool _enabled;
  bool _createLinkedReminder = false;
  bool _createLinkedTask = false;
  bool _saving = false;
  String? _validationMessage;

  bool get _isEditing =>
      widget.task != null || widget.event != null || widget.reminder != null;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appControllerProvider);
    final metadata = switch (widget.kind) {
      PlanningEditorKind.task =>
        widget.task != null
            ? PlanningMetadataDraft.fromTask(
                widget.task!,
                fallbackCreatedVia: widget.origin,
                sourceChannel: 'app',
                sourceSessionId: appState.currentSessionId,
              )
            : PlanningMetadataDraft.forNew(
                createdVia: widget.origin,
                sourceChannel: 'app',
                sourceSessionId: appState.currentSessionId,
              ),
      PlanningEditorKind.event =>
        widget.event != null
            ? PlanningMetadataDraft.fromEvent(
                widget.event!,
                fallbackCreatedVia: widget.origin,
                sourceChannel: 'app',
                sourceSessionId: appState.currentSessionId,
              )
            : PlanningMetadataDraft.forNew(
                createdVia: widget.origin,
                sourceChannel: 'app',
                sourceSessionId: appState.currentSessionId,
              ),
      PlanningEditorKind.reminder =>
        widget.reminder != null
            ? PlanningMetadataDraft.fromReminder(
                widget.reminder!,
                fallbackCreatedVia: widget.origin,
                sourceChannel: 'app',
                sourceSessionId: appState.currentSessionId,
              )
            : PlanningMetadataDraft.forNew(
                createdVia: widget.origin,
                sourceChannel: 'app',
                sourceSessionId: appState.currentSessionId,
              ),
    };

    _titleController = TextEditingController(
      text:
          widget.task?.title ??
          widget.event?.title ??
          widget.reminder?.title ??
          '',
    );
    _detailsController = TextEditingController(
      text:
          widget.task?.description ??
          widget.event?.description ??
          widget.reminder?.message ??
          '',
    );
    _dueAtController = TextEditingController(text: widget.task?.dueAt ?? '');
    _startAtController = TextEditingController(
      text: widget.event?.startAt ?? '',
    );
    _endAtController = TextEditingController(text: widget.event?.endAt ?? '');
    _locationController = TextEditingController(
      text: widget.event?.location ?? '',
    );
    _timeController = TextEditingController(text: widget.reminder?.time ?? '');
    _bundleIdController = TextEditingController(text: metadata.bundleId);
    _createdViaController = TextEditingController(text: metadata.createdVia);
    _sourceChannelController = TextEditingController(
      text: metadata.sourceChannel,
    );
    _sourceSessionIdController = TextEditingController(
      text: metadata.sourceSessionId,
    );
    _sourceMessageIdController = TextEditingController(
      text: metadata.sourceMessageId,
    );
    _linkedTaskIdController = TextEditingController(
      text: metadata.linkedTaskId,
    );
    _linkedEventIdController = TextEditingController(
      text: metadata.linkedEventId,
    );
    _linkedReminderIdController = TextEditingController(
      text: metadata.linkedReminderId,
    );
    _linkedReminderTitleController = TextEditingController(
      text: _defaultLinkedReminderTitle(),
    );
    _linkedReminderMessageController = TextEditingController(
      text: _detailsController.text,
    );
    _linkedReminderTimeController = TextEditingController();
    _linkedTaskTitleController = TextEditingController(text: titleOrFallback);
    _linkedTaskDescriptionController = TextEditingController(
      text: _detailsController.text,
    );
    _linkedTaskDueAtController = TextEditingController();

    _priority = widget.task?.priority ?? 'medium';
    _repeat = widget.reminder?.repeat ?? 'daily';
    _linkedReminderRepeat = 'daily';
    _linkedTaskPriority = 'medium';
    _completed = widget.task?.completed ?? false;
    _enabled = widget.reminder?.enabled ?? true;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _titleController,
      _detailsController,
      _dueAtController,
      _startAtController,
      _endAtController,
      _locationController,
      _timeController,
      _bundleIdController,
      _createdViaController,
      _sourceChannelController,
      _sourceSessionIdController,
      _sourceMessageIdController,
      _linkedTaskIdController,
      _linkedEventIdController,
      _linkedReminderIdController,
      _linkedReminderTitleController,
      _linkedReminderMessageController,
      _linkedReminderTimeController,
      _linkedTaskTitleController,
      _linkedTaskDescriptionController,
      _linkedTaskDueAtController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${_isEditing ? 'Edit' : 'New'} ${widget.kind.label}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '${widget.kind.label} Title',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsController,
                decoration: InputDecoration(
                  labelText: widget.kind == PlanningEditorKind.reminder
                      ? 'Message'
                      : 'Description',
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              switch (widget.kind) {
                PlanningEditorKind.task => _buildTaskFields(context),
                PlanningEditorKind.event => _buildEventFields(context),
                PlanningEditorKind.reminder => _buildReminderFields(context),
              },
              if (!_isEditing) ...<Widget>[
                const SizedBox(height: 12),
                _buildBundleCreationFields(context),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('Planning Metadata'),
                subtitle: const Text(
                  'Shared bundle, source, and linked resource fields for manual edits.',
                ),
                children: <Widget>[
                  TextField(
                    controller: _bundleIdController,
                    decoration: InputDecoration(
                      labelText: 'Bundle ID',
                      suffixIcon: IconButton(
                        tooltip: 'Generate bundle id',
                        onPressed: () {
                          _bundleIdController.text = generatePlanningBundleId();
                        },
                        icon: const Icon(Icons.autorenew_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _createdViaController,
                    decoration: const InputDecoration(labelText: 'Created Via'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sourceChannelController,
                    decoration: const InputDecoration(
                      labelText: 'Source Channel',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sourceSessionIdController,
                    decoration: const InputDecoration(
                      labelText: 'Source Session ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sourceMessageIdController,
                    decoration: const InputDecoration(
                      labelText: 'Source Message ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _linkedTaskIdController,
                    decoration: const InputDecoration(
                      labelText: 'Linked Task ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _linkedEventIdController,
                    decoration: const InputDecoration(
                      labelText: 'Linked Event ID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _linkedReminderIdController,
                    decoration: const InputDecoration(
                      labelText: 'Linked Reminder ID',
                    ),
                  ),
                ],
              ),
              if (_validationMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _validationMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  Widget _buildTaskFields(BuildContext context) {
    return Column(
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'high', child: Text('High')),
            DropdownMenuItem(value: 'medium', child: Text('Medium')),
            DropdownMenuItem(value: 'low', child: Text('Low')),
          ],
          onChanged: (String? value) {
            if (value != null) {
              setState(() => _priority = value);
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dueAtController,
          decoration: InputDecoration(
            labelText: 'Due At',
            hintText: '2026-04-10T09:00:00',
            suffixIcon: IconButton(
              tooltip: 'Pick due date and time',
              onPressed: () => _pickDateTime(_dueAtController),
              icon: const Icon(Icons.event_available_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: _completed,
          onChanged: (bool value) {
            setState(() => _completed = value);
          },
          contentPadding: EdgeInsets.zero,
          title: const Text('Completed'),
        ),
      ],
    );
  }

  Widget _buildEventFields(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: _startAtController,
          decoration: InputDecoration(
            labelText: 'Start At',
            hintText: '2026-04-10T09:00:00',
            suffixIcon: IconButton(
              tooltip: 'Pick start time',
              onPressed: () => _pickDateTime(_startAtController),
              icon: const Icon(Icons.schedule_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endAtController,
          decoration: InputDecoration(
            labelText: 'End At',
            hintText: '2026-04-10T10:00:00',
            suffixIcon: IconButton(
              tooltip: 'Pick end time',
              onPressed: () => _pickDateTime(
                _endAtController,
                fallback: _parsedDateTime(_startAtController.text),
              ),
              icon: const Icon(Icons.event_busy_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(labelText: 'Location'),
        ),
      ],
    );
  }

  Widget _buildReminderFields(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: _timeController,
          decoration: InputDecoration(
            labelText: 'Time',
            hintText: '09:00',
            suffixIcon: IconButton(
              tooltip: 'Pick time',
              onPressed: () => _pickTime(_timeController),
              icon: const Icon(Icons.alarm_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _repeat,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
            DropdownMenuItem(value: 'weekends', child: Text('Weekends')),
            DropdownMenuItem(value: 'once', child: Text('Once')),
          ],
          onChanged: (String? value) {
            if (value != null) {
              setState(() => _repeat = value);
            }
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: _enabled,
          onChanged: (bool value) {
            setState(() => _enabled = value);
          },
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
        ),
      ],
    );
  }

  Widget _buildBundleCreationFields(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Bundle Creation'),
      subtitle: const Text(
        'Create linked items together so manual entries share one planning bundle.',
      ),
      children: <Widget>[
        if (widget.kind != PlanningEditorKind.reminder)
          SwitchListTile.adaptive(
            value: _createLinkedReminder,
            onChanged: (bool value) {
              setState(() => _createLinkedReminder = value);
            },
            contentPadding: EdgeInsets.zero,
            title: const Text('Also create linked reminder'),
          ),
        if (_createLinkedReminder) ...<Widget>[
          TextField(
            controller: _linkedReminderTitleController,
            decoration: const InputDecoration(
              labelText: 'Linked Reminder Title',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkedReminderMessageController,
            decoration: const InputDecoration(
              labelText: 'Linked Reminder Message',
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkedReminderTimeController,
            decoration: InputDecoration(
              labelText: 'Linked Reminder Time',
              hintText: '09:00',
              suffixIcon: IconButton(
                tooltip: 'Pick linked reminder time',
                onPressed: () => _pickTime(_linkedReminderTimeController),
                icon: const Icon(Icons.alarm_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _linkedReminderRepeat,
            decoration: const InputDecoration(
              labelText: 'Linked Reminder Repeat',
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'daily', child: Text('Daily')),
              DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
              DropdownMenuItem(value: 'weekends', child: Text('Weekends')),
              DropdownMenuItem(value: 'once', child: Text('Once')),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _linkedReminderRepeat = value);
              }
            },
          ),
        ],
        if (widget.kind == PlanningEditorKind.reminder)
          SwitchListTile.adaptive(
            value: _createLinkedTask,
            onChanged: (bool value) {
              setState(() => _createLinkedTask = value);
            },
            contentPadding: EdgeInsets.zero,
            title: const Text('Also create linked task'),
          ),
        if (_createLinkedTask) ...<Widget>[
          TextField(
            controller: _linkedTaskTitleController,
            decoration: const InputDecoration(labelText: 'Linked Task Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkedTaskDescriptionController,
            decoration: const InputDecoration(
              labelText: 'Linked Task Description',
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _linkedTaskPriority,
            decoration: const InputDecoration(
              labelText: 'Linked Task Priority',
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'low', child: Text('Low')),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _linkedTaskPriority = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkedTaskDueAtController,
            decoration: InputDecoration(
              labelText: 'Linked Task Due At',
              hintText: '2026-04-10T09:00:00',
              suffixIcon: IconButton(
                tooltip: 'Pick linked task due time',
                onPressed: () => _pickDateTime(_linkedTaskDueAtController),
                icon: const Icon(Icons.event_available_outlined),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDateTime(
    TextEditingController controller, {
    DateTime? fallback,
  }) async {
    final initial =
        _parsedDateTime(controller.text) ?? fallback ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null) {
      return;
    }
    controller.text = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toIso8601String();
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final initial = _parsedTimeOfDay(controller.text) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) {
      return;
    }
    controller.text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final metadata = PlanningMetadataDraft(
      bundleId: _bundleIdController.text.trim(),
      createdVia: _createdViaController.text.trim(),
      sourceChannel: _sourceChannelController.text.trim(),
      sourceSessionId: _sourceSessionIdController.text.trim(),
      sourceMessageId: _sourceMessageIdController.text.trim(),
      linkedTaskId: _linkedTaskIdController.text.trim(),
      linkedEventId: _linkedEventIdController.text.trim(),
      linkedReminderId: _linkedReminderIdController.text.trim(),
    );

    final validationMessage = _validate(title: title);
    if (validationMessage != null) {
      setState(() => _validationMessage = validationMessage);
      return;
    }

    setState(() {
      _saving = true;
      _validationMessage = null;
    });

    final controller = ref.read(appControllerProvider.notifier);
    final now = DateTime.now().toIso8601String();

    switch (widget.kind) {
      case PlanningEditorKind.task:
        final existing = widget.task;
        final next = _buildTaskDraft(
          now: now,
          title: title,
          metadata: metadata,
          existing: existing,
        );
        if (existing == null) {
          await controller.createPlanningBundle(
            tasks: <TaskModel>[next],
            reminders: _createLinkedReminder
                ? <ReminderModel>[
                    _buildLinkedReminderDraft(now: now, metadata: metadata),
                  ]
                : const <ReminderModel>[],
            successMessage: _bundleSuccessMessage(widget.kind),
          );
        } else {
          await controller.updateTask(next);
        }
        break;
      case PlanningEditorKind.event:
        final existing = widget.event;
        final next = _buildEventDraft(
          now: now,
          title: title,
          metadata: metadata,
          existing: existing,
        );
        if (existing == null) {
          await controller.createPlanningBundle(
            events: <EventModel>[next],
            reminders: _createLinkedReminder
                ? <ReminderModel>[
                    _buildLinkedReminderDraft(now: now, metadata: metadata),
                  ]
                : const <ReminderModel>[],
            successMessage: _bundleSuccessMessage(widget.kind),
          );
        } else {
          await controller.updateEvent(next);
        }
        break;
      case PlanningEditorKind.reminder:
        final existing = widget.reminder;
        final next = _buildReminderDraft(
          now: now,
          title: title,
          metadata: metadata,
          existing: existing,
        );
        if (existing == null) {
          await controller.createPlanningBundle(
            reminders: <ReminderModel>[next],
            tasks: _createLinkedTask
                ? <TaskModel>[
                    _buildLinkedTaskDraft(now: now, metadata: metadata),
                  ]
                : const <TaskModel>[],
            successMessage: _bundleSuccessMessage(widget.kind),
          );
        } else {
          await controller.updateReminder(next);
        }
        break;
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  String? _validate({required String title}) {
    if (title.isEmpty) {
      return 'Title is required.';
    }
    if (_createLinkedReminder &&
        _linkedReminderTimeController.text.trim().isEmpty) {
      return 'Linked reminder time is required.';
    }
    switch (widget.kind) {
      case PlanningEditorKind.task:
        return null;
      case PlanningEditorKind.event:
        if (_startAtController.text.trim().isEmpty ||
            _endAtController.text.trim().isEmpty) {
          return 'Event start and end time are required.';
        }
        return null;
      case PlanningEditorKind.reminder:
        if (_timeController.text.trim().isEmpty) {
          return 'Reminder time is required.';
        }
        return null;
    }
  }

  TaskModel _buildTaskDraft({
    required String now,
    required String title,
    required PlanningMetadataDraft metadata,
    required TaskModel? existing,
  }) {
    return TaskModel(
      id: existing?.id ?? 'task_local_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: _nullableText(_detailsController.text),
      priority: _priority,
      completed: _completed,
      dueAt: _nullableText(_dueAtController.text),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      bundleId: _nullableText(metadata.bundleId) ?? generatePlanningBundleId(),
      createdVia: _nullableText(metadata.createdVia) ?? widget.origin,
      sourceChannel: _nullableText(metadata.sourceChannel) ?? 'app',
      sourceSessionId: _nullableText(metadata.sourceSessionId),
      sourceMessageId: _nullableText(metadata.sourceMessageId),
      linkedTaskId: _nullableText(metadata.linkedTaskId),
      linkedEventId: _nullableText(metadata.linkedEventId),
      linkedReminderId: _nullableText(metadata.linkedReminderId),
      normalizedTime: existing?.normalizedTime,
      normalizedTimes: existing?.normalizedTimes ?? const <String, dynamic>{},
      conflictSummaries: existing?.conflictSummaries ?? const <String>[],
      planningMetadata: metadata.toMetadataMap(
        seed: existing?.planningMetadata ?? const <String, dynamic>{},
      ),
    );
  }

  EventModel _buildEventDraft({
    required String now,
    required String title,
    required PlanningMetadataDraft metadata,
    required EventModel? existing,
  }) {
    return EventModel(
      id:
          existing?.id ??
          'event_local_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: _nullableText(_detailsController.text),
      startAt: _startAtController.text.trim(),
      endAt: _endAtController.text.trim(),
      location: _nullableText(_locationController.text),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      bundleId: _nullableText(metadata.bundleId) ?? generatePlanningBundleId(),
      createdVia: _nullableText(metadata.createdVia) ?? widget.origin,
      sourceChannel: _nullableText(metadata.sourceChannel) ?? 'app',
      sourceSessionId: _nullableText(metadata.sourceSessionId),
      sourceMessageId: _nullableText(metadata.sourceMessageId),
      linkedTaskId: _nullableText(metadata.linkedTaskId),
      linkedEventId: _nullableText(metadata.linkedEventId),
      linkedReminderId: _nullableText(metadata.linkedReminderId),
      normalizedTime: existing?.normalizedTime,
      normalizedTimes: existing?.normalizedTimes ?? const <String, dynamic>{},
      conflictSummaries: existing?.conflictSummaries ?? const <String>[],
      planningMetadata: metadata.toMetadataMap(
        seed: existing?.planningMetadata ?? const <String, dynamic>{},
      ),
    );
  }

  ReminderModel _buildReminderDraft({
    required String now,
    required String title,
    required PlanningMetadataDraft metadata,
    required ReminderModel? existing,
  }) {
    return ReminderModel(
      id: existing?.id ?? 'rem_local_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: _detailsController.text.trim(),
      time: _timeController.text.trim(),
      repeat: _repeat,
      enabled: _enabled,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      bundleId: _nullableText(metadata.bundleId) ?? generatePlanningBundleId(),
      createdVia: _nullableText(metadata.createdVia) ?? widget.origin,
      sourceChannel: _nullableText(metadata.sourceChannel) ?? 'app',
      sourceSessionId: _nullableText(metadata.sourceSessionId),
      sourceMessageId: _nullableText(metadata.sourceMessageId),
      linkedTaskId: _nullableText(metadata.linkedTaskId),
      linkedEventId: _nullableText(metadata.linkedEventId),
      linkedReminderId: _nullableText(metadata.linkedReminderId),
      normalizedTime: existing?.normalizedTime,
      normalizedTimes: existing?.normalizedTimes ?? const <String, dynamic>{},
      conflictSummaries: existing?.conflictSummaries ?? const <String>[],
      nextTriggerAt: existing?.nextTriggerAt,
      lastTriggeredAt: existing?.lastTriggeredAt,
      lastError: existing?.lastError,
      snoozedUntil: existing?.snoozedUntil,
      completedAt: existing?.completedAt,
      status: existing?.status,
      planningMetadata: metadata.toMetadataMap(
        seed: existing?.planningMetadata ?? const <String, dynamic>{},
      ),
      runtimeMetadata: existing?.runtimeMetadata ?? const <String, dynamic>{},
    );
  }

  ReminderModel _buildLinkedReminderDraft({
    required String now,
    required PlanningMetadataDraft metadata,
  }) {
    return ReminderModel(
      id: 'rem_local_${DateTime.now().millisecondsSinceEpoch}',
      title: _linkedReminderTitleController.text.trim().isEmpty
          ? _defaultLinkedReminderTitle()
          : _linkedReminderTitleController.text.trim(),
      message: _linkedReminderMessageController.text.trim(),
      time: _linkedReminderTimeController.text.trim(),
      repeat: _linkedReminderRepeat,
      enabled: true,
      createdAt: now,
      updatedAt: now,
      bundleId: _nullableText(metadata.bundleId) ?? generatePlanningBundleId(),
      createdVia: _nullableText(metadata.createdVia) ?? widget.origin,
      sourceChannel: _nullableText(metadata.sourceChannel) ?? 'app',
      sourceSessionId: _nullableText(metadata.sourceSessionId),
      sourceMessageId: _nullableText(metadata.sourceMessageId),
      planningMetadata: metadata.toMetadataMap(),
    );
  }

  TaskModel _buildLinkedTaskDraft({
    required String now,
    required PlanningMetadataDraft metadata,
  }) {
    return TaskModel(
      id: 'task_local_${DateTime.now().millisecondsSinceEpoch}',
      title: _linkedTaskTitleController.text.trim().isEmpty
          ? _titleController.text.trim()
          : _linkedTaskTitleController.text.trim(),
      description: _nullableText(_linkedTaskDescriptionController.text),
      priority: _linkedTaskPriority,
      completed: false,
      dueAt: _nullableText(_linkedTaskDueAtController.text),
      createdAt: now,
      updatedAt: now,
      bundleId: _nullableText(metadata.bundleId) ?? generatePlanningBundleId(),
      createdVia: _nullableText(metadata.createdVia) ?? widget.origin,
      sourceChannel: _nullableText(metadata.sourceChannel) ?? 'app',
      sourceSessionId: _nullableText(metadata.sourceSessionId),
      sourceMessageId: _nullableText(metadata.sourceMessageId),
      planningMetadata: metadata.toMetadataMap(),
    );
  }

  String _defaultLinkedReminderTitle() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return 'Reminder';
    }
    return '$title reminder';
  }

  String get titleOrFallback {
    final title = _titleController.text.trim();
    return title.isEmpty ? 'Task' : title;
  }

  String _bundleSuccessMessage(PlanningEditorKind kind) {
    final linkedCount =
        (_createLinkedReminder ? 1 : 0) + (_createLinkedTask ? 1 : 0);
    if (linkedCount == 0) {
      return '${kind.label} created through the planning bundle.';
    }
    return '${kind.label} and linked planning items created together.';
  }
}

DateTime? _parsedDateTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

TimeOfDay? _parsedTimeOfDay(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String? _nullableText(String raw) {
  final value = raw.trim();
  return value.isEmpty ? null : value;
}
