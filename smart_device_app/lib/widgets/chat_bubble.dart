import 'package:flutter/material.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final bool showTimestamp;
  
  const ChatBubble({
    Key? key,
    required this.message,
    this.showTimestamp = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final isDeviceMessage = message.source == MessageSource.device;
    final isSystemMessage = message.type == MessageType.system;
    final isError = message.type == MessageType.error;
    final isToolResult = message.type == MessageType.toolResult;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      alignment: isDeviceMessage ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: isDeviceMessage 
            ? CrossAxisAlignment.start 
            : CrossAxisAlignment.end,
        children: [
          if (showTimestamp)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                _formatTimestamp(message.timestamp),
                style: TextStyle(
                  fontSize: 12.0,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          if (isSystemMessage)
            _buildSystemMessage(context)
          else if (isError)
            _buildErrorMessage(context)
          else if (isToolResult)
            _buildToolResultMessage(context)
          else
            _buildRegularMessage(context, isDeviceMessage),
        ],
      ),
    );
  }
  
  Widget _buildRegularMessage(BuildContext context, bool isDeviceMessage) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: isDeviceMessage
            ? Theme.of(context).colorScheme.surfaceVariant
            : Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16.0),
          topRight: const Radius.circular(16.0),
          bottomLeft: isDeviceMessage 
              ? const Radius.circular(4.0) 
              : const Radius.circular(16.0),
          bottomRight: isDeviceMessage 
              ? const Radius.circular(16.0) 
              : const Radius.circular(4.0),
        ),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: isDeviceMessage
              ? Theme.of(context).textTheme.bodyLarge?.color
              : Colors.white,
        ),
      ),
    );
  }
  
  Widget _buildSystemMessage(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      ),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.7),
        borderRadius: const BorderRadius.all(Radius.circular(8.0)),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          fontSize: 14.0,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
  
  Widget _buildErrorMessage(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      ),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
  
  Widget _buildToolResultMessage(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
      ),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '工具执行结果',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            message.content,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final isToday = timestamp.year == now.year && 
                   timestamp.month == now.month && 
                   timestamp.day == now.day;
    
    if (isToday) {
      return '今天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}-${timestamp.day} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}