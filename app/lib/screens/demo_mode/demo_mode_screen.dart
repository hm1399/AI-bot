import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DemoModeScreen extends StatelessWidget {
  const DemoModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.bolt_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Demo Mode',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                'The app keeps demo services isolated from the real backend contract.',
                textAlign: TextAlign.center,
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
    );
  }
}
