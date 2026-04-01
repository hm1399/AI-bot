import 'package:flutter/material.dart';
import '../models/event.dart';

class EventTile extends StatelessWidget {
  final Event event;
  const EventTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.event),
      title: Text(event.title),
      subtitle: Text('${event.startTime} - ${event.endTime}'),
    );
  }
}