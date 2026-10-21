import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/circles/channel_types/channel_types_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/forum.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

import '../../mobile/phone_test_support.dart';

/// The ids of the two channels this feature adds to the sample circle.
const galleryChannelId = 'ch-gallery';
const galleryConversationId = 'conv-gallery';
const askChannelId = 'ch-ask';
const askConversationId = 'conv-ask';

/// The Q&A post the thread tests open, and its messages.
const askPostId = 'q-open';
const askPostConversationId = 'q-open-conv';
const askQuestionId = 'qm-1';
const askAnswerId = 'qm-2';
const askOtherAnswerId = 'qm-3';

/// Answers the database functions of Q&A channels. Solving or reopening
/// changes what the next read says, as the server would; unknown functions
/// fail, as an uninitialized Supabase client would.
class QaRpc {
  QaRpc({this.canMark = true, List<Map<String, dynamic>>? posts})
    : posts = posts ?? qaPostsJson();

  /// The sample post's mark, as get_qa_post_state would say it.
  bool solved = false;
  String? answerMessageId;
  bool canMark;

  /// The posts list_qa_posts answers from (it applies the status filter).
  List<Map<String, dynamic>> posts;
  final calls = <(String, Map<String, dynamic>)>[];

  /// Makes the next call to this function fail.
  final failing = <String>{};

  CircleRpc get call => _call;

  Map<String, dynamic> get state => {
    'thread_id': askPostId,
    'channel_id': askChannelId,
    'circle_id': 'circle-1',
    'solved': solved,
    'solved_at': solved ? '2026-10-21T08:00:00Z' : null,
    'answer_message_id': answerMessageId,
    'opening_message_id': askQuestionId,
    'can_mark': canMark,
  };

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    if (failing.contains(name)) {
      throw StateError('offline');
    }
    switch (name) {
      case 'get_qa_post_state':
        return params['target_conversation_id'] == askPostConversationId
            ? state
            : null;
      case 'mark_post_solved':
        solved = true;
        answerMessageId = params['answer_message_id'] as String?;
        return state;
      case 'reopen_qa_post':
        solved = false;
        answerMessageId = null;
        return state;
      case 'list_qa_posts':
        final status = params['filter_status'] as String? ?? 'all';
        return [
          for (final post in posts)
            if (status == 'all' ||
                (status == 'solved') == (post['solved_at'] != null))
              post,
        ];
    }
    throw StateError('Unexpected $name');
  }

  List<Map<String, dynamic>> paramsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];

  List<Override> get overrides => [
    channelTypesRepositoryProvider.overrideWithValue(
      ChannelTypesRepository(call),
    ),
  ];
}

Map<String, dynamic> _qaPostJson(
  String id,
  String title,
  Profile author, {
  required int createdMinutesAgo,
  required int activeMinutesAgo,
  required String body,
  int replies = 0,
  int unread = 0,
  bool pinned = false,
  bool solved = false,
  String? answerId,
}) => {
  'id': id,
  'conversation_id': id == askPostId ? askPostConversationId : '$id-conv',
  'channel_id': askChannelId,
  'title': title,
  'created_by': author.id,
  'created_at': minutesAgo(createdMinutesAgo).toUtc().toIso8601String(),
  'last_activity_at': minutesAgo(activeMinutesAgo).toUtc().toIso8601String(),
  'is_pinned': pinned,
  'author': {
    'id': author.id,
    'username': author.username,
    'display_name': author.displayName,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  },
  'tags': <Map<String, dynamic>>[],
  'opening_message': {
    'id': 'op-$id',
    'type': 'text',
    'body': body,
    'recalled': false,
  },
  'reply_count': replies,
  'unread_count': unread,
  'thumbnail': null,
  'can_manage': true,
  'solved_at': solved
      ? minutesAgo(activeMinutesAgo).toUtc().toIso8601String()
      : null,
  'solved_message_id': answerId,
};

/// Questions of the sample Q&A channel: an open one, a solved one with an
/// accepted answer and a pinned house-rules post.
List<Map<String, dynamic>> qaPostsJson() => [
  _qaPostJson(
    'q-rules',
    'Read me first: how to ask well',
    bart,
    createdMinutesAgo: 9000,
    activeMinutesAgo: 9000,
    body: 'One question per post. Say what you tried.',
    pinned: true,
  ),
  _qaPostJson(
    askPostId,
    'Why do my night photos come out so grainy?',
    grace,
    createdMinutesAgo: 240,
    activeMinutesAgo: 15,
    body: 'Shot at ISO 6400 on a tripod. Is that too high?',
    replies: 2,
    unread: 1,
  ),
  _qaPostJson(
    'q-solved',
    'Which lens for the Milky Way?',
    me,
    createdMinutesAgo: 2000,
    activeMinutesAgo: 600,
    body: 'Planning a trip in November.',
    replies: 5,
    solved: true,
    answerId: 'qs-2',
  ),
];

/// The sample circle with a picture wall (`photo-wall`) and a Q&A channel
/// (`ask-the-group`) added to the Text Channels category.
CircleDetail circleDetailWithChannelTypes({
  int? permissions,
  String role = 'owner',
}) {
  final detail = circleDetail();
  final restricted = permissions != null;
  return CircleDetail(
    // [permissions] makes the current person an ordinary member who holds
    // only those bits in the two new channels.
    circle: restricted
        ? CircleSummary(
            id: detail.circle.id,
            name: detail.circle.name,
            memberCount: detail.circle.memberCount,
            channelCount: detail.circle.channelCount,
            currentUserRole: 'member',
            currentUserPermissions: 1 | 2 | 64 | 8192,
          )
        : detail.circle,
    categories: detail.categories,
    roles: detail.roles,
    members: detail.members,
    posts: detail.posts,
    channels: [
      ...detail.channels,
      CircleChannel(
        id: galleryChannelId,
        circleId: 'circle-1',
        conversationId: galleryConversationId,
        name: 'photo-wall',
        position: 3,
        categoryId: 'cat-1',
        kind: CircleChannelKind.media,
        topic: 'Your best shots from the trail.',
        currentUserPermissions: permissions,
        isReadOnly: restricted,
        tags: const [
          ForumTag(
            id: 'tag-land',
            channelId: galleryChannelId,
            name: 'Landscape',
            emoji: '🌄',
          ),
        ],
      ),
      CircleChannel(
        id: askChannelId,
        circleId: 'circle-1',
        conversationId: askConversationId,
        name: 'ask-the-group',
        position: 4,
        categoryId: 'cat-1',
        kind: CircleChannelKind.qa,
        topic: 'Gear, trips and technique questions.',
        currentUserPermissions: permissions,
        isReadOnly: restricted,
      ),
    ],
  );
}

/// The posts of the picture wall.
List<ForumPost> mediaPosts() {
  ForumPost post(
    String id,
    String title,
    Profile author, {
    required int createdMinutesAgo,
    required int activeMinutesAgo,
    int replies = 0,
    int unread = 0,
    bool pinned = false,
    String? alt,
    bool withPicture = true,
  }) => ForumPost(
    id: id,
    conversationId: '$id-conv',
    channelId: galleryChannelId,
    title: title,
    createdBy: author.id,
    author: ForumPostAuthor(profile: author),
    createdAt: minutesAgo(createdMinutesAgo),
    lastActivityAt: minutesAgo(activeMinutesAgo),
    replyCount: replies,
    unreadCount: unread,
    isPinned: pinned,
    canManage: true,
    thumbnail: withPicture
        ? ImageAttachment(
            bucket: 'chat-images',
            path: '$galleryConversationId/$id.png',
            mimeType: 'image/png',
            size: 2048,
            alt: alt,
          )
        : null,
  );

  return [
    post(
      'pic-pinned',
      'Monthly theme: golden hour',
      bart,
      createdMinutesAgo: 9000,
      activeMinutesAgo: 9000,
      pinned: true,
      alt: 'A field of wheat lit orange by the setting sun',
    ),
    post(
      'pic-1',
      'Sunrise over Half Dome with a very long title that wraps',
      grace,
      createdMinutesAgo: 300,
      activeMinutesAgo: 12,
      replies: 14,
      unread: 1,
      alt: 'Pink clouds over a granite dome',
    ),
    post(
      'pic-2',
      'Night sky from Glacier Point',
      me,
      createdMinutesAgo: 900,
      activeMinutesAgo: 200,
      replies: 3,
    ),
    post(
      'pic-3',
      'Mission Peak, 6 a.m.',
      linus,
      createdMinutesAgo: 1500,
      activeMinutesAgo: 1400,
    ),
    post(
      'pic-4',
      'Waiting for review',
      bart,
      createdMinutesAgo: 1600,
      activeMinutesAgo: 1600,
      withPicture: false,
    ),
  ];
}

/// The messages of the open question: the question itself and two answers.
List<ChatMessage> askPostMessages() => [
  phoneMessage(
    askQuestionId,
    grace,
    'Shot at ISO 6400 on a tripod. Is that too high?',
    minutesAgo: 240,
    conversationId: askPostConversationId,
  ),
  phoneMessage(
    askAnswerId,
    bart,
    'Try ISO 3200 with a longer exposure. The tripod makes that easy.',
    minutesAgo: 90,
    conversationId: askPostConversationId,
  ),
  phoneMessage(
    askOtherAnswerId,
    linus,
    'Stack five frames and average them, the grain mostly vanishes.',
    minutesAgo: 15,
    conversationId: askPostConversationId,
  ),
];

/// The sample world with the picture wall and the Q&A channel in the circle.
/// [canMark] is whether the current person may mark the open question.
QaRpc addChannelTypes(
  PhoneWorld world, {
  bool canMark = true,
  QaRpc? rpc,
  int? permissions,
}) {
  final qa = rpc ?? QaRpc(canMark: canMark);
  world.circles
    ..detail = circleDetailWithChannelTypes(permissions: permissions)
    ..forumPosts = [...world.circles.forumPosts, ...mediaPosts()];
  world.chats
    ..conversations = [
      ...world.chats.conversations,
      ConversationSummary(
        id: askPostConversationId,
        type: ConversationType.thread,
        unreadCount: 1,
        title: 'Why do my night photos come out so grainy?',
        lastMessageAt: minutesAgo(15),
        parentConversationId: askConversationId,
        parentTitle: 'ask-the-group',
        circleId: 'circle-1',
        threadId: askPostId,
        threadLastActivityAt: minutesAgo(15),
      ),
    ]
    // Only this post's messages: the fake lists the newest of all of them.
    ..messages = askPostMessages();
  world.extraOverrides = [...world.extraOverrides, ...qa.overrides];
  return qa;
}
