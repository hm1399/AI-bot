import 'package:flutter/material.dart';

import '../../models/control/computer_action_model.dart';
import '../../theme/linear_tokens.dart';
import '../common/status_pill.dart';

class ComputerActionPanel extends StatefulWidget {
  const ComputerActionPanel({
    required this.state,
    required this.onRefresh,
    required this.onRunAction,
    required this.onConfirmAction,
    required this.onCancelAction,
    super.key,
  });

  final ComputerControlStateModel state;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ComputerActionRequest request) onRunAction;
  final Future<void> Function(String actionId) onConfirmAction;
  final Future<void> Function(String actionId) onCancelAction;

  @override
  State<ComputerActionPanel> createState() => _ComputerActionPanelState();
}

class _ComputerActionPanelState extends State<ComputerActionPanel> {
  late final TextEditingController _appController;
  late final TextEditingController _pathController;
  late final TextEditingController _urlController;
  late final TextEditingController _shortcutController;
  late final TextEditingController _scriptController;

  @override
  void initState() {
    super.initState();
    _appController = TextEditingController();
    _pathController = TextEditingController();
    _urlController = TextEditingController();
    _shortcutController = TextEditingController();
    _scriptController = TextEditingController();
  }

  @override
  void dispose() {
    _appController.dispose();
    _pathController.dispose();
    _urlController.dispose();
    _shortcutController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  bool _supports(String kind) {
    if (!widget.state.available && widget.state.supportedActions.isEmpty) {
      return false;
    }
    final actions = widget.state.supportedActions;
    return actions.isEmpty || actions.contains(kind);
  }

  Future<void> _submitTextAction({
    required String kind,
    required TextEditingController controller,
    required String argumentKey,
    required String reason,
  }) async {
    final value = controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    await widget.onRunAction(
      ComputerActionRequest(
        kind: kind,
        arguments: <String, dynamic>{argumentKey: value},
        reason: reason,
      ),
    );
    if (!mounted) {
      return;
    }
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final state = widget.state;
    final unavailable = !state.available && state.supportedActions.isEmpty;
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
                  'Computer Actions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: widget.onRefresh,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            unavailable
                ? 'Structured computer control is not exposed by this backend yet.'
                : 'Use structured actions instead of ad hoc shell commands. High-risk actions stay in approval.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: state.available ? 'Control Available' : 'Control Waiting',
                tone: state.available
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
                icon: Icons.computer_outlined,
              ),
              StatusPill(
                label: state.hasPendingActions
                    ? '${state.pendingActions.length} Pending'
                    : 'No Pending Actions',
                tone: state.hasPendingActions
                    ? StatusPillTone.warning
                    : StatusPillTone.neutral,
                icon: Icons.pending_actions_outlined,
              ),
              StatusPill(
                label: state.hasRecentActions
                    ? '${state.recentActions.length} Recent'
                    : 'No Recent Actions',
                tone: state.hasRecentActions
                    ? StatusPillTone.accent
                    : StatusPillTone.neutral,
                icon: Icons.history_outlined,
              ),
            ],
          ),
          if (state.permissionHints.isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Wrap(
              spacing: LinearSpacing.xs,
              runSpacing: LinearSpacing.xs,
              children: state.permissionHints
                  .map((String hint) => _HintChip(label: _formatHint(hint)))
                  .toList(),
            ),
          ],
          if (state.statusMessage != null && state.statusMessage!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LinearSpacing.sm),
              decoration: BoxDecoration(
                color: chrome.panel,
                borderRadius: LinearRadius.control,
                border: Border.all(color: chrome.borderSubtle),
              ),
              child: Text(
                state.statusMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: LinearSpacing.md),
          _ActionComposer(
            appController: _appController,
            pathController: _pathController,
            urlController: _urlController,
            shortcutController: _shortcutController,
            scriptController: _scriptController,
            supports: _supports,
            onOpenApp: () => _submitTextAction(
              kind: 'open_app',
              controller: _appController,
              argumentKey: 'app',
              reason: 'Open app from Control Center',
            ),
            onOpenPath: () => _submitTextAction(
              kind: 'open_path',
              controller: _pathController,
              argumentKey: 'path',
              reason: 'Open path from Control Center',
            ),
            onOpenUrl: () => _submitTextAction(
              kind: 'open_url',
              controller: _urlController,
              argumentKey: 'url',
              reason: 'Open URL from Control Center',
            ),
            onRunShortcut: () => _submitTextAction(
              kind: 'run_shortcut',
              controller: _shortcutController,
              argumentKey: 'shortcut',
              reason: 'Run shortcut from Control Center',
            ),
            onRunScript: () => _submitTextAction(
              kind: 'run_script',
              controller: _scriptController,
              argumentKey: 'script_id',
              reason: 'Run script from Control Center',
            ),
            onSystemInfo: _supports('system_info')
                ? () => widget.onRunAction(
                    const ComputerActionRequest(
                      kind: 'system_info',
                      arguments: <String, dynamic>{
                        'profile': 'frontmost_app',
                      },
                      reason: 'Inspect frontmost app from Control Center',
                    ),
                  )
                : null,
          ),
          const SizedBox(height: LinearSpacing.md),
          _ActionListSection(
            title: 'Pending Approvals',
            emptyLabel: 'No approvals are waiting right now.',
            actions: state.pendingActions,
            onConfirmAction: widget.onConfirmAction,
            onCancelAction: widget.onCancelAction,
          ),
          const SizedBox(height: LinearSpacing.md),
          _ActionListSection(
            title: 'Recent Actions',
            emptyLabel: 'No recent structured computer actions yet.',
            actions: state.recentActions,
            onConfirmAction: widget.onConfirmAction,
            onCancelAction: widget.onCancelAction,
            limit: 6,
          ),
        ],
      ),
    );
  }
}

class _ActionComposer extends StatelessWidget {
  const _ActionComposer({
    required this.appController,
    required this.pathController,
    required this.urlController,
    required this.shortcutController,
    required this.scriptController,
    required this.supports,
    required this.onOpenApp,
    required this.onOpenPath,
    required this.onOpenUrl,
    required this.onRunShortcut,
    required this.onRunScript,
    required this.onSystemInfo,
  });

  final TextEditingController appController;
  final TextEditingController pathController;
  final TextEditingController urlController;
  final TextEditingController shortcutController;
  final TextEditingController scriptController;
  final bool Function(String kind) supports;
  final Future<void> Function() onOpenApp;
  final Future<void> Function() onOpenPath;
  final Future<void> Function() onOpenUrl;
  final Future<void> Function() onRunShortcut;
  final Future<void> Function() onRunScript;
  final Future<void> Function()? onSystemInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: LinearSpacing.sm),
        _QuickActionRow(
          controller: appController,
          label: 'Open App',
          hintText: 'Safari',
          buttonText: 'Open',
          enabled: supports('open_app'),
          onPressed: onOpenApp,
        ),
        const SizedBox(height: LinearSpacing.sm),
        _QuickActionRow(
          controller: pathController,
          label: 'Open File / Folder',
          hintText: '/Users/mandy/Desktop',
          buttonText: 'Open',
          enabled: supports('open_path'),
          onPressed: onOpenPath,
        ),
        const SizedBox(height: LinearSpacing.sm),
        _QuickActionRow(
          controller: urlController,
          label: 'Open URL',
          hintText: 'https://openai.com',
          buttonText: 'Open',
          enabled: supports('open_url'),
          onPressed: onOpenUrl,
        ),
        const SizedBox(height: LinearSpacing.sm),
        _QuickActionRow(
          controller: shortcutController,
          label: 'Run Shortcut',
          hintText: 'daily-brief',
          buttonText: 'Run',
          enabled: supports('run_shortcut'),
          onPressed: onRunShortcut,
        ),
        const SizedBox(height: LinearSpacing.sm),
        _QuickActionRow(
          controller: scriptController,
          label: 'Run Script',
          hintText: 'project-healthcheck',
          buttonText: 'Run',
          enabled: supports('run_script'),
          onPressed: onRunScript,
        ),
        const SizedBox(height: LinearSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onSystemInfo,
            icon: const Icon(Icons.info_outline, size: 16),
            label: const Text('Frontmost App Info'),
          ),
        ),
      ],
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.buttonText,
    required this.enabled,
    required this.onPressed,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final String buttonText;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: label,
              hintText: hintText,
            ),
          ),
        ),
        const SizedBox(width: LinearSpacing.sm),
        FilledButton.tonal(
          onPressed: enabled ? onPressed : null,
          child: Text(buttonText),
        ),
      ],
    );
  }
}

class _ActionListSection extends StatelessWidget {
  const _ActionListSection({
    required this.title,
    required this.emptyLabel,
    required this.actions,
    required this.onConfirmAction,
    required this.onCancelAction,
    this.limit,
  });

  final String title;
  final String emptyLabel;
  final List<ComputerActionModel> actions;
  final Future<void> Function(String actionId) onConfirmAction;
  final Future<void> Function(String actionId) onCancelAction;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final visible = limit == null
        ? actions
        : actions.take(limit!).toList(growable: false);
    final chrome = context.linear;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: LinearSpacing.sm),
        if (visible.isEmpty)
          Text(
            emptyLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          )
        else
          ...visible.map(
            (ComputerActionModel action) => _ActionCard(
              action: action,
              onConfirmAction: onConfirmAction,
              onCancelAction: onCancelAction,
            ),
          ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.action,
    required this.onConfirmAction,
    required this.onCancelAction,
  });

  final ComputerActionModel action;
  final Future<void> Function(String actionId) onConfirmAction;
  final Future<void> Function(String actionId) onCancelAction;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      margin: const EdgeInsets.only(bottom: LinearSpacing.sm),
      padding: const EdgeInsets.all(LinearSpacing.sm),
      decoration: BoxDecoration(
        color: chrome.panel,
        borderRadius: LinearRadius.control,
        border: Border.all(color: chrome.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  action.displaySummary,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              StatusPill(
                label: action.displayStatusLabel,
                tone: _statusTone(action),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: <Widget>[
              StatusPill(
                label: action.kind.replaceAll('_', ' '),
                tone: StatusPillTone.neutral,
              ),
              StatusPill(
                label: action.riskLevel.replaceAll('_', ' '),
                tone: action.riskLevel == 'high'
                    ? StatusPillTone.danger
                    : action.riskLevel == 'medium'
                    ? StatusPillTone.warning
                    : StatusPillTone.accent,
              ),
            ],
          ),
          if (action.outputSummary != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              action.outputSummary!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textSecondary),
            ),
          ],
          if (action.timestamp != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              action.timestamp!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textQuaternary),
            ),
          ],
          if (action.isAwaitingConfirmation && action.actionId.isNotEmpty) ...<Widget>[
            const SizedBox(height: LinearSpacing.sm),
            Row(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => onConfirmAction(action.actionId),
                  child: const Text('Confirm'),
                ),
                const SizedBox(width: LinearSpacing.sm),
                OutlinedButton(
                  onPressed: () => onCancelAction(action.actionId),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chrome.panel,
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

StatusPillTone _statusTone(ComputerActionModel action) {
  if (action.isFailed) {
    return StatusPillTone.danger;
  }
  if (action.isSuccessful) {
    return StatusPillTone.success;
  }
  if (action.isAwaitingConfirmation) {
    return StatusPillTone.warning;
  }
  if (action.isPendingLike) {
    return StatusPillTone.accent;
  }
  return StatusPillTone.neutral;
}

String _formatHint(String hint) {
  return hint.split('_').map((String part) {
    if (part.isEmpty) {
      return part;
    }
    return '${part[0].toUpperCase()}${part.substring(1)}';
  }).join(' ');
}
