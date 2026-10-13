import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/circles/circle_category_collapse_store.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/app_router.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../features/chats/chat_thread_screen_test.dart' as chat_fakes;
import '../features/circles/circle_detail_screen_test.dart' as circle_fakes;
import '../features/contacts/contacts_screen_test.dart' as contact_fakes;
import '../features/profile/user_profile_screen_test.dart' as profile_fakes;
import '../features/settings/settings_screen_test.dart' as settings_fakes;

/// A phone screen to lay the app out on.
class PhoneViewport {
  const PhoneViewport({
    required this.name,
    required this.size,
    required this.devicePixelRatio,
    this.topInset = 0,
    this.bottomInset = 0,
    this.textScale = 1,
  });

  final String name;

  /// Logical size.
  final Size size;
  final double devicePixelRatio;

  /// Status bar / notch, in logical pixels.
  final double topInset;

  /// Home indicator, in logical pixels.
  final double bottomInset;
  final double textScale;

  @override
  String toString() => name;
}

/// Small Android phone.
const smallPhone = PhoneViewport(
  name: '360x640',
  size: Size(360, 640),
  devicePixelRatio: 2,
  topInset: 24,
);

/// iPhone 12-15 class phone with a notch and home indicator.
const notchedPhone = PhoneViewport(
  name: '390x844',
  size: Size(390, 844),
  devicePixelRatio: 3,
  topInset: 47,
  bottomInset: 34,
);

/// [notchedPhone] with larger accessibility text.
const notchedPhoneLargeText = PhoneViewport(
  name: '390x844 text 1.3',
  size: Size(390, 844),
  devicePixelRatio: 3,
  topInset: 47,
  bottomInset: 34,
  textScale: 1.3,
);

const phoneViewports = [smallPhone, notchedPhone, notchedPhoneLargeText];

/// Lays the test view out as [viewport]; everything is reset when the test
/// ends.
void usePhoneViewport(WidgetTester tester, PhoneViewport viewport) {
  final view = tester.view;
  final ratio = viewport.devicePixelRatio;
  view.physicalSize = viewport.size * ratio;
  view.devicePixelRatio = ratio;
  final padding = FakeViewPadding(
    top: viewport.topInset * ratio,
    bottom: viewport.bottomInset * ratio,
  );
  view.padding = padding;
  view.viewPadding = padding;
  view.viewInsets = FakeViewPadding.zero;
  tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
  addTearDown(() {
    view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Simulates an on-screen keyboard [height] logical pixels tall. Like iOS,
/// the bottom safe area is consumed by the keyboard.
Future<void> showKeyboard(
  WidgetTester tester,
  PhoneViewport viewport, {
  double height = 300,
}) async {
  final ratio = viewport.devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: height * ratio);
  tester.view.padding = FakeViewPadding(top: viewport.topInset * ratio);
  await settle(tester);
}

/// Runs [body] once per phone viewport.
void phoneTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester, PhoneViewport viewport) body, {
  List<PhoneViewport> viewports = phoneViewports,
}) {
  for (final viewport in viewports) {
    testWidgets('$description at $viewport', (tester) async {
      usePhoneViewport(tester, viewport);
      await body(tester, viewport);
    });
  }
}

/// Pumps long enough for data to load and sheets, dialogs and routes to
/// finish animating, without waiting on endless animations.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The visible screen area above the keyboard.
Rect visibleArea(WidgetTester tester) {
  final view = tester.view;
  final size = view.physicalSize / view.devicePixelRatio;
  final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
  return Rect.fromLTWH(0, 0, size.width, size.height - keyboard);
}

/// Expects [finder]'s widget to be fully on screen and above the keyboard.
void expectFullyVisible(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final area = visibleArea(tester);
  expect(
    area.contains(rect.topLeft) &&
        rect.right <= area.right + 0.5 &&
        rect.bottom <= area.bottom + 0.5,
    isTrue,
    reason: '$rect should fit in $area',
  );
}

/// Expects the first line of the text field [finder], where the caret is
/// kept while typing, to be on screen above the keyboard.
void expectCaretVisible(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final area = visibleArea(tester);
  final firstLineBottom = rect.top + (rect.height < 32 ? rect.height : 32);
  expect(
    rect.top >= area.top && firstLineBottom <= area.bottom + 0.5,
    isTrue,
    reason: 'the first line of $rect should be inside $area',
  );
}

/// Expects every hit-testable widget matched by [finder] to be at least
/// [minSize] logical pixels in both directions.
void expectTouchTargets(
  WidgetTester tester,
  Finder finder, {
  double minSize = 44,
}) {
  final elements = finder.evaluate().toList();
  expect(elements, isNotEmpty, reason: 'nothing matched $finder');
  for (final element in elements) {
    final size = (element.renderObject! as RenderBox).size;
    expect(
      size.width >= minSize && size.height >= minSize,
      isTrue,
      reason: '${element.widget} is $size, smaller than $minSize',
    );
  }
}

/// The whole tappable area of the icon button with [tooltip]; the tooltip
/// itself only covers the visible part.
Finder iconButtonWithTooltip(String tooltip) {
  return find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  );
}

/// Scrolls the screen's main list down until [finder] is built, then brings
/// its first match on screen.
Future<void> scrollIntoView(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  scrollable ??= find.byType(Scrollable).first;
  for (var step = 0; step < 30 && finder.evaluate().isEmpty; step++) {
    // Drag along the left edge, clear of text fields that scroll too.
    final rect = tester.getRect(scrollable);
    await tester.dragFrom(
      Offset(rect.left + 8, rect.center.dy),
      const Offset(0, -120),
    );
    await tester.pump();
  }
  await tester.ensureVisible(finder.first);
  await settle(tester);
}

/// Pops the top route, like the system back gesture, to close a sheet or
/// dialog that covers the whole screen.
Future<void> popTopRoute(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

// ---------------------------------------------------------------------------
// Fake data
// ---------------------------------------------------------------------------

final _now = DateTime.now().toUtc();

DateTime minutesAgo(int minutes) => _now.subtract(Duration(minutes: minutes));

Profile phoneProfile(
  String id,
  String username,
  String displayName, {
  CustomStatus? customStatus,
  String? alias,
}) {
  return Profile(
    id: id,
    username: username,
    displayName: displayName,
    bio: 'Building familiar spaces for friends who like long names.',
    alias: alias,
    customStatus: customStatus,
    createdAt: DateTime.utc(2026, 5, 18),
    updatedAt: DateTime.utc(2026, 5, 18),
  );
}

const longStatusText = 'Deep focus until the quarterly planning sync wraps up';
const longStatus = CustomStatus(emoji: '🎯', text: longStatusText);

final me = phoneProfile(
  'user-1',
  'ada',
  'Ada Lovelace',
  customStatus: const CustomStatus(emoji: '☕', text: 'Brewing ideas'),
);
final bart = phoneProfile(
  'user-2',
  'bartholomew_montgomery',
  'Bartholomew Montgomery-Fitzgerald III',
  customStatus: longStatus,
);
final grace = phoneProfile('user-3', 'grace', 'Grace Brewster Murray Hopper');
final linus = phoneProfile(
  'user-4',
  'linus',
  'Linus',
  customStatus: const CustomStatus(emoji: '🏔️'),
);

final extraMembers = [
  for (var index = 5; index < 17; index++)
    phoneProfile(
      'user-$index',
      'member_$index',
      index.isEven ? 'Member Number $index With A Long Name' : 'M$index',
      customStatus: index % 3 == 0
          ? const CustomStatus(emoji: '🎧', text: 'Listening to lo-fi beats')
          : null,
    ),
];

const blogUrl =
    'https://wecord.example.com/blog/2026/10/the-very-long-release-notes';
const ownLinkUrl =
    'https://example.com/a/very/long/link/that/should/wrap/somewhere/'
    'in/the/bubble?with=query&params=true';

const longCodeLine =
    'final subscription = repository.threadChanges(conversationId)'
    '.listen((_) => ref.invalidateSelf());';

ChatMessage phoneMessage(
  String id,
  Profile sender,
  String body, {
  required int minutesAgo,
  MessageType type = MessageType.text,
  Map<String, dynamic>? attachment,
  ReplyPreview? replyPreview,
  ForwardPreview? forwardPreview,
  DateTime? editedAt,
  List<MessageReaction> reactions = const [],
  bool isPinned = false,
  MessageThreadSummary? threadSummary,
  List<MessageMention> mentions = const [],
  String conversationId = 'dm-1',
}) {
  return ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: sender.id,
    type: type,
    body: body,
    attachment: attachment,
    replyPreview: replyPreview,
    forwardPreview: forwardPreview,
    createdAt: _now.subtract(Duration(minutes: minutesAgo)),
    editedAt: editedAt,
    reactions: reactions,
    isPinned: isPinned,
    sender: sender,
    threadSummary: threadSummary,
    mentions: mentions,
  );
}

/// A conversation that exercises every kind of message bubble.
List<ChatMessage> richMessages({bool withThread = false}) {
  return [
    phoneMessage(
      'm0',
      me,
      'Ada pinned a message.',
      minutesAgo: 120,
      type: MessageType.system,
      attachment: const {'kind': 'pin', 'message_id': 'm2'},
    ),
    phoneMessage(
      'm1',
      bart,
      'Morning! Did you catch the **release notes**? $blogUrl',
      minutesAgo: 90,
    ),
    phoneMessage(
      'm2',
      bart,
      '> Shipping is a feature too, and this quote is long enough to wrap '
          'over several lines on a phone.\n'
          'Agreed. Here is the snippet:\n'
          '```\n$longCodeLine\n```',
      minutesAgo: 88,
      isPinned: true,
      reactions: const [
        MessageReaction(emoji: '👍', count: 3),
        MessageReaction(emoji: '❤️', count: 1, reactedByMe: true),
        MessageReaction(emoji: '😂', count: 12),
        MessageReaction(emoji: '🎉', count: 2),
        MessageReaction(emoji: '😮', count: 1),
        MessageReaction(emoji: '😢', count: 105),
        MessageReaction(emoji: '🔥', count: 7),
      ],
      threadSummary: withThread
          ? MessageThreadSummary(
              threadId: 'thread-1',
              conversationId: 'thread-conv-1',
              title: 'Planning the extremely long weekend trip to Yosemite',
              replyCount: 12,
              lastReplyAt: minutesAgo(5),
              unreadCount: 2,
            )
          : null,
    ),
    phoneMessage(
      'm3',
      me,
      'Supercalifragilisticexpialidocious_unbroken_identifier_that_goes_on_'
          'and_on_and_on @grace',
      minutesAgo: 60,
      editedAt: minutesAgo(59),
      replyPreview: const ReplyPreview(
        messageId: 'm2',
        senderName: 'Bartholomew Montgomery-Fitzgerald III',
        body: 'Shipping is a feature too, and this quote is long enough',
        type: MessageType.text,
      ),
      mentions: const [
        MessageMention(
          userId: 'user-3',
          displayName: 'Grace',
          start: 81,
          end: 87,
        ),
      ],
    ),
    phoneMessage(
      'm4',
      me,
      '',
      minutesAgo: 50,
      type: MessageType.image,
      attachment: const {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'dm-1/photo.png',
        'mime_type': 'image/png',
        'size': 1024,
        'width': 1200,
        'height': 800,
      },
    ),
    phoneMessage(
      'm5',
      bart,
      '',
      minutesAgo: 40,
      type: MessageType.voice,
      attachment: const {
        'kind': 'voice',
        'bucket': 'voice-messages',
        'path': 'dm-1/voice.m4a',
        'mime_type': 'audio/mp4',
        'size': 2048,
        'duration_ms': 83000,
      },
    ),
    phoneMessage(
      'm6',
      bart,
      'Forwarding this one.',
      minutesAgo: 30,
      forwardPreview: const ForwardPreview(
        messageId: 'm-old',
        senderName: 'Grace Brewster Murray Hopper',
        type: MessageType.text,
        body:
            'It is often easier to ask for forgiveness than to ask for '
            'permission, especially on long release trains.',
      ),
    ),
    phoneMessage('m7', me, 'Also this: $ownLinkUrl', minutesAgo: 2),
  ];
}

final _linkPreviews = {
  blogUrl: const LinkPreview(
    url: blogUrl,
    siteName: 'WeCord Blog',
    title:
        'Autumn update: threads, presence, custom statuses and a whole '
        'lot more polish for every screen',
    description:
        'Everything that shipped this quarter, from message threads to '
        'app-wide presence, plus the fixes you asked for most.',
    imageUrl: 'https://wecord.example.com/og.png',
  ),
  ownLinkUrl: const LinkPreview(
    url: ownLinkUrl,
    siteName: 'example.com',
    title: 'An example page with a title that is long enough to wrap',
  ),
};

final groupDetail = GroupDetail(
  conversationId: 'group-1',
  title: 'Weekend Hiking & Photography Club — Bay Area Chapter',
  announcement:
      'Trailhead moved to the north lot this Saturday. Bring layers, water '
      'and a headlamp; we will be out past sunset.',
  currentUserRole: 'owner',
  members: [
    GroupMember(profile: me, role: 'owner'),
    GroupMember(profile: bart, role: 'admin'),
    GroupMember(profile: grace, role: 'member', nickname: 'Amazing Grace'),
    GroupMember(profile: linus, role: 'member'),
    for (final profile in extraMembers)
      GroupMember(profile: profile, role: 'member'),
  ],
);

final phoneConversations = [
  ConversationSummary(
    id: 'dm-1',
    type: ConversationType.direct,
    unreadCount: 128,
    title: bart.displayName,
    lastMessageBody:
        'Morning! Did you catch the **release notes**? They are long.',
    lastMessageSenderId: bart.id,
    lastMessageAt: minutesAgo(2),
    pinnedAt: minutesAgo(1000),
    isMuted: true,
    directUserId: bart.id,
    directCustomStatus: longStatus,
  ),
  ConversationSummary(
    id: 'group-1',
    type: ConversationType.group,
    unreadCount: 3,
    title: groupDetail.title,
    lastMessageBody: 'Trailhead moved to the north lot this Saturday.',
    lastMessageAt: minutesAgo(15),
    memberCount: 42,
    announcement: groupDetail.announcement,
  ),
  ConversationSummary(
    id: 'dm-2',
    type: ConversationType.direct,
    unreadCount: 0,
    title: grace.displayName,
    lastMessageBody: 'Voice message',
    lastMessageType: MessageType.voice,
    lastMessageAt: minutesAgo(300),
    isMarkedUnread: true,
    directUserId: grace.id,
  ),
  ConversationSummary(
    id: 'conv-general',
    type: ConversationType.channel,
    unreadCount: 4,
    title: 'general',
    lastMessageAt: minutesAgo(3),
    lastMessageBody: 'Who is in for Saturday?',
    circleId: 'circle-1',
  ),
  ConversationSummary(
    id: 'conv-random',
    type: ConversationType.channel,
    unreadCount: 0,
    title: 'off-topic-random-chatter-and-memes-zone',
    lastMessageAt: minutesAgo(400),
    circleId: 'circle-1',
  ),
  ConversationSummary(
    id: 'thread-conv-1',
    type: ConversationType.thread,
    unreadCount: 2,
    title: 'Planning the extremely long weekend trip to Yosemite Valley',
    lastMessageAt: minutesAgo(5),
    parentConversationId: 'conv-general',
    parentTitle: 'general',
    circleId: 'circle-1',
    threadId: 'thread-1',
    threadLastActivityAt: minutesAgo(5),
  ),
  ConversationSummary(
    id: 'thread-conv-2',
    type: ConversationType.thread,
    unreadCount: 0,
    title: 'Gear list',
    lastMessageAt: minutesAgo(50),
    parentConversationId: 'conv-random',
    parentTitle: 'off-topic-random-chatter-and-memes-zone',
    circleId: 'circle-1',
    threadId: 'thread-2',
    threadLastActivityAt: minutesAgo(50),
  ),
  ConversationSummary(
    id: 'dm-3',
    type: ConversationType.direct,
    unreadCount: 0,
    title: 'Linus',
  ),
];

CircleChannel _channel(
  String id,
  String conversationId,
  String name,
  int position, {
  String? categoryId,
}) {
  return CircleChannel(
    id: id,
    circleId: 'circle-1',
    conversationId: conversationId,
    name: name,
    position: position,
    categoryId: categoryId,
  );
}

CirclePost _post(String id, Profile author, String body, int minutesAgo) {
  final createdAt = _now.subtract(Duration(minutes: minutesAgo));
  return CirclePost(
    id: id,
    circleId: 'circle-1',
    authorId: author.id,
    body: body,
    createdAt: createdAt,
    updatedAt: createdAt,
    author: author,
    isOwnPost: author.id == me.id,
    canManagePost: true,
    likeCount: 24,
    commentCount: 2,
    likedByCurrentUser: true,
    comments: [
      CirclePostComment(
        id: '$id-c1',
        postId: id,
        authorId: grace.id,
        body: 'Count me in! I will bring the extra-long telephoto lens.',
        createdAt: createdAt,
        updatedAt: createdAt,
        author: grace,
      ),
      CirclePostComment(
        id: '$id-c2',
        postId: id,
        authorId: linus.id,
        body: 'Same.',
        createdAt: createdAt,
        updatedAt: createdAt,
        author: linus,
      ),
    ],
  );
}

final circleSummaries = [
  const CircleSummary(
    id: 'circle-1',
    name: 'Bay Area Weekend Explorers & Photography Friends',
    memberCount: 128,
    channelCount: 6,
    currentUserRole: 'owner',
    unreadCount: 4,
    mentionCount: 3,
  ),
  const CircleSummary(
    id: 'circle-2',
    name: 'Book Club',
    memberCount: 9,
    channelCount: 2,
    unreadCount: 40,
    mentionCount: 120,
    isMuted: true,
  ),
  const CircleSummary(
    id: 'circle-3',
    name: 'Family',
    memberCount: 6,
    channelCount: 3,
    unreadCount: 2,
  ),
  const CircleSummary(
    id: 'circle-4',
    name: 'International Society of Extremely Long Circle Names',
    memberCount: 1024,
    channelCount: 48,
    isMuted: true,
  ),
  const CircleSummary(
    id: 'circle-5',
    name: 'Climbing',
    memberCount: 14,
    channelCount: 4,
  ),
];

CircleDetail circleDetail() {
  return CircleDetail(
    circle: circleSummaries.first,
    categories: const [
      CircleChannelCategory(
        id: 'cat-1',
        circleId: 'circle-1',
        name: 'Text Channels',
        position: 0,
      ),
      CircleChannelCategory(
        id: 'cat-2',
        circleId: 'circle-1',
        name: 'Trips, Events & Very Long Category Names Here',
        position: 1,
      ),
      CircleChannelCategory(
        id: 'cat-3',
        circleId: 'circle-1',
        name: 'Archive',
        position: 2,
      ),
    ],
    channels: [
      _channel('ch-general', 'conv-general', 'general', 0),
      _channel('ch-ann', 'conv-ann', 'announcements', 0, categoryId: 'cat-1'),
      _channel(
        'ch-random',
        'conv-random',
        'off-topic-random-chatter-and-memes-zone',
        1,
        categoryId: 'cat-1',
      ),
      _channel(
        'ch-yosemite',
        'conv-yosemite',
        'yosemite-2026-planning-and-logistics',
        0,
        categoryId: 'cat-2',
      ),
      _channel(
        'ch-photos',
        'conv-photos',
        'photo-dump',
        1,
        categoryId: 'cat-2',
      ),
      _channel('ch-old', 'conv-old', 'old-stuff', 0, categoryId: 'cat-3'),
    ],
    members: [
      CircleMember(profile: me, role: 'owner', isCurrentUser: true),
      CircleMember(profile: bart, role: 'admin', nickname: 'Bart the Bold'),
      CircleMember(profile: grace, role: 'member'),
      CircleMember(profile: linus, role: 'member', nickname: 'Linus'),
      for (final profile in extraMembers)
        CircleMember(profile: profile, role: 'member'),
    ],
    posts: [
      _post(
        'post-1',
        bart,
        'Sunrise hike to Mission Peak on Saturday! Meet at the trailhead at '
            '5:30 sharp. Headlamps required, coffee optional but strongly '
            'encouraged. Reply below if you are coming so we can carpool.',
        30,
      ),
      _post('post-2', me, 'Photos from last weekend are up 📸', 600),
    ],
  );
}

// ---------------------------------------------------------------------------
// Fake repositories
// ---------------------------------------------------------------------------

class PhoneChatsRepository extends chat_fakes.FakeChatsRepository {
  @override
  Future<List<DiscoveryResult>> searchDiscovery(String query) async {
    return [
      DiscoveryResult(
        type: DiscoveryResultType.contact,
        id: bart.id,
        title: bart.displayName,
        subtitle: '@${bart.username}',
        rank: 1,
      ),
      DiscoveryResult(
        type: DiscoveryResultType.circleChannel,
        id: 'ch-random',
        title: '# off-topic-random-chatter-and-memes-zone',
        subtitle: circleSummaries.first.name,
        conversationId: 'conv-random',
        circleId: 'circle-1',
        channelId: 'ch-random',
        rank: 0.9,
      ),
      DiscoveryResult(
        type: DiscoveryResultType.message,
        id: 'm2',
        title: bart.displayName,
        subtitle:
            'Shipping is a feature too, and this quote is long enough to '
            'wrap over several lines on a phone.',
        conversationId: 'dm-1',
        rank: 0.5,
      ),
    ];
  }

  @override
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) async {
    return [
      for (var index = 0; index < 4; index++)
        ConversationMediaItem(
          messageId: 'media-$index',
          conversationId: conversationId,
          senderId: bart.id,
          senderName: bart.displayName,
          type: index.isEven ? MessageType.image : MessageType.voice,
          body: '',
          createdAt: minutesAgo(index * 60),
          attachment: index.isEven
              ? {
                  'kind': 'image',
                  'bucket': 'chat-images',
                  'path': 'dm-1/photo-$index.png',
                  'mime_type': 'image/png',
                  'size': 1024,
                }
              : {
                  'kind': 'voice',
                  'bucket': 'voice-messages',
                  'path': 'dm-1/voice-$index.m4a',
                  'mime_type': 'audio/mp4',
                  'size': 2048,
                  'duration_ms': 61000,
                },
        ),
    ];
  }
}

class PhoneCirclesRepository extends circle_fakes.FakeCirclesRepository {
  @override
  Future<List<CircleInvite>> listInvites(String circleId) async {
    return [
      CircleInvite(
        code: 'h7Kq2mPz',
        circleId: circleId,
        createdAt: minutesAgo(60),
        useCount: 3,
        maxUses: 25,
        expiresAt: _now.add(const Duration(days: 6)),
        createdByName: bart.displayName,
      ),
      CircleInvite(
        code: 'Zx81LmNo',
        circleId: circleId,
        createdAt: minutesAgo(600),
        useCount: 0,
        createdByName: me.displayName,
      ),
    ];
  }

  @override
  Future<CircleInvitePreview> getInvitePreview(String code) async {
    return CircleInvitePreview(
      code: code,
      alreadyMember: false,
      expiresAt: _now.add(const Duration(days: 2)),
      circle: CircleInvitePreviewCircle(
        id: 'circle-4',
        name: circleSummaries[3].name,
        memberCount: 1024,
      ),
    );
  }
}

class _NoopNotificationCoordinator extends NotificationCoordinator {
  _NoopNotificationCoordinator({
    required super.authRepository,
    required super.chatsRepository,
  }) : super(
         preferencesRepository: NotificationPreferencesRepository.withStore(
           InMemoryNotificationPreferencesStore(),
         ),
         notificationService: FakeLocalNotificationService(),
         activeConversationId: () => null,
         pollTicks: const Stream<void>.empty(),
       );

  @override
  Future<void> start() async {}
}

/// Every repository the app touches, filled with realistic data, plus the
/// app itself.
class PhoneWorld {
  PhoneWorld() {
    auth.user = const AuthUser(id: 'user-1', email: 'ada@example.com');
    chats
      ..conversations = [...phoneConversations]
      ..messages = richMessages()
      ..readMarkers = const [
        ConversationReadMarker(userId: 'user-1', lastReadMessageId: 'm5'),
        ConversationReadMarker(userId: 'user-2', lastReadMessageId: 'm7'),
      ]
      ..groupDetail = groupDetail
      ..canPin = true
      ..canManageThreads = true
      ..linkPreviews = _linkPreviews
      ..reactors = [bart, grace, linus, ...extraMembers]
      ..pinnedMessages = [
        PinnedMessage(
          message: richMessages()[2],
          sender: bart,
          pinnedAt: minutesAgo(80),
          pinnedByName: me.displayName,
        ),
        PinnedMessage(
          message: richMessages()[1],
          sender: bart,
          pinnedAt: minutesAgo(70),
          pinnedByName: bart.displayName,
        ),
      ];
    circles
      ..detail = circleDetail()
      ..circles = circleSummaries
      ..onlineUserIds = {'user-1', 'user-2', 'user-5', 'user-6'};
    contacts
      ..friends = [bart, grace.copyWith(alias: 'Grandma COBOL'), linus]
      ..searchResults = [extraMembers.first, extraMembers[1]]
      ..incomingRequests = [
        IncomingFriendRequest(
          request: FriendRequest(
            id: 'request-1',
            requesterId: extraMembers[2].id,
            receiverId: me.id,
            status: FriendRequestStatus.pending,
            createdAt: minutesAgo(10),
            updatedAt: minutesAgo(10),
          ),
          requester: extraMembers[2],
        ),
      ];
    settings.profile = me.copyWith(avatarUrl: null);
    profileData.rpcResult = [
      {
        ...profile_fakes.summaryJson(
          profile_fakes.friendSummary(
            displayName: bart.displayName,
            username: bart.username,
          ),
        ),
        'custom_status': longStatus.toJson(),
        'bio':
            'Trail runner, amateur astronomer and full-time collector of '
            'very long names.',
      },
    ];
  }

  final auth = chat_fakes.FakeAuthRepository();
  final chats = PhoneChatsRepository();
  final circles = PhoneCirclesRepository();
  final contacts = contact_fakes.FakeContactsRepository();
  final settings = settings_fakes.FakeSettingsRepository();
  final profileData = profile_fakes.FakeProfileDataSource();
  final recorder = chat_fakes.FakeVoiceMessageRecorder();
  final imagePicker = chat_fakes.FakeImagePickerService();
  final collapseStore = circle_fakes.InMemoryCircleCategoryCollapseStore({
    'circle-1': {'cat-3'},
  });
  final openedLinks = <Uri>[];

  late GoRouter router;

  List<Override> get overrides {
    return [
      authRepositoryProvider.overrideWithValue(auth),
      authStateProvider.overrideWith((ref) => Stream.value(auth.user)),
      chatsRepositoryProvider.overrideWithValue(chats),
      circlesRepositoryProvider.overrideWithValue(circles),
      contactsRepositoryProvider.overrideWithValue(contacts),
      settingsRepositoryProvider.overrideWithValue(settings),
      profileRepositoryProvider.overrideWithValue(
        ProfileRepository.withDataSource(profileData),
      ),
      onlineUserIdsProvider.overrideWith(
        (ref) => Stream.value(circles.onlineUserIds),
      ),
      circleCategoryCollapseStoreProvider.overrideWithValue(collapseStore),
      notificationCoordinatorProvider.overrideWithValue(
        _NoopNotificationCoordinator(
          authRepository: auth,
          chatsRepository: chats,
        ),
      ),
      localNotificationServiceProvider.overrideWithValue(
        FakeLocalNotificationService(),
      ),
      notificationPreferencesRepositoryProvider.overrideWithValue(
        NotificationPreferencesRepository.withStore(
          InMemoryNotificationPreferencesStore(),
        ),
      ),
      voiceMessageRecorderProvider.overrideWithValue(recorder),
      imagePickerServiceProvider.overrideWithValue(imagePicker),
      linkLauncherProvider.overrideWithValue((uri) async {
        openedLinks.add(uri);
      }),
    ];
  }

  /// Pumps the whole app signed in and opens [location].
  Future<void> open(
    WidgetTester tester,
    String location, {
    Object? extra,
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const WeCordApp()),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WeCordApp)),
    );
    router = container.read(appRouterProvider);
    await settle(tester);
    if (router.routerDelegate.currentConfiguration.uri.toString() != location) {
      router.go(location, extra: extra);
    }
    await settle(tester);
  }

  /// Unmounts the app so pending timers are cancelled before the test ends.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  }
}

/// Pumps [child] alone inside the themed app with [world]'s fakes, for
/// screens outside the signed-in shell.
Future<void> pumpStandalone(
  WidgetTester tester,
  PhoneWorld world,
  Widget child, {
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...world.overrides, ...extraOverrides],
      child: MaterialApp(theme: _theme(), home: child),
    ),
  );
  await settle(tester);
}

ThemeData _theme() => WeCordTheme.light();
