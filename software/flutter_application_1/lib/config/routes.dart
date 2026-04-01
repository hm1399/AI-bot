import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../screens/home_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/events_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/connect_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/connect',
    routes: [
      GoRoute(
        path: '/connect',
        name: 'connect',
        builder: (context, state) => ConnectScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return ScaffoldWithNavBar(child: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => HomeScreen(),
          ),
          GoRoute(
            path: '/chat',
            name: 'chat',
            builder: (context, state) => ChatScreen(),
          ),
          GoRoute(
            path: '/tasks',
            name: 'tasks',
            builder: (context, state) => TasksScreen(),
          ),
          GoRoute(
            path: '/events',
            name: 'events',
            builder: (context, state) => EventsScreen(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

class ScaffoldWithNavBar extends ConsumerWidget {
  final Widget child;
  const ScaffoldWithNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _getCurrentIndex(context),
        onTap: (index) {
          switch (index) {
            case 0: context.go('/home'); break;
            case 1: context.go('/chat'); break;
            case 2: context.go('/tasks'); break;
            case 3: context.go('/events'); break;
            case 4: context.go('/settings'); break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '对话'),
          BottomNavigationBarItem(icon: Icon(Icons.task), label: '任务'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '日程'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/chat')) return 1;
    if (location.startsWith('/tasks')) return 2;
    if (location.startsWith('/events')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }
}