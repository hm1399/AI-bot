import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/connect_screen.dart';
import '../screens/home_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/events_screen.dart';
import '../screens/settings_screen.dart';
import '../providers/config_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(configProvider);
  final hasServerConfig = config.serverIp.isNotEmpty && config.serverPort != 0;
  
  return GoRouter(
    initialLocation: hasServerConfig ? '/home' : '/connect',
    routes: [
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/tasks',
        builder: (context, state) => const TasksScreen(),
      ),
      GoRoute(
        path: '/events',
        builder: (context, state) => const EventsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('错误: ${state.error}'),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    ),
  );
});