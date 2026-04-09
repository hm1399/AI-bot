import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'config/routes.dart';
import 'theme/linear_theme.dart';

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
      themeMode: ThemeMode.system,
      theme: LinearTheme.light(),
      darkTheme: LinearTheme.dark(),
      routerConfig: router,
    );
  }
}
