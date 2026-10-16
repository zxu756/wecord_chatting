import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';

/// Where search was opened from, which decides the scopes it offers.
class MessageSearchLaunch {
  const MessageSearchLaunch({
    this.conversationId,
    this.conversationTitle,
    this.conversationType,
    this.circleId,
    this.circleName,
    this.query,
  });

  final String? conversationId;
  final String? conversationTitle;
  final ConversationType? conversationType;
  final String? circleId;
  final String? circleName;

  /// Text to start with.
  final String? query;

  /// Narrowest first, everywhere last.
  List<MessageSearchScope> get scopes => [
    if (conversationId case final id?)
      ConversationScope(
        conversationId: id,
        title: conversationTitle,
        type: conversationType,
      ),
    if (circleId case final id?) CircleScope(circleId: id, name: circleName),
    const EverywhereScope(),
  ];

  @override
  bool operator ==(Object other) =>
      other is MessageSearchLaunch &&
      other.conversationId == conversationId &&
      other.circleId == circleId &&
      other.query == query;

  @override
  int get hashCode => Object.hash(conversationId, circleId, query);
}

class MessageSearchState {
  const MessageSearchState({
    this.input = '',
    this.scopes = const [EverywhereScope()],
    this.scope = const EverywhereScope(),
    this.sort = MessageSearchSort.newest,
    this.hits = const [],
    this.conversationCounts = const {},
    this.total,
    this.totalCapped = false,
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.unresolved = const [],
    this.searchedInput,
    this.discovery = const [],
  });

  /// The search box text.
  final String input;
  final List<MessageSearchScope> scopes;
  final MessageSearchScope scope;
  final MessageSearchSort sort;
  final List<SearchHit> hits;
  final Map<String, int> conversationCounts;
  final int? total;
  final bool totalCapped;
  final Map<String, dynamic>? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  /// Filter values that matched no one and nothing (`from:@nobody`).
  final List<SearchToken> unresolved;

  /// The input the results are for; null before any search.
  final String? searchedInput;

  /// People, groups, circles and channels named like the text (searching
  /// everywhere without filters).
  final List<DiscoveryResult> discovery;

  ParsedSearchQuery get parsed => ParsedSearchQuery.parse(input);

  bool get hasMore => nextCursor != null;

  MessageSearchState copyWith({
    String? input,
    List<MessageSearchScope>? scopes,
    MessageSearchScope? scope,
    MessageSearchSort? sort,
    List<SearchHit>? hits,
    Map<String, int>? conversationCounts,
    int? Function()? total,
    bool? totalCapped,
    Map<String, dynamic>? Function()? nextCursor,
    bool? isLoading,
    bool? isLoadingMore,
    Object? Function()? error,
    List<SearchToken>? unresolved,
    String? Function()? searchedInput,
    List<DiscoveryResult>? discovery,
  }) {
    return MessageSearchState(
      input: input ?? this.input,
      scopes: scopes ?? this.scopes,
      scope: scope ?? this.scope,
      sort: sort ?? this.sort,
      hits: hits ?? this.hits,
      conversationCounts: conversationCounts ?? this.conversationCounts,
      total: total == null ? this.total : total(),
      totalCapped: totalCapped ?? this.totalCapped,
      nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error == null ? this.error : error(),
      unresolved: unresolved ?? this.unresolved,
      searchedInput: searchedInput == null
          ? this.searchedInput
          : searchedInput(),
      discovery: discovery ?? this.discovery,
    );
  }
}

/// The message search screen's state. It outlives the screen, so leaving
/// for a result and coming back finds the same search.
final messageSearchControllerProvider =
    NotifierProvider<MessageSearchController, MessageSearchState>(
      MessageSearchController.new,
    );

class MessageSearchController extends Notifier<MessageSearchState> {
  /// How long typing settles before searching.
  static const debounce = Duration(milliseconds: 300);

  Timer? _debounce;
  var _generation = 0;
  MessageSearchLaunch? _launch;

  /// Picked from suggestions: `from:`/`mentions:` handle or `in:` name
  /// (lower case) to what was picked.
  final _people = <String, SearchPerson>{};
  final _places = <String, List<SearchPlace>>{};

  @override
  MessageSearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const MessageSearchState();
  }

  MessageSearchRepository get _repository =>
      ref.read(messageSearchRepositoryProvider);

  /// Sets up for [launch]; the same launch again keeps the last search.
  void open(MessageSearchLaunch launch) {
    if (_launch == launch) {
      return;
    }
    _launch = launch;
    _debounce?.cancel();
    _generation++;
    final scopes = launch.scopes;
    state = MessageSearchState(
      input: launch.query ?? '',
      scopes: scopes,
      scope: scopes.first,
      sort: state.sort,
    );
    if (state.parsed.hasCriteria) {
      unawaited(search());
    }
  }

  void rememberPerson(SearchPerson person) {
    _people[person.username.toLowerCase()] = person;
  }

  void rememberPlace(SearchPlace place) {
    final key = place.filterValue.toLowerCase();
    _places[key] = [
      ...?_places[key]?.where((existing) => existing.id != place.id),
      place,
    ];
  }

  /// The text changed: search once typing settles.
  void setInput(String input) {
    if (input == state.input) {
      return;
    }
    state = state.copyWith(input: input);
    _debounce?.cancel();
    if (!state.parsed.hasCriteria) {
      _generation++;
      state = state.copyWith(
        hits: const [],
        conversationCounts: const {},
        total: () => null,
        nextCursor: () => null,
        isLoading: false,
        isLoadingMore: false,
        error: () => null,
        unresolved: const [],
        searchedInput: () => null,
        discovery: const [],
      );
      return;
    }
    _debounce = Timer(debounce, () => unawaited(search()));
  }

  /// Searches now (Enter) and remembers the search on this device.
  Future<void> submit() async {
    _debounce?.cancel();
    if (!state.parsed.hasCriteria) {
      return;
    }
    ref.read(recentSearchesProvider.notifier).add(state.input);
    await search();
  }

  void setScope(MessageSearchScope scope) {
    if (scope == state.scope) {
      return;
    }
    state = state.copyWith(scope: scope);
    _researchIfSearched();
  }

  void setSort(MessageSearchSort sort) {
    if (sort == state.sort) {
      return;
    }
    state = state.copyWith(sort: sort);
    _researchIfSearched();
  }

  void _researchIfSearched() {
    if (state.parsed.hasCriteria) {
      _debounce?.cancel();
      unawaited(search());
    }
  }

  /// Runs the search in the box from the first page.
  Future<void> search() async {
    final generation = ++_generation;
    final input = state.input;
    final parsed = ParsedSearchQuery.parse(input);
    if (!parsed.hasCriteria) {
      return;
    }
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      error: () => null,
    );
    try {
      final (filters, unresolved) = await _resolve(parsed);
      if (generation != _generation) {
        return;
      }
      if (unresolved.isNotEmpty) {
        state = state.copyWith(
          hits: const [],
          conversationCounts: const {},
          total: () => 0,
          totalCapped: false,
          nextCursor: () => null,
          isLoading: false,
          unresolved: unresolved,
          searchedInput: () => input,
          discovery: const [],
        );
        return;
      }
      final request = MessageSearchRequest(
        text: parsed.text,
        filters: filters,
        scope: state.scope,
        sort: state.sort,
      );
      final discovery = _discover(parsed);
      final page = await _repository.search(request);
      final people = await discovery;
      if (generation != _generation) {
        return;
      }
      _lastRequest = request;
      state = state.copyWith(
        hits: page.hits,
        conversationCounts: page.conversationCounts,
        total: () => page.total,
        totalCapped: page.totalCapped,
        nextCursor: () => page.nextCursor,
        isLoading: false,
        unresolved: const [],
        searchedInput: () => input,
        discovery: people,
      );
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: () => error,
        searchedInput: () => input,
      );
    }
  }

  MessageSearchRequest? _lastRequest;

  /// The next page, for infinite scroll.
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    final request = _lastRequest;
    if (cursor == null ||
        request == null ||
        state.isLoading ||
        state.isLoadingMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repository.search(request.nextPage(cursor));
      if (generation != _generation) {
        return;
      }
      final seen = {for (final hit in state.hits) hit.id};
      state = state.copyWith(
        hits: [
          ...state.hits,
          for (final hit in page.hits)
            if (seen.add(hit.id)) hit,
        ],
        nextCursor: () => page.nextCursor,
        isLoadingMore: false,
      );
    } catch (error) {
      if (generation != _generation) {
        return;
      }
      state = state.copyWith(isLoadingMore: false, error: () => error);
    }
  }

  Future<List<DiscoveryResult>> _discover(ParsedSearchQuery parsed) async {
    final text = parsed.text.trim();
    if (state.scope is! EverywhereScope ||
        parsed.operatorTokens.isNotEmpty ||
        text.isEmpty ||
        text.startsWith('-')) {
      return const [];
    }
    try {
      final results = await ref
          .read(chatsRepositoryProvider)
          .searchDiscovery(parsed.highlightTerms.join(' '));
      return [
        for (final result in results)
          if (result.type != DiscoveryResultType.message) result,
      ].take(6).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Turns `from:@ada` and `in:#general` into ids: what was picked from
  /// suggestions, else exact matches among the suggestions for the name.
  Future<(MessageSearchFilters, List<SearchToken>)> _resolve(
    ParsedSearchQuery parsed,
  ) async {
    final unresolved = <SearchToken>[];
    Future<List<String>> people(SearchOperator operator) async {
      final ids = <String>{};
      for (final token in parsed.tokensFor(operator)) {
        final person = await _resolvePerson(token.value);
        if (person == null) {
          unresolved.add(token);
        } else {
          ids.add(person.id);
        }
      }
      return ids.toList();
    }

    final fromIds = await people(SearchOperator.from);
    final mentionIds = await people(SearchOperator.mentions);
    final placeIds = <String>{};
    for (final token in parsed.tokensFor(SearchOperator.inPlace)) {
      final places = await _resolvePlaces(token.value);
      if (places.isEmpty) {
        unresolved.add(token);
      } else {
        placeIds.addAll(places.map((place) => place.id));
      }
    }
    return (
      MessageSearchFilters(
        fromIds: fromIds,
        mentionIds: mentionIds,
        placeIds: placeIds.toList(),
        has: parsed.has,
        before: parsed.dateFor(SearchOperator.before),
        after: parsed.dateFor(SearchOperator.after),
        during: parsed.dateFor(SearchOperator.during),
        pinned: parsed.pinned,
      ),
      unresolved,
    );
  }

  Future<SearchPerson?> _resolvePerson(String handle) async {
    final key = handle.toLowerCase();
    final picked = _people[key];
    if (picked != null) {
      return picked;
    }
    final candidates = await _repository.suggestPeople(
      handle,
      scope: state.scope,
      limit: 20,
    );
    final match =
        candidates
            .where((person) => person.username.toLowerCase() == key)
            .firstOrNull ??
        candidates
            .where((person) => person.displayName.toLowerCase() == key)
            .firstOrNull;
    if (match != null) {
      _people[key] = match;
    }
    return match;
  }

  Future<List<SearchPlace>> _resolvePlaces(String name) async {
    final key = name.toLowerCase();
    final picked = _places[key];
    if (picked != null && picked.isNotEmpty) {
      return picked;
    }
    final candidates = await _repository.suggestPlaces(
      name,
      scope: state.scope,
      limit: 20,
    );
    return [
      for (final place in candidates)
        if (place.filterValue.toLowerCase() == key || place.id == name) place,
    ];
  }
}
