import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/task.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/task_provider.dart';
import '../widget/task_tile.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('任务'),
          bottom: TabBar(
            tabs: [
              Tab(text: '待办'),
              Tab(text: '已完成'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // 待办任务列表
            ListView.builder(
              itemCount: tasks.where((t) => !t.isCompleted).length,
              itemBuilder: (context, index) {
                final task = tasks.where((t) => !t.isCompleted).toList()[index];
                return TaskTile(
                  task: task,
                  onToggle: () {
                    // 切换完成状态（可通过 WebSocket 或 API 通知服务端）
                    ref.read(taskProvider.notifier).toggleTask(task.id);
                  },
                );
              },
            ),
            // 已完成任务列表
            ListView.builder(
              itemCount: tasks.where((t) => t.isCompleted).length,
              itemBuilder: (context, index) {
                final task = tasks.where((t) => t.isCompleted).toList()[index];
                return TaskTile(
                  task: task,
                  onToggle: () {
                    ref.read(taskProvider.notifier).toggleTask(task.id);
                  },
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          child: Icon(Icons.add),
          onPressed: () {
            // 弹出对话框创建新任务（简化示例）
            _showAddTaskDialog(context, ref);
          },
        ),
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('新建任务'),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: '任务内容')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(taskProvider.notifier).addTask(controller.text as Task);
                Navigator.pop(ctx);
              }
            },
            child: Text('添加'),
          ),
        ],
      ),
    );
  }
}

extension on Object? {
   Null get isCompleted => null;
}