import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';

/// Opens [location]. On wide layouts pages replace each other beside the
/// rail and sidebar; on phones they stack, so back returns here.
void openPage(BuildContext context, String location, {Object? extra}) {
  if (isWideLayout(MediaQuery.sizeOf(context).width)) {
    context.go(location, extra: extra);
  } else {
    context.push(location, extra: extra);
  }
}

/// A circle's page, optionally with one of its channels (or a channel
/// thread) open.
String circleLocation(String circleId, {String? conversationId}) {
  return Uri(
    path: '${CircleRoutes.path}/$circleId',
    queryParameters: conversationId == null ? null : {'c': conversationId},
  ).toString();
}

/// Opens [conversation] where it lives: circle channels and their threads
/// inside the circle, other chats under the direct messages.
void openConversation(BuildContext context, ConversationSummary conversation) {
  final title = conversation.title?.trim().isNotEmpty == true
      ? conversation.title!
      : conversation.isThread
      ? 'Thread'
      : 'Conversation';
  final circleId = conversation.circleId;
  if (circleId != null) {
    if (isWideLayout(MediaQuery.sizeOf(context).width)) {
      context.go(circleLocation(circleId, conversationId: conversation.id));
      return;
    }
    context.push(
      CircleChannelThreadScreen.pathFor(circleId, conversation.id),
      extra: ChatThreadRouteExtra(
        title: conversation.isThread ? title : '# $title',
        type: conversation.isThread
            ? ConversationType.thread
            : ConversationType.channel,
        circleId: circleId,
      ),
    );
    return;
  }
  openPage(
    context,
    '${ChatsScreen.path}/${conversation.id}',
    extra: ChatThreadRouteExtra(
      title: title,
      type: conversation.type,
      avatarUrl: conversation.avatarUrl,
    ),
  );
}
