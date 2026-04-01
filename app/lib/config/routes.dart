import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../screens/chat/chat_screen.dart';
import '../screens/connect/connect_screen.dart';
import '../screens/control_center/control_center_screen.dart';
import '../screens/demo_mode/demo_mode_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/tasks/tasks_screen.dart';
import '../widgets/common/app_scaffold.dart';

final routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    initialLocation: '/connect',
    routes: <RouteBase>[
      GoRoute(
        path: '/connect',
        builder: (BuildContext context, GoRouterState state) =>
            const ConnectScreen(),
      ),
      GoRoute(
        path: '/demo',
        builder: (BuildContext context, GoRouterState state) =>
            const DemoModeScreen(),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return AppScaffold(child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/app/home',
            builder: (BuildContext context, GoRouterState state) =>
                const HomeScreen(),
          ),
          GoRoute(
            path: '/app/chat',
            builder: (BuildContext context, GoRouterState state) =>
                const ChatScreen(),
          ),
          GoRoute(
            path: '/app/tasks',
            builder: (BuildContext context, GoRouterState state) =>
                const TasksScreen(),
          ),
          GoRoute(
            path: '/app/control',
            builder: (BuildContext context, GoRouterState state) =>
                const ControlCenterScreen(),
          ),
          GoRoute(
            path: '/app/settings',
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
