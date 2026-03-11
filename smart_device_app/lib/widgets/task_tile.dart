import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/task.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback? onToggleComplete;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  
  const TaskTile({
    Key? key,
    required this.task,
    this.onToggleComplete,
    this.onEdit,
    this.onDelete,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: Key(task.id),
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
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (_) => onToggleComplete?.call(),
          activeColor: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted 
                ? Theme.of(context).disabledColor 
                : Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        subtitle: _buildSubtitle(context),
        trailing: _buildPriorityIndicator(context),
        onTap: onToggleComplete,
      ),
    );
  }
  
  Widget? _buildSubtitle(BuildContext context) {
    final List<Widget> parts = [];
    
    if (task.description != null && task.description!.isNotEmpty) {
      parts.add(
        Text(
          task.description!,
          style: TextStyle(
            color: task.isCompleted 
                ? Theme.of(context).disabledColor 
                : Theme.of(context).textTheme.bodySmall?.color,
            fontSize: 12.0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    
    if (task.dueDate != null) {
      if (parts.isNotEmpty) {
        parts.add(const SizedBox(width: 8.0));
      }
      
      final isOverdue = task.dueDate!.isBefore(DateTime.now()) && !task.isCompleted;
      
      parts.add(
        Text(
          _formatDueDate(task.dueDate!),
          style: TextStyle(
            color: isOverdue 
                ? Theme.of(context).colorScheme.error 
                : (task.isCompleted 
                    ? Theme.of(context).disabledColor 
                    : Theme.of(context).textTheme.bodySmall?.color),
            fontSize: 12.0,
            fontWeight: isOverdue ? FontWeight.bold : null,
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
  
  Widget _buildPriorityIndicator(BuildContext context) {
    Color color;
    String text;
    
    switch (task.priority) {
      case TaskPriority.high:
        color = Colors.red;
        text = '高';
        break;
      case TaskPriority.medium:
        color = Colors.orange;
        text = '中';
        break;
      case TaskPriority.low:
        color = Colors.green;
        text = '低';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  String _formatDueDate(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));
    
    if (dueDate.year == today.year && 
        dueDate.month == today.month && 
        dueDate.day == today.day) {
      return '今天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    } else if (dueDate.year == tomorrow.year && 
               dueDate.month == tomorrow.month && 
               dueDate.day == tomorrow.day) {
      return '明天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    } else if (dueDate.year == yesterday.year && 
               dueDate.month == yesterday.month && 
               dueDate.day == yesterday.day) {
      return '昨天 ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    } else if (dueDate.year == now.year) {
      return '${dueDate.month}-${dueDate.day} ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dueDate.year}-${dueDate.month}-${dueDate.day}';
    }
  }
}