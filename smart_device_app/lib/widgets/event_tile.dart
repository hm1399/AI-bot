import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/event.dart';

class EventTile extends StatelessWidget {
  final Event event;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  
  const EventTile({
    Key? key,
    required this.event,
    this.onTap,
    this.onEdit,
    this.onDelete,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: Key(event.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => onEdit?.call(),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.edit,
            label: '编辑',
          ),
          SlidableAction(
            onPressed: (_) => onDelete?.call(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
          ),
        ],
      ),
      child: ListTile(
        leading: _buildEventIcon(context),
        title: Text(
          event.title,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        subtitle: _buildSubtitle(context),
        onTap: onTap,
      ),
    );
  }
  
  Widget _buildEventIcon(BuildContext context) {
    return Container(
      width: 48.0,
      height: 48.0,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Icon(
        event.isAllDay ? Icons.event : Icons.schedule,
        color: Theme.of(context).colorScheme.primary,
        size: 24.0,
      ),
    );
  }
  
  Widget? _buildSubtitle(BuildContext context) {
    final List<Widget> parts = [];
    
    // 时间信息
    parts.add(
      Text(
        _formatEventTime(event),
        style: TextStyle(
          color: Theme.of(context).textTheme.bodySmall?.color,
          fontSize: 12.0,
        ),
      ),
    );
    
    // 描述信息
    if (event.description != null && event.description!.isNotEmpty) {
      parts.add(const SizedBox(width: 8.0));
      parts.add(
        Flexible(
          child: Text(
            event.description!,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 12.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    
    if (parts.isEmpty) {
      return null;
    }
    
    return Row(
      children: parts,
    );
  }
  
  String _formatEventTime(Event event) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));
    
    final startDate = DateTime(event.startTime.year, event.startTime.month, event.startTime.day);
    
    String dateText;
    
    if (startDate.year == today.year && 
        startDate.month == today.month && 
        startDate.day == today.day) {
      dateText = '今天';
    } else if (startDate.year == tomorrow.year && 
               startDate.month == tomorrow.month && 
               startDate.day == tomorrow.day) {
      dateText = '明天';
    } else if (startDate.year == yesterday.year && 
               startDate.month == yesterday.month && 
               startDate.day == yesterday.day) {
      dateText = '昨天';
    } else if (startDate.year == now.year) {
      dateText = '${startDate.month}-${startDate.day}';
    } else {
      dateText = '${startDate.year}-${startDate.month}-${startDate.day}';
    }
    
    if (event.isAllDay) {
      return '$dateText (全天)';
    } else {
      final startTime = '${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}';
      final endTime = '${event.endTime.hour.toString().padLeft(2, '0')}:${event.endTime.minute.toString().padLeft(2, '0')}';
      
      // 如果是同一天的事件
      if (event.startTime.year == event.endTime.year &&
          event.startTime.month == event.endTime.month &&
          event.startTime.day == event.endTime.day) {
        return '$dateText $startTime-$endTime';
      } else {
        // 如果跨天
        final endDate = DateTime(event.endTime.year, event.endTime.month, event.endTime.day);
        String endDateText;
        
        if (endDate.year == today.year && 
            endDate.month == today.month && 
            endDate.day == today.day) {
          endDateText = '今天';
        } else if (endDate.year == tomorrow.year && 
                   endDate.month == tomorrow.month && 
                   endDate.day == tomorrow.day) {
          endDateText = '明天';
        } else if (endDate.year == yesterday.year && 
                   endDate.month == yesterday.month && 
                   endDate.day == yesterday.day) {
          endDateText = '昨天';
        } else if (endDate.year == now.year) {
          endDateText = '${endDate.month}-${endDate.day}';
        } else {
          endDateText = '${endDate.year}-${endDate.month}-${endDate.day}';
        }
        
        return '$dateText $startTime - $endDateText $endTime';
      }
    }
  }
}