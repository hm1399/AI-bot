import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

class AppBottomDock extends StatelessWidget {
  const AppBottomDock({
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
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LinearSpacing.sm,
          8,
          LinearSpacing.sm,
          12,
        ),
        decoration: BoxDecoration(
          color: chrome.panel,
          border: Border(top: BorderSide(color: chrome.borderSubtle)),
        ),
        child: Row(
          children: items
              .map(
                (item) => Expanded(
                  child: _DockItem(
                    label: item.label,
                    icon: item.icon,
                    selected: currentPath.startsWith(item.path),
                    onTap: () => onSelect(item.path),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: LinearRadius.card,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? chrome.surfaceHover : Colors.transparent,
              borderRadius: LinearRadius.card,
              border: Border.all(
                color: selected ? chrome.borderStrong : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? chrome.textPrimary : chrome.textTertiary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? chrome.textPrimary : chrome.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
