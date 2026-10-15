import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/gif_search.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/message.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

const _cat = GifResult(
  id: 'cat',
  url: 'https://media1.giphy.com/media/cat/giphy-downsized.gif',
  previewUrl: 'https://media1.giphy.com/media/cat/200w.gif',
  title: 'Happy cat',
);
const _dog = GifResult(
  id: 'dog',
  url: 'https://media1.giphy.com/media/dog/giphy-downsized.gif',
  previewUrl: 'https://media1.giphy.com/media/dog/200w.gif',
  title: 'Dog',
);

class _FakeGifSearch implements GifSearchRepository {
  _FakeGifSearch({this.notConfigured = false});

  final bool notConfigured;
  final queries = <String>[];

  @override
  Future<List<GifResult>> search(String query, {int offset = 0}) async {
    queries.add(query);
    if (notConfigured) {
      throw const GifNotConfiguredException();
    }
    return query.isEmpty ? [_cat, _dog] : [_dog];
  }
}

Widget _chat(
  chat_fakes.FakeChatsRepository repository,
  GifSearchRepository gifs,
) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(repository),
      gifSearchRepositoryProvider.overrideWithValue(gifs),
      composerDraftStoreProvider.overrideWithValue(
        InMemoryComposerDraftStore(),
      ),
      onlineUserIdsProvider.overrideWith(
        (ref) => const Stream<Set<String>>.empty(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeSettingsRepository(),
      ),
      authRepositoryProvider.overrideWithValue(
        chat_fakes.FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: const MaterialApp(
      home: ChatThreadScreen(conversationId: 'conversation-1'),
    ),
  );
}

void main() {
  test('only a lone GIPHY GIF address counts as a GIF message', () {
    expect(gifUrlIn(' ${_cat.url} '), _cat.url);
    expect(
      gifUrlIn('https://i.giphy.com/abc.gif'),
      'https://i.giphy.com/abc.gif',
    );
    expect(gifUrlIn('look ${_cat.url}'), isNull);
    expect(gifUrlIn('http://media1.giphy.com/media/cat/a.gif'), isNull);
    expect(gifUrlIn('https://example.com/cat.gif'), isNull);
    expect(gifUrlIn('https://media1.giphy.com/media/cat/a.gif?x=1'), isNull);
  });

  test('reads the function answer, dropping foreign addresses', () {
    expect(
      GifResult.fromJson({
        'id': 'cat',
        'url': _cat.url,
        'preview_url': _cat.previewUrl,
        'title': 'Happy cat',
        'width': 320,
        'height': 240,
      })?.previewUrl,
      _cat.previewUrl,
    );
    expect(
      GifResult.fromJson({'id': 'x', 'url': 'https://example.com/x.gif'}),
      isNull,
    );
  });

  testWidgets('the GIF button sends the picked GIF as its link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = chat_fakes.FakeChatsRepository();
    final gifs = _FakeGifSearch();
    await tester.pumpWidget(_chat(repository, gifs));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-gif-button')));
    await tester.pumpAndSettle();
    expect(find.text('Trending'), findsOneWidget);
    expect(find.byKey(const ValueKey('gif-cat')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('gif-search-field')),
      'dog',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(gifs.queries, ['', 'dog']);
    expect(find.byKey(const ValueKey('gif-cat')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('gif-dog')));
    await tester.pumpAndSettle();
    expect(repository.sentMessages.single.body, _dog.url);
  });

  testWidgets('without a provider key the picker says so and the button '
      'turns off', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _chat(
        chat_fakes.FakeChatsRepository(),
        _FakeGifSearch(notConfigured: true),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-gif-button')));
    await tester.pumpAndSettle();
    expect(
      find.text("GIF search isn't set up on this server yet."),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.byType(GifPickerSheet))).pop();
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('composer-gif-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('GIF messages show the GIF instead of the link', (tester) async {
    final repository = chat_fakes.FakeChatsRepository()
      ..messages = [
        ChatMessage(
          id: 'message-1',
          conversationId: 'conversation-1',
          senderId: 'user-2',
          type: MessageType.text,
          body: _cat.url,
          createdAt: DateTime.utc(2026, 10, 16),
        ),
      ];
    await tester.pumpWidget(_chat(repository, _FakeGifSearch()));
    await tester.pump();

    expect(find.byKey(const ValueKey('gif-message')), findsOneWidget);
    expect(repository.linkPreviewRequests, isEmpty);
  });
}
