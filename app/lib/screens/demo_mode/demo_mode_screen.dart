import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/linear_tokens.dart';
import '../../widgets/common/status_pill.dart';

class DemoModeScreen extends StatelessWidget {
  const DemoModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = context.linear;
    return Scaffold(
      backgroundColor: chrome.canvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: chrome.surface,
              borderRadius: LinearRadius.panel,
              border: Border.all(color: chrome.borderStandard),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const StatusPill(
                  label: 'Demo Route',
                  tone: StatusPillTone.accent,
                  icon: Icons.bolt_outlined,
                ),
                const SizedBox(height: 16),
                Text(
                  'Demo Mode',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'The app keeps demo services isolated from the real backend contract.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: chrome.textTertiary),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/connect'),
                  child: const Text('Back to Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
