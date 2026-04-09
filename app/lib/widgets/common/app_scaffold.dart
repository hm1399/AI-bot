import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../theme/linear_tokens.dart';
import 'app_bottom_dock.dart';
import 'app_shell_header.dart';
import 'app_sidebar.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final location = GoRouterState.of(context).uri.toString();
    final unreadNotifications = state.notifications
        .where((item) => !item.read)
        .length;
    final tabs = <({String label, IconData icon, String path})>[
      (label: 'Home', icon: Icons.dashboard_outlined, path: '/app/home'),
      (label: 'Chat', icon: Icons.chat_bubble_outline, path: '/app/chat'),
      (label: 'Tasks', icon: Icons.checklist_outlined, path: '/app/tasks'),
      (label: 'Control', icon: Icons.tune, path: '/app/control'),
      (label: 'Settings', icon: Icons.settings_outlined, path: '/app/settings'),
    ];
    final currentTab = tabs.firstWhere(
      (item) => location.startsWith(item.path),
      orElse: () => tabs.first,
    );

    Future<void> showConnectionInfo() async {
      final token = state.connection.token.trim();
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Connection Details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Host: ${state.connection.host.isEmpty ? 'Not connected' : state.connection.host}',
                ),
                const SizedBox(height: 8),
                Text('Port: ${state.connection.port}'),
                const SizedBox(height: 8),
                Text(
                  'Transport: ${state.connection.secure ? 'HTTPS / WSS' : 'HTTP / WS'}',
                ),
                const SizedBox(height: 8),
                Text('Token: ${token.isEmpty ? 'Not set' : 'Configured'}'),
                if (state.connection.currentSessionId.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('Session: ${state.connection.currentSessionId}'),
                ],
                if (state.bootstrap != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('Server version: ${state.bootstrap!.serverVersion}'),
                ],
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    }

    Future<void> disconnect() async {
      await ref.read(appControllerProvider.notifier).disconnect();
      if (context.mounted) {
        context.go('/connect');
      }
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final useSidebar = constraints.maxWidth >= 980;
        return Scaffold(
          backgroundColor: context.linear.canvas,
          body: SafeArea(
            child: Container(
              color: context.linear.canvas,
              child: Column(
                children: <Widget>[
                  AppShellHeader(
                    pageTitle: currentTab.label,
                    state: state,
                    unreadNotifications: unreadNotifications,
                    onRefreshAll: ref
                        .read(appControllerProvider.notifier)
                        .refreshAll,
                    onDisconnect: disconnect,
                    onShowConnection: showConnectionInfo,
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        if (useSidebar)
                          AppSidebar(
                            items: tabs,
                            currentPath: location,
                            onSelect: (String path) => context.go(path),
                          ),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.linear.canvas,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  context.linear.canvas,
                                  context.linear.panel.withOpacity(0.48),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                useSidebar
                                    ? LinearSpacing.xl
                                    : LinearSpacing.md,
                                LinearSpacing.md,
                                useSidebar
                                    ? LinearSpacing.xl
                                    : LinearSpacing.md,
                                useSidebar
                                    ? LinearSpacing.xl
                                    : LinearSpacing.md,
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: useSidebar
              ? null
              : AppBottomDock(
                  items: tabs,
                  currentPath: location,
                  onSelect: (String path) => context.go(path),
                ),
        );
      },
    );
  }
}
