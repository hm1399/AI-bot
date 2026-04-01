import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'config/routes.dart';

void main() {
  runApp(const ProviderScope(child: AiBotApp()));
}

class AiBotApp extends ConsumerWidget {
  const AiBotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'AI Bot App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6CBD)),
      ),
      routerConfig: router,
    );
  }
}
