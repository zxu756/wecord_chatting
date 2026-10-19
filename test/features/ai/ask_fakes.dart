import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ask/ask_models.dart';
import 'package:wecord/features/ai/ask/ask_repository.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/shared/models/conversation.dart';

import 'ai_fakes.dart';

/// An [AskRepository] for tests: the answers are set up front, calls recorded.
class FakeAskRepository implements AskRepository {
  FakeAskRepository({List<AskAnswer>? answers})
    : answers = answers ?? [sampleAnswer()];

  /// Handed out in order; the last one repeats.
  final List<AskAnswer> answers;

  /// Thrown instead of an answer when set.
  Object? error;

  /// Holds the next answer until completed (for the loading state).
  Completer<void>? gate;

  final calls = <({String question, MessageSearchScope scope})>[];

  @override
  Future<AskAnswer> ask({
    required String question,
    required MessageSearchScope scope,
    AiLanguage? language,
    DateTime? now,
  }) async {
    calls.add((question: question, scope: scope));
    await gate?.future;
    if (error case final error?) {
      throw error;
    }
    final index = calls.length - 1;
    return answers[index < answers.length ? index : answers.length - 1];
  }
}

const sampleGroup = SearchPlace(
  id: 'conv-plan',
  type: ConversationType.group,
  title: 'Weekend plan',
);

const sampleChannel = SearchPlace(
  id: 'conv-general',
  type: ConversationType.channel,
  title: 'general',
  circleId: 'circle-1',
  circleName: 'Hikers',
);

AskSource sampleSource(
  int n, {
  String id = 'm1',
  String sender = 'Cy',
  String snippet = 'The dinner is at Haidilao on Friday',
  SearchPlace? place = sampleGroup,
}) {
  return AskSource(
    n: n,
    messageId: id,
    conversationId: place?.id ?? 'conv-x',
    sender: sender,
    snippet: snippet,
    createdAt: DateTime(2026, 10, 16, 18, 5),
    place: place,
  );
}

AskAnswer sampleAnswer() {
  return AskAnswer(
    found: true,
    answer:
        'Cy said the dinner is at Haidilao on Friday [1]. Ada confirmed '
        'it starts at 7pm [2].',
    sources: [
      sampleSource(1),
      sampleSource(
        2,
        id: 'm2',
        sender: 'Ada',
        snippet: '7pm works, bring cash',
        place: sampleChannel,
      ),
    ],
  );
}

/// A search repository that finds nothing and records that it was used.
class QuietSearchRepository implements MessageSearchRepository {
  final requests = <MessageSearchRequest>[];

  @override
  Future<SearchPage> search(MessageSearchRequest request) async {
    requests.add(request);
    return const SearchPage(hits: []);
  }

  @override
  Future<SearchContext> context(
    String messageId, {
    int before = 1,
    int after = 1,
  }) async => const SearchContext();

  @override
  Future<List<SearchPerson>> suggestPeople(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async => const [];

  @override
  Future<List<SearchPlace>> suggestPlaces(
    String prefix, {
    MessageSearchScope scope = const EverywhereScope(),
    int limit = 8,
  }) async => const [];
}

class MemoryRecents implements RecentSearchesStore {
  var stored = <String>[];

  @override
  Future<List<String>> load() async => stored;

  @override
  Future<void> save(List<String> searches) async => stored = searches;
}

/// The overrides that make Ask AI available: AI is set up on the server and
/// the person has it on.
List<Override> askOverrides(
  FakeAskRepository ask, {
  FakeAiRepository? ai,
  QuietSearchRepository? search,

  /// False: the server has no AI (the default repository).
  bool aiSetUp = true,
}) => [
  askRepositoryProvider.overrideWithValue(ask),
  if (aiSetUp) aiRepositoryProvider.overrideWithValue(ai ?? FakeAiRepository()),
  aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
  messageSearchRepositoryProvider.overrideWithValue(
    search ?? QuietSearchRepository(),
  ),
  recentSearchesStoreProvider.overrideWithValue(MemoryRecents()),
];
