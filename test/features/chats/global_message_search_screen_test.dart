import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  late FakeChatsRepository chats;
  late FakeSearchRepository search;
  late MemoryRecentSearchesStore recents;
  late ProviderContainer Function() containerOf;

  setUp(() {
    chats = FakeChatsRepository();
    search = FakeSearchRepository();
    recents = MemoryRecentSearchesStore();
  });

  Future<GoRouter> pumpSearch(
    WidgetTester tester, {
    String location = GlobalMessageSearchScreen.path,
  }) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: GlobalMessageSearchScreen.path,
          builder: (context, state) => GlobalMessageSearchScreen(
            launch: GlobalMessageSearchScreen.launchFrom(
              state.uri.queryParameters,
            ),
          ),
        ),
        GoRoute(
          path: '/chats/:conversationId',
          builder: (context, state) =>
              Text('Thread ${state.pathParameters['conversationId']}'),
        ),
        GoRoute(
          path: '/circles/:circleId',
          builder: (context, state) =>
              Text('Circle ${state.pathParameters['circleId']}'),
          routes: [
            GoRoute(
              path: 'channels/:conversationId',
              builder: (context, state) =>
                  Text('Channel ${state.pathParameters['conversationId']}'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(chats),
          messageSearchRepositoryProvider.overrideWithValue(search),
          recentSearchesStoreProvider.overrideWithValue(recents),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GlobalMessageSearchScreen)),
    );
    containerOf = () => container;
    return router;
  }

  Future<void> typeQuery(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      text,
    );
    await tester.pump(MessageSearchController.debounce);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('results are grouped by conversation and open at the message', (
    tester,
  ) async {
    search.pages.add(
      SearchPage(
        hits: [
          hit('m1', 'conv-1', 'Ada', 'We ship it on Friday', place: dm),
          hit('m2', 'conv-2', 'Grace', 'Ship notes are up', place: general),
          hit('m3', 'conv-1', 'Ada', 'ship ship ship', place: dm),
        ],
        total: 12,
        conversationCounts: const {'conv-1': 9, 'conv-2': 3},
      ),
    );
    await pumpSearch(tester);
    await typeQuery(tester, 'ship');

    expect(search.requests.single.text, 'ship');
    expect(search.requests.single.scope, const EverywhereScope());
    expect(find.text('12 results'), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('# general  Launch Crew'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('search-group-count-conv-1')),
      findsOneWidget,
    );
    expect(find.text('9'), findsOneWidget);
    // conv-1's two results sit together, before conv-2's.
    final m1 = tester.getTopLeft(find.byKey(const ValueKey('search-hit-m1')));
    final m3 = tester.getTopLeft(find.byKey(const ValueKey('search-hit-m3')));
    final m2 = tester.getTopLeft(find.byKey(const ValueKey('search-hit-m2')));
    expect(m1.dy, lessThan(m3.dy));
    expect(m3.dy, lessThan(m2.dy));

    // The match is marked.
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('search-hit-m1')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText() == 'We ship it on Friday',
        ),
      ),
    );
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text), ['We ', 'ship', ' it on Friday']);
    expect(spans[1].style?.fontWeight, FontWeight.w700);

    await tester.tap(find.byKey(const ValueKey('search-hit-m1')));
    await tester.pumpAndSettle();
    expect(find.text('Thread conv-1'), findsOneWidget);
    final jump = containerOf().read(pendingMessageJumpProvider);
    expect(jump?.conversationId, 'conv-1');
    expect(jump?.messageId, 'm1');
    expect(recents.saved.last, ['ship']);
  });

  testWidgets('channel results open inside their circle', (tester) async {
    search.pages.add(
      SearchPage(
        hits: [hit('m2', 'conv-2', 'Grace', 'notes', place: general)],
        total: 1,
      ),
    );
    await pumpSearch(tester);
    await typeQuery(tester, 'notes');
    expect(find.text('1 result'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search-hit-m2')));
    await tester.pumpAndSettle();
    expect(find.text('Channel conv-2'), findsOneWidget);
  });

  testWidgets('from: autocompletes people and sends their ids', (tester) async {
    search.people = const [
      SearchPerson(id: 'u-grace', username: 'grace', displayName: 'Grace H'),
    ];
    search.pages.add(const SearchPage(hits: [], total: 0));
    await pumpSearch(tester);

    // An empty box offers the filters.
    await tester.tap(find.byKey(const ValueKey('message-search-field')));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-operator-from')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      'deploy from:@gr',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(search.suggestionPrefixes.last, 'gr');
    await tester.tap(find.byKey(const ValueKey('search-person-u-grace')));
    await tester.pump(MessageSearchController.debounce);
    await tester.pump();
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'deploy from:@grace ');
    final request = search.requests.last;
    expect(request.text, 'deploy');
    expect(request.filters.fromIds, ['u-grace']);
    // The filter shows as a chip that removes it.
    expect(find.text('From @grace'), findsOneWidget);
    await tester.tap(find.text('From @grace'));
    await tester.pump();
    expect(field.controller!.text, 'deploy');
  });

  testWidgets('a filter nobody matches says so instead of searching', (
    tester,
  ) async {
    await pumpSearch(tester);
    await typeQuery(tester, 'from:@nobody hello');
    expect(search.requests, isEmpty);
    expect(find.text('No one called @nobody here.'), findsOneWidget);
  });

  testWidgets('has:, dates and pinned: go out as filters', (tester) async {
    search.pages.add(const SearchPage(hits: [], total: 0));
    await pumpSearch(tester);
    await typeQuery(
      tester,
      'has:link during:2026-10-02 pinned:true "release notes"',
    );
    final request = search.requests.single;
    expect(request.text, '"release notes"');
    final json = request.filters.toJson();
    expect(json['has'], ['link']);
    expect(json['pinned'], true);
    expect(
      DateTime.parse(json['after']! as String),
      DateTime(2026, 10, 2).toUtc(),
    );
    expect(
      DateTime.parse(json['before']! as String),
      DateTime(2026, 10, 3).toUtc(),
    );
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('opened from a channel it searches there, then everywhere', (
    tester,
  ) async {
    search.pages.addAll(const [
      SearchPage(hits: [], total: 0),
      SearchPage(hits: [], total: 0),
    ]);
    await pumpSearch(
      tester,
      location: GlobalMessageSearchScreen.location(
        conversationId: 'conv-2',
        conversationTitle: 'general',
        conversationType: ConversationType.channel,
        circleId: 'circle-1',
        query: 'standup',
      ),
    );
    await tester.pump(MessageSearchController.debounce);
    await tester.pump();
    expect(find.text('This channel'), findsOneWidget);
    expect(find.text('This circle'), findsOneWidget);
    expect(find.text('Everywhere'), findsOneWidget);
    expect(
      search.requests.first.scope,
      const ConversationScope(conversationId: 'conv-2'),
    );
    expect(search.requests.first.text, 'standup');

    await tester.tap(find.text('Everywhere'));
    await tester.pump();
    await tester.pump();
    expect(search.requests.last.scope, const EverywhereScope());
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    search.pages.addAll([
      SearchPage(
        hits: [
          for (var i = 0; i < 25; i++)
            hit('a$i', 'conv-1', 'Ada', 'ship $i', place: dm),
        ],
        total: 30,
        nextCursor: const {'id': 'a24', 'created_at': '2026-10-01T00:00:00Z'},
      ),
      SearchPage(
        hits: [
          for (var i = 0; i < 5; i++)
            hit('b$i', 'conv-1', 'Ada', 'ship more $i', place: dm),
        ],
      ),
    ]);
    await pumpSearch(tester);
    await typeQuery(tester, 'ship');
    await tester.drag(
      find.byKey(const ValueKey('message-search-results')),
      const Offset(0, -6000),
    );
    await tester.pumpAndSettle();
    expect(search.requests, hasLength(2));
    expect(search.requests.last.cursor, {
      'id': 'a24',
      'created_at': '2026-10-01T00:00:00Z',
    });
    expect(find.text('That is everything.'), findsOneWidget);
  });

  testWidgets('a result shows the messages around it', (tester) async {
    search.pages.add(
      SearchPage(
        hits: [hit('m1', 'conv-1', 'Ada', 'the release', place: dm)],
        total: 1,
      ),
    );
    search.contextFor['m1'] = SearchContext(
      before: [hit('m0', 'conv-1', 'Grace', 'is it ready?')],
      after: [hit('m2', 'conv-1', 'Grace', 'great, thanks')],
    );
    await pumpSearch(tester);
    await typeQuery(tester, 'release');
    await tester.tap(find.byKey(const ValueKey('search-hit-context-m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-context-m0')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-context-m2')), findsOneWidget);
    expect(find.textContaining('is it ready?'), findsOneWidget);
  });

  testWidgets('recent searches come back and can be cleared', (tester) async {
    recents.stored = ['ship it', 'from:@ada'];
    search.pages.add(const SearchPage(hits: [], total: 0));
    await pumpSearch(tester);
    await tester.pump();
    expect(find.text('Recent searches'), findsWidgets);
    expect(find.text('ship it'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('search-clear-recent')).first);
    await tester.pump();
    expect(find.text('ship it'), findsNothing);
    expect(recents.saved.last, isEmpty);
  });

  testWidgets('people and places named like the search show first', (
    tester,
  ) async {
    chats.discoveryResults = const [
      DiscoveryResult(
        type: DiscoveryResultType.circle,
        id: 'circle-1',
        title: 'Close Friends',
        circleId: 'circle-1',
        rank: 0.9,
      ),
      DiscoveryResult(
        type: DiscoveryResultType.message,
        id: 'message-1',
        title: 'not shown here',
        conversationId: 'conv-1',
        rank: 0.5,
      ),
    ];
    search.pages.add(const SearchPage(hits: [], total: 0));
    await pumpSearch(tester);
    await typeQuery(tester, 'close');
    expect(find.text('People and places'), findsOneWidget);
    expect(find.text('not shown here'), findsNothing);
    await tester.tap(find.text('Close Friends'));
    await tester.pumpAndSettle();
    expect(find.text('Circle circle-1'), findsOneWidget);
  });
}

const dm = SearchPlace(
  id: 'conv-1',
  type: ConversationType.direct,
  title: 'Ada Lovelace',
);

const general = SearchPlace(
  id: 'conv-2',
  type: ConversationType.channel,
  title: 'general',
  circleId: 'circle-1',
  circleName: 'Launch Crew',
);

SearchHit hit(
  String id,
  String conversationId,
  String sender,
  String body, {
  SearchPlace? place,
}) {
  return SearchHit(
    message: ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: 'u-$sender',
      type: MessageType.text,
      body: body,
      createdAt: DateTime(2026, 10, 1, 9, 30),
    ),
    senderName: sender,
    place: place,
  );
}

class FakeSearchRepository implements MessageSearchRepository {
  final pages = <SearchPage>[];
  final requests = <MessageSearchRequest>[];
  final contextFor = <String, SearchContext>{};
  final suggestionPrefixes = <String>[];
  var people = const <SearchPerson>[];
  var places = const <SearchPlace>[];

  @override
  Future<SearchPage> search(MessageSearchRequest request) async {
    requests.add(request);
    return pages.isEmpty ? const SearchPage(hits: []) : pages.removeAt(0);
  }

  @override
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) async => contextFor[messageId] ?? const SearchContext();

  @override
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    suggestionPrefixes.add(prefix);
    return [
      for (final person in people)
        if (person.username.startsWith(prefix.toLowerCase())) person,
    ];
  }

  @override
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async {
    suggestionPrefixes.add(prefix);
    return places;
  }
}

class MemoryRecentSearchesStore implements RecentSearchesStore {
  var stored = <String>[];
  final saved = <List<String>>[];

  @override
  Future<List<String>> load() async => stored;

  @override
  Future<void> save(List<String> searches) async {
    saved.add(searches);
    stored = searches;
  }
}

class FakeChatsRepository implements ChatsRepository {
  @override
  Future<void> createPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    required bool multi,
    int? durationHours,
  }) async {}

  @override
  Future<void> votePoll({
    required String messageId,
    required List<String> optionIds,
  }) async {}

  @override
  Future<void> endPoll({required String messageId}) async {}

  @override
  Future<bool> canModeratePolls(String conversationId) async => false;

  @override
  Future<List<Profile>> listPollVoters({
    required String messageId,
    required String optionId,
  }) async => const [];

  var searchResults = <MessageSearchResult>[];
  var discoveryResults = <DiscoveryResult>[];
  final searchQueries = <String>[];

  @override
  Future<List<MessageSearchResult>> searchMessages(String query) async {
    searchQueries.add(query);
    return searchResults;
  }

  @override
  Future<List<DiscoveryResult>> searchDiscovery(String query) async {
    searchQueries.add(query);
    return discoveryResults;
  }

  @override
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) async {
    return const [];
  }

  @override
  Future<List<ConversationSummary>> listConversations() async => const [];

  @override
  Future<ConversationSummary?> getConversationSummary(
    String conversationId,
  ) async {
    return null;
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<List<ConversationReadMarker>> listReadMarkers(
    String conversationId,
  ) async {
    return const [];
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) async {
    return 'conversation-for-$otherUserId';
  }

  @override
  Future<GroupDetail> getGroupDetail(String conversationId) async {
    return GroupDetail(
      conversationId: conversationId,
      title: conversationId,
      members: const [],
    );
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {}

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) async {}

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) async {}

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) async {}

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async {
    return 'https://example.com/${attachment.path}';
  }

  final sentFiles =
      <({String conversationId, String fileName, String mimeType, int size})>[];

  @override
  Future<void> sendFileMessage({
    required String conversationId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    sentFiles.add((
      conversationId: conversationId,
      fileName: fileName,
      mimeType: mimeType,
      size: bytes.length,
    ));
  }

  @override
  Future<String> createFileUrl(FileAttachment attachment) async {
    return 'https://files.test/${attachment.path}';
  }

  @override
  Future<String> createVoiceUrl(VoiceAttachment attachment) async {
    return 'https://example.com/${attachment.path}';
  }

  @override
  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) async {
    return 'group-conversation';
  }

  @override
  Future<void> renameGroupConversation({
    required String conversationId,
    required String title,
  }) async {}

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) async {}

  @override
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  }) async {
    return 'group-avatars/$conversationId/avatar.png';
  }

  @override
  Future<void> updateGroupProfile({
    required String conversationId,
    required String title,
    required String? avatarUrl,
    required String announcement,
  }) async {}

  @override
  Future<void> leaveGroupConversation(String conversationId) async {}

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required String memberId,
  }) async {}

  @override
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
  }) async {}

  @override
  Future<bool> canModerateMessages(String conversationId) async => false;

  @override
  Future<void> recallMessage({required String messageId}) async {}

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {}

  @override
  Future<void> toggleMessageReaction({
    required String messageId,
    required String emoji,
  }) async {}

  @override
  Future<List<Profile>> listMessageReactors({
    required String messageId,
    required String emoji,
  }) async {
    return const [];
  }

  @override
  Future<bool> canPinMessages(String conversationId) async => false;

  @override
  Future<void> pinMessage({required String messageId}) async {}

  @override
  Future<void> unpinMessage({required String messageId}) async {}

  @override
  Future<List<PinnedMessage>> listPinnedMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<LinkPreview?> getLinkPreview(String url) async => null;

  @override
  Future<void> setMessageSuppressEmbeds({
    required String messageId,
    required bool suppress,
  }) async {}

  @override
  Future<ConversationThread> createThread({
    required String parentConversationId,
    String? rootMessageId,
    String? title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ConversationThread>> listThreads(
    String parentConversationId,
  ) async => const [];

  @override
  Future<ConversationThread> setThreadArchived({
    required String threadId,
    required bool archived,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canManageThread(String threadId) async => false;

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> markConversationUnread(String conversationId) async {}

  @override
  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) async {}

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {}

  @override
  Future<void> hideConversation(String conversationId) async {}

  @override
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    return conversations;
  }

  @override
  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  ) {
    return messages;
  }

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  Stream<void> messageChanges(String conversationId) => const Stream.empty();

  @override
  Stream<void> threadChanges(String conversationId) => const Stream.empty();

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    return const Stream.empty();
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
