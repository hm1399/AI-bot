import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

enum StatusPillTone { neutral, accent, success, warning, danger }

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.tone = StatusPillTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final StatusPillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    final colors = switch (tone) {
      StatusPillTone.accent => (chrome.accent.withOpacity(0.18), chrome.accent),
      StatusPillTone.success => (
        chrome.success.withOpacity(0.18),
        chrome.success,
      ),
      StatusPillTone.warning => (
        chrome.warning.withOpacity(0.18),
        chrome.warning,
      ),
      StatusPillTone.danger => (chrome.danger.withOpacity(0.18), chrome.danger),
      StatusPillTone.neutral => (chrome.panel, chrome.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LinearSpacing.sm,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: LinearRadius.pill,
        border: Border.all(
          color: tone == StatusPillTone.neutral
              ? chrome.borderStandard
              : colors.$2.withOpacity(0.36),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: colors.$2),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.$2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
