import '../experience/experience_model.dart';
import 'message_model.dart';

class SessionModel {
  const SessionModel({
    required this.sessionId,
    required this.channel,
    required this.title,
    required this.summary,
    required this.lastMessageAt,
    required this.messageCount,
    required this.pinned,
    required this.archived,
    required this.active,
    this.experienceOverride = const SessionExperienceOverrideModel(),
  });

  final String sessionId;
  final String channel;
  final String title;
  final String summary;
  final String? lastMessageAt;
  final int messageCount;
  final bool pinned;
  final bool archived;
  final bool active;
  final SessionExperienceOverrideModel experienceOverride;

  SessionModel copyWith({
    String? title,
    String? summary,
    String? lastMessageAt,
    int? messageCount,
    bool? pinned,
    bool? archived,
    bool? active,
    SessionExperienceOverrideModel? experienceOverride,
  }) {
    return SessionModel(
      sessionId: sessionId,
      channel: channel,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messageCount: messageCount ?? this.messageCount,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      active: active ?? this.active,
      experienceOverride: experienceOverride ?? this.experienceOverride,
    );
  }

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    final experienceOverride = SessionExperienceOverrideModel.fromJson(json);
    return SessionModel(
      sessionId: json['session_id']?.toString() ?? '',
      channel: json['channel']?.toString() ?? 'app',
      title: json['title']?.toString() ?? 'Untitled session',
      summary: json['summary']?.toString() ?? '',
      lastMessageAt: json['last_message_at']?.toString(),
      messageCount: json['message_count'] is int
          ? json['message_count'] as int
          : int.tryParse(json['message_count']?.toString() ?? '') ?? 0,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      active: json['active'] == true,
      experienceOverride: experienceOverride.hasOverrides
          ? experienceOverride
          : const SessionExperienceOverrideModel(),
    );
  }
}

class MessagePageModel {
  const MessagePageModel({
    required this.items,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
  });

  final List<MessageModel> items;
  final bool hasMoreBefore;
  final bool hasMoreAfter;

  factory MessagePageModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] is List
        ? json['items'] as List<dynamic>
        : const <dynamic>[];
    final pageInfo = json['page_info'] is Map<String, dynamic>
        ? json['page_info'] as Map<String, dynamic>
        : <String, dynamic>{};
    return MessagePageModel(
      items: rawItems
          .map(
            (dynamic item) => MessageModel.fromJson(
              item is Map<String, dynamic> ? item : <String, dynamic>{},
            ),
          )
          .toList(),
      hasMoreBefore: pageInfo['has_more_before'] == true,
      hasMoreAfter: pageInfo['has_more_after'] == true,
    );
  }
}

class PostMessageAcceptedModel {
  const PostMessageAcceptedModel({
    required this.acceptedMessage,
    required this.taskId,
    required this.queued,
  });

  final MessageModel acceptedMessage;
  final String taskId;
  final bool queued;

  factory PostMessageAcceptedModel.fromJson(Map<String, dynamic> json) {
    return PostMessageAcceptedModel(
      acceptedMessage: MessageModel.fromJson(
        json['accepted_message'] is Map<String, dynamic>
            ? json['accepted_message'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      taskId: json['task_id']?.toString() ?? '',
      queued: json['queued'] == true,
    );
  }
}
