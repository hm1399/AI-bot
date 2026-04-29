import 'package:flutter/material.dart';

import '../../models/chat/message_model.dart';
import '../../theme/linear_tokens.dart';
import 'message_bubble.dart';

class ConversationMessageList extends StatefulWidget {
  const ConversationMessageList({
    required this.sessionId,
    required this.messages,
    super.key,
  });

  final String sessionId;
  final List<MessageModel> messages;

  @override
  State<ConversationMessageList> createState() =>
      _ConversationMessageListState();
}

class _ConversationMessageListState extends State<ConversationMessageList> {
  static const double _stickToBottomThreshold = 96;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    if (widget.messages.isNotEmpty) {
      _scheduleScrollToBottom(jump: true);
    }
  }

  @override
  void didUpdateWidget(covariant ConversationMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final sessionChanged = widget.sessionId != oldWidget.sessionId;
    final previousCount = oldWidget.messages.length;
    final nextCount = widget.messages.length;
    final firstLoadForSession = previousCount == 0 && nextCount > 0;
    final appendedMessages = nextCount > previousCount;
    final shouldFollowNewMessages =
        appendedMessages && _isNearBottomBeforeUpdate();

    if (sessionChanged || firstLoadForSession) {
      _scheduleScrollToBottom(jump: true);
      return;
    }

    if (shouldFollowNewMessages) {
      _scheduleScrollToBottom(jump: false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isNearBottomBeforeUpdate() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <=
        _stickToBottomThreshold;
  }

  void _scheduleScrollToBottom({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        key: ValueKey<String>('conversation-list:${widget.sessionId}'),
        controller: _scrollController,
        padding: const EdgeInsets.all(LinearSpacing.md),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.messages.length,
        itemBuilder: (BuildContext context, int index) {
          return MessageBubble(message: widget.messages[index]);
        },
      ),
    );
  }
}
