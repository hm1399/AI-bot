import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

class OverviewStatCard extends StatelessWidget {
  const OverviewStatCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.highlight = false,
    super.key,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(LinearSpacing.md),
      decoration: BoxDecoration(
        color: highlight ? chrome.surfaceElevated : chrome.surface,
        borderRadius: LinearRadius.card,
        border: Border.all(
          color: highlight ? chrome.borderStrong : chrome.borderStandard,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 18,
            color: highlight ? chrome.accent : chrome.textTertiary,
          ),
          const SizedBox(height: LinearSpacing.md),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
        ],
      ),
    );
  }
}
