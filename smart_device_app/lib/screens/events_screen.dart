import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/event_provider.dart';
import '../models/event.dart';
import '../widgets/event_tile.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  TextEditingController _titleController = TextEditingController();
  TextEditingController _descriptionController = TextEditingController();
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;
  bool _isAllDay = false;

  @override
  void initState() {
    super.initState();
    // 初始加载事件列表
    ref.read(eventProvider.notifier).loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final eventState = ref.watch(eventProvider);
    final eventNotifier = ref.read(eventProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        elevation: 0,
      ),
      body: SafeArea(
        child: eventState.isLoading && eventState.events.isEmpty
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : eventState.events.isEmpty
                ? _buildEmptyState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 即将到来的事件
                        _buildUpcomingEvents(
                          context,
                          '即将到来的日程',
                          eventState.events,
                          eventNotifier,
                        ),
                        
                        // 所有事件
                        _buildAllEvents(
                          context,
                          '所有日程',
                          eventState.events,
                          eventNotifier,
                        ),
                      ],
                    ),
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventDialog(),
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
            Icons.event_outlined,
            size: 64.0,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16.0),
          Text(
            '暂无日程',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
          const SizedBox(height: 8.0),
          Text(
            '点击右下角按钮添加日程',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEvents(
    BuildContext context,
    String title,
    List<Event> events,
    EventNotifier eventNotifier,
  ) {
    final now = DateTime.now();
    final upcomingEvents = events
        .where((event) => event.startTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    
    // 只显示最近的5个事件
    final recentEvents = upcomingEvents.take(5).toList();
    
    if (recentEvents.isEmpty) {
      return Container();
    }
    
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
                ...recentEvents.map((event) => EventTile(
                      event: event,
                      onTap: () => _showEventDetails(event),
                      onEdit: () => _showEditEventDialog(event),
                      onDelete: () => _showDeleteEventConfirmation(event),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAllEvents(
    BuildContext context,
    String title,
    List<Event> events,
    EventNotifier eventNotifier,
  ) {
    // 按日期排序事件
    final sortedEvents = List<Event>.from(events)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    
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
                ...sortedEvents.map((event) => EventTile(
                      event: event,
                      onTap: () => _showEventDetails(event),
                      onEdit: () => _showEditEventDialog(event),
                      onDelete: () => _showDeleteEventConfirmation(event),
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
      currentIndex: 2, // 任务/日程
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

  void _showEventDetails(Event event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (event.description != null && event.description!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '描述:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(event.description!),
                    const SizedBox(height: 16.0),
                  ],
                ),
              Text(
                '时间:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_formatEventTime(event)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showAddEventDialog() {
    _resetForm();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加日程'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '日程标题',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '日程描述 (可选)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16.0),
                SwitchListTile(
                  title: const Text('全天事件'),
                  value: _isAllDay,
                  onChanged: (value) {
                    setState(() {
                      _isAllDay = value;
                    });
                  },
                ),
                const SizedBox(height: 16.0),
                Text('开始时间:'),
                const SizedBox(height: 8.0),
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
                              _startDate = date;
                              if (_endDate == null || _endDate!.isBefore(date)) {
                                _endDate = date;
                              }
                            });
                          }
                        },
                        child: Text(
                          _startDate != null
                              ? '日期: ${_startDate!.month}-${_startDate!.day}'
                              : '选择日期',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _startDate != null && !_isAllDay
                            ? () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() {
                                    _startTime = time;
                                  });
                                }
                              }
                            : null,
                        child: Text(
                          _startTime != null
                              ? '时间: ${_startTime!.format(context)}'
                              : _isAllDay ? '全天' : '选择时间',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Text('结束时间:'),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? _startDate ?? DateTime.now(),
                            firstDate: _startDate ?? DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _endDate = date;
                            });
                          }
                        },
                        child: Text(
                          _endDate != null
                              ? '日期: ${_endDate!.month}-${_endDate!.day}'
                              : '选择日期',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _endDate != null && !_isAllDay
                            ? () async {
                                final initialTime = _startTime != null
                                    ? TimeOfDay(
                                        hour: _startTime!.hour + 1,
                                        minute: _startTime!.minute,
                                      )
                                    : TimeOfDay.now();
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: initialTime,
                                );
                                if (time != null) {
                                  setState(() {
                                    _endTime = time;
                                  });
                                }
                              }
                            : null,
                        child: Text(
                          _endTime != null
                              ? '时间: ${_endTime!.format(context)}'
                              : _isAllDay ? '全天' : '选择时间',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
              _saveEvent();
              Navigator.pop(context);
              _resetForm();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showEditEventDialog(Event event) {
    _titleController.text = event.title;
    _descriptionController.text = event.description ?? '';
    _isAllDay = event.isAllDay;
    
    _startDate = DateTime(
      event.startTime.year,
      event.startTime.month,
      event.startTime.day,
    );
    
    if (!event.isAllDay) {
      _startTime = TimeOfDay.fromDateTime(event.startTime);
    } else {
      _startTime = null;
    }
    
    _endDate = DateTime(
      event.endTime.year,
      event.endTime.month,
      event.endTime.day,
    );
    
    if (!event.isAllDay) {
      _endTime = TimeOfDay.fromDateTime(event.endTime);
    } else {
      _endTime = null;
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('编辑日程'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '日程标题',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16.0),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '日程描述 (可选)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16.0),
                SwitchListTile(
                  title: const Text('全天事件'),
                  value: _isAllDay,
                  onChanged: (value) {
                    setState(() {
                      _isAllDay = value;
                    });
                  },
                ),
                const SizedBox(height: 16.0),
                Text('开始时间:'),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _startDate = date;
                              if (_endDate == null || _endDate!.isBefore(date)) {
                                _endDate = date;
                              }
                            });
                          }
                        },
                        child: Text(
                          _startDate != null
                              ? '日期: ${_startDate!.month}-${_startDate!.day}'
                              : '选择日期',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _startDate != null && !_isAllDay
                            ? () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: _startTime ?? TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() {
                                    _startTime = time;
                                  });
                                }
                              }
                            : null,
                        child: Text(
                          _startTime != null
                              ? '时间: ${_startTime!.format(context)}'
                              : _isAllDay ? '全天' : '选择时间',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Text('结束时间:'),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? _startDate ?? DateTime.now(),
                            firstDate: _startDate ?? DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _endDate = date;
                            });
                          }
                        },
                        child: Text(
                          _endDate != null
                              ? '日期: ${_endDate!.month}-${_endDate!.day}'
                              : '选择日期',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _endDate != null && !_isAllDay
                            ? () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: _endTime ?? 
                                      (_startTime != null 
                                          ? TimeOfDay(
                                              hour: _startTime!.hour + 1,
                                              minute: _startTime!.minute,
                                            )
                                          : TimeOfDay.now()),
                                );
                                if (time != null) {
                                  setState(() {
                                    _endTime = time;
                                  });
                                }
                              }
                            : null,
                        child: Text(
                          _endTime != null
                              ? '时间: ${_endTime!.format(context)}'
                              : _isAllDay ? '全天' : '选择时间',
                        ),
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
                _updateEvent(event);
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

  void _saveEvent() {
    if (_titleController.text.trim().isEmpty || _startDate == null || _endDate == null) {
      return;
    }
    
    DateTime startTime;
    DateTime endTime;
    
    if (_isAllDay) {
      startTime = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      endTime = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
    } else {
      final startHour = _startTime?.hour ?? 0;
      final startMinute = _startTime?.minute ?? 0;
      final endHour = _endTime?.hour ?? startHour + 1;
      final endMinute = _endTime?.minute ?? startMinute;
      
      startTime = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        startHour,
        startMinute,
      );
      
      endTime = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        endHour,
        endMinute,
      );
      
      // 确保结束时间晚于开始时间
      if (endTime.isBefore(startTime)) {
        endTime = startTime.add(const Duration(hours: 1));
      }
    }
    
    ref.read(eventProvider.notifier).createEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startTime: startTime,
          endTime: endTime,
          isAllDay: _isAllDay,
        );
  }

  void _updateEvent(Event event) {
    if (_titleController.text.trim().isEmpty || _startDate == null || _endDate == null) {
      return;
    }
    
    DateTime startTime;
    DateTime endTime;
    
    if (_isAllDay) {
      startTime = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      endTime = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
    } else {
      final startHour = _startTime?.hour ?? 0;
      final startMinute = _startTime?.minute ?? 0;
      final endHour = _endTime?.hour ?? startHour + 1;
      final endMinute = _endTime?.minute ?? startMinute;
      
      startTime = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
        startHour,
        startMinute,
      );
      
      endTime = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        endHour,
        endMinute,
      );
      
      // 确保结束时间晚于开始时间
      if (endTime.isBefore(startTime)) {
        endTime = startTime.add(const Duration(hours: 1));
      }
    }
    
    final updatedEvent = event.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      startTime: startTime,
      endTime: endTime,
      isAllDay: _isAllDay,
    );
    
    ref.read(eventProvider.notifier).updateEvent(updatedEvent);
  }

  void _resetForm() {
    _titleController.clear();
    _descriptionController.clear();
    _startDate = null;
    _startTime = null;
    _endDate = null;
    _endTime = null;
    _isAllDay = false;
  }

  void _showDeleteEventConfirmation(Event event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日程'),
        content: Text('确定要删除日程"${event.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(eventProvider.notifier).deleteEvent(event.id);
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

  String _formatEventTime(Event event) {
    if (event.isAllDay) {
      if (event.startTime.year == event.endTime.year &&
          event.startTime.month == event.endTime.month &&
          event.startTime.day == event.endTime.day) {
        return '${event.startTime.year}-${event.startTime.month}-${event.startTime.day} (全天)';
      } else {
        return '${event.startTime.year}-${event.startTime.month}-${event.startTime.day} 至 ${event.endTime.year}-${event.endTime.month}-${event.endTime.day} (全天)';
      }
    } else {
      final startTime = '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}';
      final endTime = '${event.endTime.hour.toString().padLeft(2, '0')}:${event.endTime.minute.toString().padLeft(2, '0')}';
      
      if (event.startTime.year == event.endTime.year &&
          event.startTime.month == event.endTime.month &&
          event.startTime.day == event.endTime.day) {
        return '${event.startTime.year}-${event.startTime.month}-${event.startTime.day} $startTime-$endTime';
      } else {
        return '${event.startTime.year}-${event.startTime.month}-${event.startTime.day} $startTime 至 ${event.endTime.year}-${event.endTime.month}-${event.endTime.day} $endTime';
      }
    }
  }
}