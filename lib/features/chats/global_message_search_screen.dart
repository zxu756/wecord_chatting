import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/features/search/search_filter_bar.dart';
import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/features/search/search_results.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Message search: free text and filters (typed as `from:@ada` with
/// autocomplete, or picked from the chips), in one conversation, a circle
/// or everywhere, with results grouped by where they were sent.
class GlobalMessageSearchScreen extends ConsumerStatefulWidget {
  const GlobalMessageSearchScreen({
    this.launch = const MessageSearchLaunch(),
    super.key,
  });

  static const path = '/search/messages';

  /// Search opened from [conversationId] (and its [circleId]), offering
  /// "this channel", "this circle" and "everywhere".
  static String location({
    String? conversationId,
    String? conversationTitle,
    ConversationType? conversationType,
    String? circleId,
    String? circleName,
    String? query,
  }) {
    final params = <String, String>{
      'c': ?conversationId,
      'ct': ?conversationTitle,
      if (conversationType != null) 'ck': conversationType.name,
      'circle': ?circleId,
      'cn': ?circleName,
      if (query != null && query.trim().isNotEmpty) 'q': query,
    };
    return Uri(
      path: path,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static MessageSearchLaunch launchFrom(Map<String, String> params) {
    final kind = params['ck'];
    return MessageSearchLaunch(
      conversationId: params['c'],
      conversationTitle: params['ct'],
      conversationType: kind == null
          ? null
          : ConversationType.values.where((t) => t.name == kind).firstOrNull,
      circleId: params['circle'],
      circleName: params['cn'],
      query: params['q'],
    );
  }

  final MessageSearchLaunch launch;

  @override
  ConsumerState<GlobalMessageSearchScreen> createState() =>
      _GlobalMessageSearchScreenState();
}

/// Something to put in the search box from the suggestions under it.
sealed class _Suggestion {
  const _Suggestion();
}

class _OperatorSuggestion extends _Suggestion {
  const _OperatorSuggestion(this.operator);
  final SearchOperator operator;
}

class _PersonSuggestion extends _Suggestion {
  const _PersonSuggestion(this.person);
  final SearchPerson person;
}

class _PlaceSuggestion extends _Suggestion {
  const _PlaceSuggestion(this.place);
  final SearchPlace place;
}

class _ValueSuggestion extends _Suggestion {
  const _ValueSuggestion(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

class _PickDateSuggestion extends _Suggestion {
  const _PickDateSuggestion();
}

class _RecentSuggestion extends _Suggestion {
  const _RecentSuggestion(this.query);
  final String query;
}

class _GlobalMessageSearchScreenState
    extends ConsumerState<GlobalMessageSearchScreen> {
  late final _SearchFieldController _controller;
  final _focusNode = FocusNode(debugLabel: 'message-search');
  final _scrollController = ScrollController();
  final _loadMore = LoadMoreGate();
  var _focused = false;
  var _highlighted = 0;
  var _dismissedSuggestions = false;

  /// Suggestions fetched for the value being typed.
  String? _suggestionKey;
  List<_Suggestion> _asyncSuggestions = const [];
  Timer? _suggestionDebounce;

  MessageSearchController get _search =>
      ref.read(messageSearchControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _controller = _SearchFieldController();
    _controller.text = ref.read(messageSearchControllerProvider).input;
    _openLaunch();
    _controller.addListener(_handleTextChange);
    _focusNode.addListener(_handleFocusChange);
    _focusNode.onKeyEvent = _handleKey;
    _scrollController.addListener(_handleScroll);
    // Open with the keyboard up unless there are results to look at.
    if (ref.read(messageSearchControllerProvider).hits.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  /// Sets the search up for where it was opened from, after this frame
  /// (providers can't change while widgets build).
  void _openLaunch() {
    final launch = widget.launch;
    Future.microtask(() {
      if (!mounted || widget.launch != launch) {
        return;
      }
      _search.open(launch);
      final input = ref.read(messageSearchControllerProvider).input;
      if (input != _controller.text) {
        _setText(input);
      }
    });
  }

  @override
  void didUpdateWidget(covariant GlobalMessageSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launch != widget.launch) {
      _openLaunch();
    }
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _focused = _focusNode.hasFocus;
      if (_focused) {
        _dismissedSuggestions = false;
      }
    });
  }

  void _handleTextChange() {
    final text = _controller.text;
    if (text != ref.read(messageSearchControllerProvider).input) {
      _search.setInput(text);
      _dismissedSuggestions = false;
      _highlighted = 0;
    }
    _refreshAsyncSuggestions();
    setState(() {});
  }

  void _handleScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore.request(_search.loadMore);
    }
  }

  void _setText(String text, {int? cursor}) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor ?? text.length),
    );
  }

  void _applyEdit(SearchQueryEdit edit) {
    _setText(edit.text, cursor: edit.cursor);
  }

  int get _cursor {
    final selection = _controller.selection;
    return selection.isValid ? selection.baseOffset : _controller.text.length;
  }

  SearchCompletionContext? get _completion {
    if (!_focused || _dismissedSuggestions) {
      return null;
    }
    return searchCompletionAt(_controller.text, _cursor);
  }

  /// Suggestions for what is at the cursor, or recent searches and the
  /// filter options in an empty box.
  List<_Suggestion> _suggestions() {
    final completion = _completion;
    if (completion == null) {
      return const [];
    }
    switch (completion) {
      case OperatorCompletion(:final token, :final prefix):
        final operators = [
          for (final operator in SearchOperator.values)
            if (operator.keyword.startsWith(prefix))
              _OperatorSuggestion(operator),
        ];
        if (token == null && _controller.text.trim().isEmpty) {
          final recent = ref.read(recentSearchesProvider);
          return [
            for (final query in recent.take(5)) _RecentSuggestion(query),
            ...operators,
          ];
        }
        return token == null ? const [] : operators;
      case ValueCompletion(:final operator, :final prefix):
        final lower = prefix.toLowerCase();
        switch (operator) {
          case SearchOperator.from ||
              SearchOperator.mentions ||
              SearchOperator.inPlace:
            return _asyncSuggestions;
          case SearchOperator.has:
            return [
              for (final kind in SearchHas.values)
                if (kind.name.startsWith(lower))
                  _ValueSuggestion(
                    kind.name,
                    searchHasLabel(kind),
                    searchHasIcon(kind),
                  ),
            ];
          case SearchOperator.pinned:
            return [
              if ('true'.startsWith(lower))
                _ValueSuggestion('true', tr('Pinned'), Icons.push_pin_outlined),
              if ('false'.startsWith(lower))
                _ValueSuggestion(
                  'false',
                  tr('Not pinned'),
                  Icons.push_pin_outlined,
                ),
            ];
          case SearchOperator.before ||
              SearchOperator.after ||
              SearchOperator.during:
            final today = SearchDate.fromDateTime(DateTime.now());
            final yesterday = SearchDate.fromDateTime(
              DateTime.now().subtract(const Duration(days: 1)),
            );
            return [
              if (today.toString().startsWith(prefix))
                _ValueSuggestion(
                  today.toString(),
                  tr('Today'),
                  Icons.today_outlined,
                ),
              if (yesterday.toString().startsWith(prefix))
                _ValueSuggestion(
                  yesterday.toString(),
                  tr('Yesterday'),
                  Icons.event_outlined,
                ),
              const _PickDateSuggestion(),
            ];
        }
    }
  }

  /// People and places come from the server; fetch them once typing in a
  /// value settles.
  void _refreshAsyncSuggestions() {
    final completion = _completion;
    if (completion is! ValueCompletion ||
        !(completion.operator.takesPerson ||
            completion.operator == SearchOperator.inPlace)) {
      _suggestionDebounce?.cancel();
      _suggestionKey = null;
      if (_asyncSuggestions.isNotEmpty) {
        _asyncSuggestions = const [];
      }
      return;
    }
    final people = completion.operator.takesPerson;
    final key = '${people ? 'p' : 'c'}:${completion.prefix}';
    if (key == _suggestionKey) {
      return;
    }
    _suggestionKey = key;
    _suggestionDebounce?.cancel();
    _suggestionDebounce = Timer(const Duration(milliseconds: 150), () async {
      final repository = ref.read(messageSearchRepositoryProvider);
      final scope = ref.read(messageSearchControllerProvider).scope;
      try {
        final suggestions = people
            ? [
                for (final person in await repository.suggestPeople(
                  completion.prefix,
                  scope: scope,
                ))
                  _PersonSuggestion(person),
              ]
            : [
                for (final place in await repository.suggestPlaces(
                  completion.prefix,
                  scope: scope,
                ))
                  _PlaceSuggestion(place),
              ];
        if (!mounted || _suggestionKey != key) {
          return;
        }
        setState(() {
          _asyncSuggestions = suggestions;
          _highlighted = 0;
        });
      } catch (_) {
        if (mounted && _suggestionKey == key) {
          setState(() => _asyncSuggestions = const []);
        }
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = _suggestions();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && suggestions.isNotEmpty) {
      setState(() => _dismissedSuggestions = true);
      return KeyEventResult.handled;
    }
    if (suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlighted = (_highlighted + 1) % suggestions.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _highlighted =
            (_highlighted - 1 + suggestions.length) % suggestions.length,
      );
      return KeyEventResult.handled;
    }
    final completingValue = _completion is ValueCompletion;
    if (key == LogicalKeyboardKey.tab ||
        (key == LogicalKeyboardKey.enter && completingValue)) {
      unawaited(
        _applySuggestion(
          suggestions[_highlighted.clamp(0, suggestions.length - 1)],
        ),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _applySuggestion(_Suggestion suggestion) async {
    final text = _controller.text;
    final completion = _completion;
    switch (suggestion) {
      case _RecentSuggestion(:final query):
        _setText(query);
        _focusNode.unfocus();
        await _search.submit();
      case _OperatorSuggestion(:final operator):
        final token = completion is OperatorCompletion
            ? completion.token
            : null;
        final insert = '${operator.keyword}:';
        if (token == null) {
          final cursor = _cursor;
          final before = text.substring(0, cursor);
          final spacer = before.isEmpty || before.endsWith(' ') ? '' : ' ';
          final next = '$before$spacer$insert${text.substring(cursor)}';
          _setText(next, cursor: before.length + spacer.length + insert.length);
        } else {
          _applyEdit(
            SearchQueryEdit.replace(text, token, insert, trailingSpace: false),
          );
        }
      case _PersonSuggestion(:final person):
        if (completion is! ValueCompletion) {
          return;
        }
        _search.rememberPerson(person);
        _applyEdit(
          SearchQueryEdit.replace(
            text,
            completion.token,
            '${completion.operator.keyword}:'
            '${formatOperatorValue(completion.operator, person.username)}',
          ),
        );
      case _PlaceSuggestion(:final place):
        if (completion is! ValueCompletion) {
          return;
        }
        _search.rememberPlace(place);
        _applyEdit(
          SearchQueryEdit.replace(
            text,
            completion.token,
            '${SearchOperator.inPlace.keyword}:'
            '${formatOperatorValue(SearchOperator.inPlace, place.filterValue)}',
          ),
        );
      case _ValueSuggestion(:final value):
        if (completion is! ValueCompletion) {
          return;
        }
        _applyEdit(
          SearchQueryEdit.replace(
            text,
            completion.token,
            '${completion.operator.keyword}:$value',
          ),
        );
      case _PickDateSuggestion():
        if (completion is! ValueCompletion) {
          return;
        }
        final picked = await _pickDate(
          parseSearchDate(completion.prefix)?.startLocal,
        );
        if (picked == null || !mounted) {
          return;
        }
        _applyEdit(
          SearchQueryEdit.replace(
            _controller.text,
            completion.token,
            '${completion.operator.keyword}:$picked',
          ),
        );
        _focusNode.requestFocus();
    }
  }

  Future<SearchDate?> _pickDate(DateTime? initial) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    return picked == null ? null : SearchDate.fromDateTime(picked);
  }

  void _removeToken(SearchToken token) {
    _applyEdit(SearchQueryEdit.remove(_controller.text, token));
  }

  Future<void> _addFilter(SearchOperator operator) async {
    switch (operator) {
      case SearchOperator.from || SearchOperator.mentions:
        final person = await _pickPerson(operator);
        if (person == null || !mounted) {
          return;
        }
        _search.rememberPerson(person);
        _applyEdit(
          SearchQueryEdit.append(_controller.text, operator, person.username),
        );
      case SearchOperator.inPlace:
        final place = await _pickPlace();
        if (place == null || !mounted) {
          return;
        }
        _search.rememberPlace(place);
        _applyEdit(
          SearchQueryEdit.append(
            _controller.text,
            SearchOperator.inPlace,
            place.filterValue,
          ),
        );
      case SearchOperator.has:
        final kind = await _pickHas();
        if (kind == null || !mounted) {
          return;
        }
        _applyEdit(
          SearchQueryEdit.append(_controller.text, operator, kind.name),
        );
      case SearchOperator.pinned:
        _applyEdit(
          SearchQueryEdit.setSingle(_controller.text, operator, 'true'),
        );
      case SearchOperator.before ||
          SearchOperator.after ||
          SearchOperator.during:
        final choice = await _pickDateFilter();
        if (choice == null || !mounted) {
          return;
        }
        var text = _controller.text;
        // On a day replaces any range; before/after replace themselves.
        for (final other in [
          choice.$1,
          if (choice.$1 == SearchOperator.during) ...[
            SearchOperator.before,
            SearchOperator.after,
          ] else
            SearchOperator.during,
        ]) {
          text = SearchQueryEdit.setSingle(text, other, null).text;
        }
        _applyEdit(
          SearchQueryEdit.append(text, choice.$1, choice.$2.toString()),
        );
    }
  }

  Future<SearchPerson?> _pickPerson(SearchOperator operator) {
    final scope = ref.read(messageSearchControllerProvider).scope;
    final repository = ref.read(messageSearchRepositoryProvider);
    return showWeCordSheet<SearchPerson>(
      context,
      title: operator == SearchOperator.from
          ? tr('From a person')
          : tr('Mentions a person'),
      detents: const [0.6, 0.92],
      builder: (context, scrollController) => _PickerList<SearchPerson>(
        hint: tr('Search people'),
        scrollController: scrollController,
        load: (prefix) =>
            repository.suggestPeople(prefix, scope: scope, limit: 20),
        keyOf: (person) => person.id,
        tileBuilder: (context, person) => _SuggestionTile(
          leading: ResolvedAvatar(
            name: person.displayName,
            avatarUrl: person.avatarUrl,
            size: 34,
          ),
          title: person.displayName,
          subtitle: '@${person.username}',
          onTap: () => Navigator.of(context).pop(person),
        ),
      ),
    );
  }

  Future<SearchPlace?> _pickPlace() {
    final scope = ref.read(messageSearchControllerProvider).scope;
    final repository = ref.read(messageSearchRepositoryProvider);
    return showWeCordSheet<SearchPlace>(
      context,
      title: tr('In a channel or chat'),
      detents: const [0.6, 0.92],
      builder: (context, scrollController) => _PickerList<SearchPlace>(
        hint: tr('Search channels and chats'),
        scrollController: scrollController,
        load: (prefix) =>
            repository.suggestPlaces(prefix, scope: scope, limit: 20),
        keyOf: (place) => place.id,
        tileBuilder: (context, place) => _SuggestionTile(
          leading: SearchPlaceAvatar(place: place, size: 34),
          title: place.label,
          subtitle: place.subtitle,
          onTap: () => Navigator.of(context).pop(place),
        ),
      ),
    );
  }

  Future<SearchHas?> _pickHas() {
    return showWeCordSheet<SearchHas>(
      context,
      title: tr('Has'),
      builder: (context, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SettingsGroup(
            children: [
              for (final kind in SearchHas.values)
                SettingsRow(
                  key: ValueKey('search-has-${kind.name}'),
                  icon: searchHasIcon(kind),
                  title: searchHasLabel(kind),
                  value: 'has:${kind.name}',
                  onTap: () => Navigator.of(context).pop(kind),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<(SearchOperator, SearchDate)?> _pickDateFilter() {
    return showWeCordSheet<(SearchOperator, SearchDate)>(
      context,
      title: tr('Date'),
      builder: (context, _) => const _DateFilterPicker(),
    );
  }

  void _openHit(SearchHit hit) {
    ref.read(recentSearchesProvider.notifier).add(_controller.text);
    final place = hit.place;
    final conversation =
        place?.toSummary() ??
        ConversationSummary(
          id: hit.conversationId,
          type: ConversationType.direct,
          unreadCount: 0,
        );
    openConversationAtMessage(
      context,
      ref,
      conversation: conversation,
      messageId: hit.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final state = ref.watch(messageSearchControllerProvider);
    ref.watch(recentSearchesProvider);
    final parsed = ParsedSearchQuery.parse(_controller.text);
    final suggestions = _suggestions();
    final highlighted = suggestions.isEmpty
        ? -1
        : _highlighted.clamp(0, suggestions.length - 1);
    final scopes = state.scopes;

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(title: tr('Search')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: WeCordTextField(
                    fieldKey: const ValueKey('message-search-field'),
                    controller: _controller,
                    focusNode: _focusNode,
                    onPaper: true,
                    hint: switch (state.scope) {
                      ConversationScope(:final title?) => tr('Search {name}', {
                        'name': title,
                      }),
                      CircleScope(:final name?) => tr('Search {name}', {
                        'name': name,
                      }),
                      _ => tr('Search messages'),
                    },
                    prefixIcon: Icons.search_rounded,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      unawaited(_search.submit());
                    },
                    suffix: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('message-search-clear'),
                            tooltip: tr('Clear search'),
                            icon: Icon(
                              Icons.cancel_rounded,
                              size: 18,
                              color: c.faint,
                            ),
                            onPressed: () {
                              _setText('');
                              _focusNode.requestFocus();
                            },
                          ),
                  ),
                ),
                if (scopes.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: WeCordSegmented<MessageSearchScope>(
                      expand: true,
                      semanticLabel: tr('Search in'),
                      segments: [
                        for (final scope in scopes)
                          WeCordSegment(
                            value: scope,
                            label: searchScopeLabel(scope),
                            key: ValueKey(
                              'search-scope-${scope.toJson()['type']}',
                            ),
                          ),
                      ],
                      selected: state.scope,
                      onChanged: _search.setScope,
                    ),
                  ),
                const SizedBox(height: 8),
                SearchFilterBar(
                  parsed: parsed,
                  onRemove: _removeToken,
                  onAdd: (operator) => unawaited(_addFilter(operator)),
                ),
                Expanded(
                  child: suggestions.isNotEmpty
                      ? _SuggestionsPanel(
                          suggestions: suggestions,
                          highlighted: highlighted,
                          onPick: (suggestion) =>
                              unawaited(_applySuggestion(suggestion)),
                          onClearRecent:
                              suggestions.any((s) => s is _RecentSuggestion)
                              ? ref.read(recentSearchesProvider.notifier).clear
                              : null,
                        )
                      : _buildBody(context, state, parsed),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MessageSearchState state,
    ParsedSearchQuery parsed,
  ) {
    final c = context.tokens.colors;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    if (!parsed.hasCriteria) {
      return _RecentSearches(
        bottom: bottom,
        onPick: (query) {
          _setText(query);
          unawaited(_search.submit());
        },
        onShowOperators: () {
          _setText('');
          _focusNode.requestFocus();
        },
      );
    }
    if (state.isLoading && state.hits.isEmpty) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2.5, color: c.muted),
      );
    }
    if (state.error case final error? when state.hits.isEmpty) {
      return SearchHint(
        icon: Icons.error_outline_rounded,
        title: tr('Search failed'),
        text: error.toString(),
        action: WeCordButton(
          label: tr('Try again'),
          variant: WeCordButtonVariant.secondary,
          size: WeCordButtonSize.small,
          onPressed: () => unawaited(_search.search()),
        ),
      );
    }
    if (state.unresolved.isNotEmpty) {
      return SearchHint(
        icon: Icons.person_search_outlined,
        title: tr('No matches for that filter'),
        text: [
          for (final token in state.unresolved)
            token.operator == SearchOperator.inPlace
                ? tr('Nothing called "{name}" here.', {'name': token.value})
                : tr('No one called @{name} here.', {'name': token.value}),
        ].join('\n'),
      );
    }
    if (state.searchedInput == null && state.hits.isEmpty) {
      return const SizedBox.shrink();
    }
    final groups = groupSearchHits(state.hits);
    final terms = parsed.highlightTerms;
    final total = state.total ?? state.hits.length;
    final items = <Widget>[
      _ResultsSummary(
        total: total,
        capped: state.totalCapped,
        sort: state.sort,
        loading: state.isLoading,
        onSort: _search.setSort,
      ),
      if (state.discovery.isNotEmpty) _DiscoveryStrip(results: state.discovery),
      if (state.hits.isEmpty)
        SearchHint(
          icon: Icons.search_off_rounded,
          title: tr('No results'),
          text: state.scope is EverywhereScope
              ? tr('Try other words or fewer filters.')
              : tr('Try searching everywhere.'),
          action: state.scope is EverywhereScope
              ? null
              : WeCordButton(
                  label: tr('Search everywhere'),
                  variant: WeCordButtonVariant.secondary,
                  size: WeCordButtonSize.small,
                  onPressed: () => _search.setScope(const EverywhereScope()),
                ),
        ),
      for (final group in groups) ...[
        SearchGroupHeader(
          group: group,
          count: state.conversationCounts[group.conversationId],
        ),
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
            boxShadow: context.tokens.shadows.hairline,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, hit) in group.hits.indexed)
                SearchHitTile(
                  key: ValueKey('search-hit-tile-${hit.id}'),
                  hit: hit,
                  terms: terms,
                  first: index == 0,
                  last: index == group.hits.length - 1,
                  onOpen: () => _openHit(hit),
                ),
            ],
          ),
        ),
      ],
      if (state.isLoadingMore || state.hasMore)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: c.muted,
              ),
            ),
          ),
        )
      else if (state.hits.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Text(
            tr('That is everything.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.subtle),
          ),
        ),
    ];
    if (state.hasMore && !state.isLoadingMore) {
      // A short first page doesn't scroll; ask for more right away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent < 600) {
          _loadMore.request(_search.loadMore);
        }
      });
    }
    return ListView.builder(
      key: const ValueKey('message-search-results'),
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }
}

/// Colors operators (`from:@ada`) in the search box.
class _SearchFieldController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = value.composing;
    if (withComposing && composing.isValid && !composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final c = context.tokens.colors;
    final operators = tokenizeSearchQuery(
      text,
    ).where((token) => token.isOperator).toList();
    if (operators.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final children = <TextSpan>[];
    var at = 0;
    for (final token in operators) {
      if (token.start > at) {
        children.add(TextSpan(text: text.substring(at, token.start)));
      }
      children.add(
        TextSpan(
          text: text.substring(token.start, token.end),
          style: TextStyle(
            color: token.isValid ? c.accentText : c.dangerText,
            backgroundColor: token.isValid ? c.accentSoft : c.dangerSoft,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      at = token.end;
    }
    if (at < text.length) {
      children.add(TextSpan(text: text.substring(at)));
    }
    return TextSpan(style: style, children: children);
  }
}

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({
    required this.suggestions,
    required this.highlighted,
    required this.onPick,
    this.onClearRecent,
  });

  final List<_Suggestion> suggestions;
  final int highlighted;
  final ValueChanged<_Suggestion> onPick;
  final VoidCallback? onClearRecent;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final recent = <(int, _RecentSuggestion)>[];
    final rest = <(int, _Suggestion)>[];
    for (final (index, suggestion) in suggestions.indexed) {
      if (suggestion is _RecentSuggestion) {
        recent.add((index, suggestion));
      } else {
        rest.add((index, suggestion));
      }
    }
    Widget tile(int index, _Suggestion suggestion) {
      final selected = index == highlighted;
      void onTap() => onPick(suggestion);
      return switch (suggestion) {
        _RecentSuggestion(:final query) => _SuggestionTile(
          key: ValueKey('search-recent-$query'),
          leading: Icon(Icons.history_rounded, size: 20, color: c.muted),
          title: query,
          selected: selected,
          onTap: onTap,
        ),
        _OperatorSuggestion(:final operator) => _SuggestionTile(
          key: ValueKey('search-operator-${operator.keyword}'),
          leading: SettingsIconTile(
            icon: searchOperatorIcon(operator),
            size: 32,
          ),
          title: '${operator.keyword}:',
          subtitle: searchOperatorLabel(operator),
          trailing: Text(
            searchOperatorExample(operator),
            style: TextStyle(fontSize: 12, color: c.subtle),
          ),
          selected: selected,
          onTap: onTap,
        ),
        _PersonSuggestion(:final person) => _SuggestionTile(
          key: ValueKey('search-person-${person.id}'),
          leading: ResolvedAvatar(
            name: person.displayName,
            avatarUrl: person.avatarUrl,
            size: 32,
          ),
          title: person.displayName,
          subtitle: '@${person.username}',
          selected: selected,
          onTap: onTap,
        ),
        _PlaceSuggestion(:final place) => _SuggestionTile(
          key: ValueKey('search-place-${place.id}'),
          leading: SearchPlaceAvatar(place: place, size: 32),
          title: place.label,
          subtitle: place.subtitle,
          selected: selected,
          onTap: onTap,
        ),
        _ValueSuggestion(:final value, :final label, :final icon) =>
          _SuggestionTile(
            key: ValueKey('search-value-$value'),
            leading: SettingsIconTile(icon: icon, size: 32),
            title: label,
            trailing: Text(
              value,
              style: TextStyle(fontSize: 12, color: c.subtle),
            ),
            selected: selected,
            onTap: onTap,
          ),
        _PickDateSuggestion() => _SuggestionTile(
          key: const ValueKey('search-pick-date'),
          leading: const SettingsIconTile(
            icon: Icons.calendar_month_outlined,
            size: 32,
          ),
          title: tr('Pick a date…'),
          selected: selected,
          onTap: onTap,
        ),
      };
    }

    return ListView(
      key: const ValueKey('message-search-suggestions'),
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (recent.isNotEmpty) ...[
          SettingsSectionHeader(
            tr('Recent searches'),
            trailing: onClearRecent == null
                ? null
                : TextButton(
                    key: const ValueKey('search-clear-recent'),
                    onPressed: onClearRecent,
                    child: Text(tr('Clear')),
                  ),
          ),
          _SuggestionGroup(children: [for (final (i, s) in recent) tile(i, s)]),
        ],
        if (rest.isNotEmpty) ...[
          SettingsSectionHeader(
            rest.first.$2 is _OperatorSuggestion
                ? tr('Search options')
                : tr('Suggestions'),
          ),
          _SuggestionGroup(children: [for (final (i, s) in rest) tile(i, s)]),
        ],
      ],
    );
  }
}

class _SuggestionGroup extends StatelessWidget {
  const _SuggestionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        boxShadow: context.tokens.shadows.hairline,
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.selected = false,
    super.key,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onTap,
      pressedScale: 1,
      selected: selected,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? c.raised
                : c.ink.withValues(alpha: hovered ? 0.035 : 0),
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                  ],
                ),
              ),
              if (trailing case final trailing?) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A search field over a list loaded for what is typed (people, places).
class _PickerList<T> extends StatefulWidget {
  const _PickerList({
    required this.hint,
    required this.load,
    required this.keyOf,
    required this.tileBuilder,
    this.scrollController,
  });

  final String hint;
  final Future<List<T>> Function(String prefix) load;
  final String Function(T item) keyOf;
  final Widget Function(BuildContext context, T item) tileBuilder;
  final ScrollController? scrollController;

  @override
  State<_PickerList<T>> createState() => _PickerListState<T>();
}

class _PickerListState<T> extends State<_PickerList<T>> {
  Timer? _debounce;
  late Future<List<T>> _items = widget.load('');

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: WeCordTextField(
            fieldKey: const ValueKey('search-picker-field'),
            hint: widget.hint,
            prefixIcon: Icons.search_rounded,
            autofocus: true,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 150), () {
                if (mounted) {
                  setState(() => _items = widget.load(value.trim()));
                }
              });
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<T>>(
            future: _items,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const [];
              if (snapshot.connectionState != ConnectionState.done &&
                  items.isEmpty) {
                return Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.muted,
                  ),
                );
              }
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    tr('No matches'),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                );
              }
              return ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  for (final item in items)
                    KeyedSubtree(
                      key: ValueKey('search-picker-${widget.keyOf(item)}'),
                      child: widget.tileBuilder(context, item),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Before / On / After a day picked on a calendar.
class _DateFilterPicker extends StatefulWidget {
  const _DateFilterPicker();

  @override
  State<_DateFilterPicker> createState() => _DateFilterPickerState();
}

class _DateFilterPickerState extends State<_DateFilterPicker> {
  var _operator = SearchOperator.during;
  var _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordSegmented<SearchOperator>(
            expand: true,
            segments: [
              WeCordSegment(
                value: SearchOperator.before,
                label: tr('Before'),
                key: const ValueKey('search-date-before'),
              ),
              WeCordSegment(
                value: SearchOperator.during,
                label: tr('On'),
                key: const ValueKey('search-date-during'),
              ),
              WeCordSegment(
                value: SearchOperator.after,
                label: tr('After'),
                key: const ValueKey('search-date-after'),
              ),
            ],
            selected: _operator,
            onChanged: (value) => setState(() => _operator = value),
          ),
          CalendarDatePicker(
            initialDate: _date,
            firstDate: DateTime(2015),
            lastDate: DateTime(now.year + 1, 12, 31),
            onDateChanged: (value) => setState(() => _date = value),
          ),
          WeCordButton(
            key: const ValueKey('search-date-apply'),
            label: tr('Apply'),
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () => Navigator.of(
              context,
            ).pop((_operator, SearchDate.fromDateTime(_date))),
          ),
        ],
      ),
    );
  }
}

/// "128 results" and the sort menu.
class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({
    required this.total,
    required this.capped,
    required this.sort,
    required this.loading,
    required this.onSort,
  });

  final int total;
  final bool capped;
  final MessageSearchSort sort;
  final bool loading;
  final ValueChanged<MessageSearchSort> onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              searchTotalLabel(total, capped: capped),
              key: const ValueKey('message-search-total'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.subtle,
                ),
              ),
            ),
          PopupMenuButton<MessageSearchSort>(
            key: const ValueKey('message-search-sort'),
            tooltip: tr('Sort results'),
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => [
              for (final option in MessageSearchSort.values)
                PopupMenuItem(
                  key: ValueKey('message-search-sort-${option.name}'),
                  value: option,
                  child: Text(option.label),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, size: 16, color: c.accentText),
                  const SizedBox(width: 4),
                  Text(
                    sort.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.accentText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent searches (with Clear) and a hint at the filters, in place of
/// results while the box is empty.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({
    required this.bottom,
    required this.onPick,
    required this.onShowOperators,
  });

  final double bottom;
  final ValueChanged<String> onPick;
  final VoidCallback onShowOperators;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final recent = ref.watch(recentSearchesProvider);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
      children: [
        if (recent.isNotEmpty) ...[
          SettingsSectionHeader(
            tr('Recent searches'),
            trailing: TextButton(
              key: const ValueKey('search-clear-recent'),
              onPressed: ref.read(recentSearchesProvider.notifier).clear,
              child: Text(tr('Clear')),
            ),
          ),
          _SuggestionGroup(
            children: [
              for (final query in recent)
                _SuggestionTile(
                  key: ValueKey('search-recent-$query'),
                  leading: Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: c.muted,
                  ),
                  title: query,
                  trailing: WeCordIconButton(
                    icon: Icons.close_rounded,
                    tooltip: tr('Remove'),
                    size: 28,
                    iconSize: 16,
                    variant: WeCordButtonVariant.ghost,
                    onPressed: () =>
                        ref.read(recentSearchesProvider.notifier).remove(query),
                  ),
                  onTap: () => onPick(query),
                ),
            ],
          ),
        ] else
          SearchHint(
            icon: Icons.manage_search_rounded,
            title: tr('Search messages'),
            text: tr(
              'Find words and phrases, or narrow it down with from:, in:, '
              'has: and dates.',
            ),
            action: WeCordButton(
              label: tr('Show search options'),
              variant: WeCordButtonVariant.onPaper,
              size: WeCordButtonSize.small,
              onPressed: onShowOperators,
            ),
          ),
      ],
    );
  }
}

/// People, groups, circles and channels named like the search.
class _DiscoveryStrip extends StatelessWidget {
  const _DiscoveryStrip({required this.results});

  final List<DiscoveryResult> results;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('People and places')),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: results.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final result = results[index];
              final person = result.type == DiscoveryResultType.contact;
              return WeCordPressable(
                key: ValueKey('search-discovery-${result.id}'),
                onPressed: () => _openDiscoveryResult(context, result),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                builder: (context, states) => Container(
                  width: 96,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.panel,
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                    boxShadow: context.tokens.shadows.hairline,
                  ),
                  child: Column(
                    children: [
                      if (result.type == DiscoveryResultType.circleChannel)
                        const SettingsIconTile(
                          icon: Icons.tag_rounded,
                          size: 36,
                        )
                      else
                        ResolvedAvatar(
                          name: result.title,
                          avatarUrl: null,
                          size: 36,
                          squircle: !person,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        result.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

void _openDiscoveryResult(BuildContext context, DiscoveryResult result) {
  switch (result.type) {
    case DiscoveryResultType.circle:
      context.go('${CircleRoutes.path}/${result.circleId ?? result.id}');
    case DiscoveryResultType.contact:
    case DiscoveryResultType.group:
    case DiscoveryResultType.circleChannel:
    case DiscoveryResultType.message:
      final conversationId = result.conversationId;
      if (result.circleId case final circleId? when conversationId != null) {
        context.go(circleLocation(circleId, conversationId: conversationId));
      } else if (conversationId != null) {
        openPage(context, '${ChatsScreen.path}/$conversationId');
      } else if (result.type == DiscoveryResultType.contact) {
        openPage(context, '${UserProfileScreen.path}/${result.id}');
      }
  }
}
