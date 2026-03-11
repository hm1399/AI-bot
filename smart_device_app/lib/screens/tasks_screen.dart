import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/task_provider.dart';
import '../models/task.dart';
import '../widgets/task_tile.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  TaskPriority _selectedPriority = TaskPriority.medium;
  TextEditingController _titleController = TextEditingController();
  TextEditingController _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    // 初始加载任务列表
    ref.read(taskProvider.notifier).loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskProvider);
    final taskNotifier = ref.read(taskProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        elevation: 0,
        actions: [
          if (taskState.completedTasks.isNotEmpty)
            TextButton(
              onPressed: () => _showClearCompletedConfirmation(),
              child: Text(
                '清除已完成',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: taskState.isLoading && taskState.tasks.isEmpty
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : taskState.tasks.isEmpty
                ? _buildEmptyState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 待办任务
                        _buildTasksSection(
                          context,
                          '待办任务',
                          taskState.tasksByPriority,
                          taskNotifier,
                        ),
                        
                        // 已完成任务
                        if (taskState.completedTasks.isNotEmpty)
                          _buildCompletedTasksSection(
                            context,
                            '已完成任务',
                            taskState.completedTasks,
                            taskNotifier,
                          ),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTaskDialog(),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.task_outlined,
            size: 64.0,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16.0),
          Text(
            '暂无任务',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
          const SizedBox(height: 8.0),
          Text(
            '点击右下角按钮添加任务',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksSection(
    BuildContext context,
    String title,
    Map<TaskPriority, List<Task>> tasksByPriority,
    TaskNotifier taskNotifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16.0),
        
        // 高优先级任务
        if (tasksByPriority[TaskPriority.high]!.isNotEmpty)
          _buildPriorityTasks(
            context,
            '高优先级',
            tasksByPriority[TaskPriority.high]!,
            taskNotifier,
            Colors.red,
          ),
        
        // 中优先级任务
        if (tasksByPriority[TaskPriority.medium]!.isNotEmpty)
          _buildPriorityTasks(
            context,
            '中优先级',
            tasksByPriority[TaskPriority.medium]!,
            taskNotifier,
            Colors.orange,
          ),
        
        // 低优先级任务
        if (tasksByPriority[TaskPriority.low]!.isNotEmpty)
          _buildPriorityTasks(
            context,
            '低优先级',
            tasksByPriority[TaskPriority.low]!,
            taskNotifier,
            Colors.green,
          ),
      ],
    );
  }

  Widget _buildPriorityTasks(
    BuildContext context,
    String title,
    List<Task> tasks,
    TaskNotifier taskNotifier,
    Color color,
  ) {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4.0,
                  height: 20.0,
                  color: color,
                  margin: const EdgeInsets.only(right: 8.0),
                ),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${tasks.length} 个任务',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            ...tasks.map((task) => TaskTile(
                  task: task,
                  onToggleComplete: () => taskNotifier.toggleTaskCompletion(task.id),
                  onEdit: () => _showEditTaskDialog(task),
                  onDelete: () => _showDeleteTaskConfirmation(task),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedTasksSection(
    BuildContext context,
    String title,
    List<Task> tasks,
    TaskNotifier taskNotifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24.0),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16.0),
        Card(
          elevation: 2.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...tasks.map((task) => TaskTile(
                      task: task,
                      onToggleComplete: () => taskNotifier.toggleTaskCompletion(task.id),
                      onEdit: () => _showEditTaskDialog(task),
                      onDelete: () => _showDeleteTaskConfirmation(task),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 2, // 任务
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/home');
            break;
          case 1:
            context.go('/chat');
            break;
          case 2:
            context.go('/tasks');
            break;
          case 3:
            context.go('/settings');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: '首页',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat),
          label: '对话',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.task),
          label: '任务',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }

  void _showAddTaskDialog() {
    _resetForm();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加任务'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '任务标题',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '任务描述 (可选)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _selectedDate = date;
                            });
                          }
                        },
                        child: Text(
                          _selectedDate != null
                              ? '日期: ${_selectedDate!.month}-${_selectedDate!.day}'
                              : '选择日期',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _selectedDate != null
                            ? () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() {
                                    _selectedTime = time;
                                  });
                                }
                              }
                            : null,
                        child: Text(
                          _selectedTime != null
                              ? '时间: ${_selectedTime!.format(context)}'
                              : '选择时间',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Text('优先级:'),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile(
                        title: const Text('低'),
                        value: TaskPriority.low,
                        groupValue: _selectedPriority,
                        onChanged: (value) {
                          setState(() {
                            _selectedPriority = value as TaskPriority;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile(
                        title: const Text('中'),
                        value: TaskPriority.medium,
                        groupValue: _selectedPriority,
                        onChanged: (value) {
                          setState(() {
                            _selectedPriority = value as TaskPriority;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile(
                        title: const Text('高'),
                        value: TaskPriority.high,
                        groupValue: _selectedPriority,
                        onChanged: (value) {
                          setState(() {
                            _selectedPriority = value as TaskPriority;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetForm();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                _saveTask();
                Navigator.pop(context);
                _resetForm();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTaskDialog(Task task) {
    _titleController.text = task.title;
    _descriptionController.text = task.description ?? '';
    _selectedPriority = task.priority;
    
    if (task.dueDate != null) {
      _selectedDate = DateTime(
        task.dueDate!.year,
        task.dueDate!.month,
        task.dueDate!.day,
      );
      _selectedTime = TimeOfDay.fromDateTime(task.dueDate!);
    } else {
      _selectedDate = null;
      _selectedTime = null;
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('编辑任务'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '任务标题',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '任务描述 (可选)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _selectedDate = date;
                            });
                          }
                        },
                        child: Text(
                          _selectedDate != null
                              ? '日期: ${_selectedDate!.month}-${_selectedDate!.day}'
                              : '选择日期',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _selectedDate != null
                            ? () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: _selectedTime ?? TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() {
                                    _selectedTime = time;
                                  });
                                }
                              }
                            : null,
                        child: Text(
                          _selectedTime != null
                              ? '时间: ${_selectedTime!.format(context)}'
                              : '选择时间',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Text('优先级:'),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile(
                        title: const Text('低'),
                        value: TaskPriority.low,
                        groupValue: _selectedPriority,
                        onChanged: (value) {
                          setState(() {
                            _selectedPriority = value as TaskPriority;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile(
                        title: const Text('中'),
                        value: TaskPriority.medium,
                        groupValue: _selectedPriority,
                        onChanged: (value) {
                          setState(() {
                            _selectedPriority = value as TaskPriority;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile(
                        title: const Text('高'),
                        value: TaskPriority.high,
                        groupValue: _selectedPriority,
                        onChanged: (value) {
                          setState(() {
                            _selectedPriority = value as TaskPriority;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetForm();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                _updateTask(task);
                Navigator.pop(context);
                _resetForm();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveTask() {
    if (_titleController.text.trim().isEmpty) return;
    
    DateTime? dueDate;
    if (_selectedDate != null) {
      if (_selectedTime != null) {
        dueDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
      } else {
        dueDate = _selectedDate;
      }
    }
    
    ref.read(taskProvider.notifier).createTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          dueDate: dueDate,
          priority: _selectedPriority,
        );
  }

  void _updateTask(Task task) {
    if (_titleController.text.trim().isEmpty) return;
    
    DateTime? dueDate;
    if (_selectedDate != null) {
      if (_selectedTime != null) {
        dueDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
      } else {
        dueDate = _selectedDate;
      }
    }
    
    final updatedTask = task.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      dueDate: dueDate,
      priority: _selectedPriority,
    );
    
    ref.read(taskProvider.notifier).updateTask(updatedTask);
  }

  void _resetForm() {
    _titleController.clear();
    _descriptionController.clear();
    _selectedDate = null;
    _selectedTime = null;
    _selectedPriority = TaskPriority.medium;
  }

  void _showDeleteTaskConfirmation(Task task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定要删除任务"${task.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(taskProvider.notifier).deleteTask(task.id);
            },
            child: const Text('删除'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCompletedConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除已完成任务'),
        content: const Text('确定要清除所有已完成的任务吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(taskProvider.notifier).clearCompletedTasks();
            },
            child: const Text('清除'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}