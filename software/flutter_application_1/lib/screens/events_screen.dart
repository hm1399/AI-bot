import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/event_provider.dart';
import '../widget/event_tile.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref, dynamic events) {
    final event = ref.watch(eventProvider);
    
    return Scaffold(
      appBar: AppBar(title: Text('日程')),
      body: ListView.builder(
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          return EventTile(event: event);
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () {
          // 简化：弹出对话框添加日程（略）
        },
      ),
    );
  }
}