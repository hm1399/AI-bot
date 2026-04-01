import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'config/routes.dart';      // 确保存在此文件
import 'config/theme.dart';       // 确保存在此文件
import 'service/ws_service.dart'; // 修正为 services

void main() {
  // 初始化 WebSocket 服务（监听网络变化）
  WebSocketService().init();
  
  runApp(
    // 顶层 ProviderScope 必须包裹整个应用
    ProviderScope(
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {  // 改为 ConsumerWidget 以读取 provider
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 从 provider 获取路由配置
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AI Assistant',
      theme: lightTheme,                // 亮色主题
      darkTheme: darkTheme,              // 暗色主题
      themeMode: ThemeMode.system,       // 跟随系统
      routerConfig: router,              // 使用 GoRouter 管理路由
      debugShowCheckedModeBanner: false, // 可选：隐藏调试标志
    );
  }
}