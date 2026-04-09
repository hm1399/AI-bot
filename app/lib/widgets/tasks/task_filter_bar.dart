import 'package:flutter/material.dart';

import '../../theme/linear_tokens.dart';

class TaskFilterBar extends StatelessWidget {
  const TaskFilterBar({
    required this.searchController,
    required this.chips,
    super.key,
  });

  final TextEditingController searchController;
  final List<Widget> chips;

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
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filter by title, summary or location',
            ),
          ),
          const SizedBox(height: LinearSpacing.sm),
          Wrap(
            spacing: LinearSpacing.xs,
            runSpacing: LinearSpacing.xs,
            children: chips,
          ),
        ],
      ),
    );
  }
}
