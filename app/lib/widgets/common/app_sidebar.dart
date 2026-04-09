import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.items,
    required this.currentPath,
    required this.onSelect,
    super.key,
  });

  final List<({String label, IconData icon, String path})> items;
  final String currentPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: chrome.panel,
        border: Border(right: BorderSide(color: chrome.borderSubtle)),
      ),
      padding: const EdgeInsets.all(LinearSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('AI Bot', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Linear-inspired operator console',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
          ),
          const SizedBox(height: LinearSpacing.xl),
          for (final item in items) ...<Widget>[
            _SidebarItem(
              label: item.label,
              icon: item.icon,
              selected: currentPath.startsWith(item.path),
              onTap: () => onSelect(item.path),
            ),
            const SizedBox(height: LinearSpacing.xs),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(LinearSpacing.md),
            decoration: BoxDecoration(
              color: chrome.surface,
              borderRadius: LinearRadius.card,
              border: Border.all(color: chrome.borderStandard),
            ),
            child: Text(
              'Keep every existing tool reachable. Additive changes only.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: chrome.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: LinearRadius.card,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: LinearSpacing.sm,
            vertical: LinearSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? chrome.surfaceHover : Colors.transparent,
            borderRadius: LinearRadius.card,
            border: Border.all(
              color: selected ? chrome.borderStrong : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: selected ? chrome.textPrimary : chrome.textTertiary,
              ),
              const SizedBox(width: LinearSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? chrome.textPrimary : chrome.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
