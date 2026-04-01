import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final location = GoRouterState.of(context).uri.toString();
    final tabs = <({String label, IconData icon, String path})>[
      (label: 'Home', icon: Icons.dashboard_outlined, path: '/app/home'),
      (label: 'Chat', icon: Icons.chat_bubble_outline, path: '/app/chat'),
      (label: 'Tasks', icon: Icons.checklist_outlined, path: '/app/tasks'),
      (label: 'Control', icon: Icons.tune, path: '/app/control'),
      (label: 'Settings', icon: Icons.settings_outlined, path: '/app/settings'),
    ];

    final bannerColor = state.isDemoMode
        ? const Color(0xFFE47E22)
        : state.isConnected && state.eventStreamConnected
        ? const Color(0xFF15803D)
        : state.isConnected
        ? const Color(0xFFCA8A04)
        : const Color(0xFFB91C1C);
    final bannerText = state.isDemoMode
        ? 'Demo Mode'
        : state.isConnected && state.eventStreamConnected
        ? 'Connected'
        : state.isConnected
        ? 'Backend connected · events reconnecting'
        : 'Disconnected';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              width: double.infinity,
              color: bannerColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                bannerText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs
            .indexWhere(
              (({IconData icon, String label, String path}) item) =>
                  location.startsWith(item.path),
            )
            .clamp(0, tabs.length - 1),
        onDestinationSelected: (int index) => context.go(tabs[index].path),
        destinations: tabs
            .map(
              (({IconData icon, String label, String path}) item) =>
                  NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  ),
            )
            .toList(),
      ),
    );
  }
}
