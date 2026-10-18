import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chain/chain_fakes.dart';
import '../file_preview/file_preview_fakes.dart';
import '../location/location_fakes.dart';
import '../wallpapers/wallpaper_fakes.dart';
import 'chat_thread_screen_test.dart' as thread_test;
import 'paged_chat_fakes.dart';

/// A 1,000 message group conversation with every kind of content the chat
/// draws, for the performance tests (`message_list_mixed_benchmark_test`
/// measures it, `message_list_rebuild_test` guards it).
///
/// Per 24 messages: plain text, Markdown, a reply, a picture, an album of
/// three, a voice message, and a chain, location, contact, chat history,
/// note and file card; every ninth message has reactions.
const mixedMessageCount = 1000;

final mixedStart = DateTime.utc(2026, 3, 1, 8);

Map<String, dynamic> _image(int index, (int, int) size) => {
  'kind': 'image',
  'bucket': 'chat-images',
  'path': 'pics/$index.jpg',
  'mime_type': 'image/jpeg',
  'size': 250000,
  'width': size.$1,
  'height': size.$2,
};

List<Map<String, dynamic>> mixedRows({
  int count = mixedMessageCount,

  /// Only these kinds (slots of the 24 message cycle), for measuring one
  /// kind of content on its own.
  List<int>? slots,

  /// The pixel size the pictures say they have (and the fake server's are).
  (int, int) imageSize = (96, 128),
}) {
  final rows = <Map<String, dynamic>>[];
  for (var index = 0; index < count; index++) {
    final mine = index % 3 == 0;
    final sender = mine ? 'user-1' : 'user-${2 + index % 3}';
    final slot = slots == null ? index % 24 : slots[index % slots.length];
    var type = 'text';
    String body = 'Message number $index';
    Map<String, dynamic>? attachment;
    Map<String, dynamic>? extra;
    switch (slot) {
      case 1:
        body =
            '**Update $index** with `code`, a [link](https://wecord.test) '
            'and a _longer_ line of text that wraps over two lines on a phone';
      case 2:
        extra = {
          'reply_to_message_id':
              'message-${(index - 1).toString().padLeft(5, '0')}',
          'reply_preview': {
            'message_id': 'message-${(index - 1).toString().padLeft(5, '0')}',
            'sender_name': 'Ada',
            'body': 'Message number ${index - 1}',
            'type': 'text',
          },
        };
        body = 'A reply to the one above';
      case 3:
        type = 'image';
        body = 'Image';
        attachment = _image(index, imageSize);
      case 4 || 5 || 6:
        // An album of three from one sender.
        type = 'image';
        body = 'Image';
        attachment = _image(index, imageSize);
        extra = {
          'attachment_group_id': 'album-${index ~/ (slots?.length ?? 24)}',
        };
      case 7:
        type = 'voice';
        body = 'Voice message';
        attachment = {
          'kind': 'voice',
          'bucket': 'chat-voice',
          'path': 'voice/$index.m4a',
          'mime_type': 'audio/mp4',
          'size': 40000,
          'duration_ms': 6400,
        };
      case 8:
        body = 'Chain: Saturday hike';
        attachment = {
          'kind': 'chain',
          'chain_id': 'chain-${index ~/ 24}',
          'title': 'Saturday hike sign-up',
        };
      case 9:
        body = 'Location: Cuba Street';
        attachment = {
          'kind': 'location',
          'lat': -41.29 + index / 100000,
          'lng': 174.77,
          'name': 'Cuba Street',
          'address': 'Te Aro, Wellington',
        };
      case 10:
        body = 'Contact card: Ada';
        attachment = {
          'kind': 'contact_card',
          'card': 'user',
          'user_id': 'user-9',
          'name': 'Ada Lovelace',
          'username': 'ada',
        };
      case 11:
        body = 'Chat history: Hike club';
        attachment = {
          'kind': 'chat_history',
          'title': 'Hike club',
          'count': 4,
          'preview': [
            {'name': 'Ada', 'kind': 'text', 'text': 'See you at 9'},
            {'name': 'Bob', 'kind': 'image', 'text': ''},
          ],
        };
      case 12:
        body = 'Note: Packing list';
        attachment = {
          'kind': 'note',
          'note_id': 'note-${index ~/ 24}',
          'title': 'Packing list',
        };
      case 13:
        type = 'file';
        body = 'plan.pdf';
        attachment = {
          'kind': 'file',
          'bucket': 'chat-files',
          'path': 'files/$index.pdf',
          'name': 'plan.pdf',
          'mime_type': 'application/pdf',
          'size': 120000,
        };
    }
    rows.add({
      ...messageRow(
        index,
        id: 'message-${index.toString().padLeft(5, '0')}',
        senderId: sender,
        body: body,
        type: type,
        attachment: attachment,
        createdAt: mixedStart.add(Duration(minutes: index * 7)),
      ),
      ...?extra,
      'reactions': index % 9 == 0
          ? const [
              {'emoji': '👍', 'count': 2},
              {'emoji': '❤️', 'count': 1},
            ]
          : const <Object?>[],
    });
  }
  return rows;
}

/// Counts what rebuilds, by widget type, between [start] and [stop].
class RebuildCounter {
  final byType = <String, int>{};
  var total = 0;
  var _running = false;

  void start() {
    byType.clear();
    total = 0;
    _running = true;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (!_running) {
        return;
      }
      total += 1;
      final name = element.widget.runtimeType.toString();
      byType[name] = (byType[name] ?? 0) + 1;
    };
  }

  void stop() {
    _running = false;
    debugOnRebuildDirtyWidget = null;
  }

  int of(String type) => byType[type] ?? 0;

  /// The widgets whose type name matches [pattern], summed.
  int matching(Pattern pattern) {
    var sum = 0;
    byType.forEach((name, count) {
      if (name.contains(pattern)) {
        sum += count;
      }
    });
    return sum;
  }

  String summary({int top = 6}) {
    final sorted = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return '$total rebuilt'
        '${sorted.isEmpty ? '' : ' (${sorted.take(top).map((e) => '${e.key} ${e.value}').join(', ')})'}';
  }
}

/// Counts providers created, updated and disposed, by name (with the family
/// argument for the ones that have one): a provider created many times, or
/// updated on every tick, shows up here.
base class ProviderCounter extends ProviderObserver {
  final added = <String, int>{};
  final updated = <String, int>{};
  final disposed = <String, int>{};

  String _name(ProviderObserverContext context) {
    final provider = context.provider;
    final name = provider.name ?? provider.runtimeType.toString();
    final argument = provider.argument;
    return argument == null ? name : '$name($argument)';
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final key = _name(context);
    added[key] = (added[key] ?? 0) + 1;
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    final key = _name(context);
    updated[key] = (updated[key] ?? 0) + 1;
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    final key = _name(context);
    disposed[key] = (disposed[key] ?? 0) + 1;
  }

  void clear() {
    added.clear();
    updated.clear();
    disposed.clear();
  }

  static String top(Map<String, int> counts, {int n = 12}) {
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => '${e.key} x${e.value}').join(', ');
  }
}

/// Drafts in memory that count the writes (each is a write of every draft to
/// the device's storage).
class CountingDraftStore extends InMemoryComposerDraftStore {
  var saves = 0;
  var bytes = 0;

  @override
  Future<void> save(String userId, Map<String, ComposerDraft> drafts) {
    saves += 1;
    bytes += encodeComposerDrafts(drafts).length;
    return super.save(userId, drafts);
  }
}

/// A small JPEG-looking PNG served for every picture request, so pictures
/// load and decode for real.
Uint8List samplePng({int width = 96, int height = 128}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 160, 200));
  return Uint8List.fromList(img.encodePng(image));
}

class _FakeHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._bytes);

  final Uint8List _bytes;

  @override
  HttpHeaders get headers => _FakeHeaders() as dynamic;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._bytes);

  final Uint8List _bytes;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeImageClient implements HttpClient {
  FakeImageClient(this.bytes);

  final Uint8List bytes;
  final requested = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return _FakeRequest(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Everything a mixed conversation needs around the chat screen.
class MixedThreadWorld {
  MixedThreadWorld({
    int count = mixedMessageCount,
    bool wallpaper = true,
    List<int>? slots,
    this.imageSize = (96, 128),
  }) : repository = PagedChatsRepository()
         ..rows = mixedRows(count: count, slots: slots, imageSize: imageSize),
       stores = WallpaperTestStores() {
    repository.conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.group,
        unreadCount: 0,
        title: 'Hike club',
      ),
    ];
    if (wallpaper) {
      const path = 'user-1/00000000-0000-4000-8000-000000000001.jpg';
      stores.repository.bucket[path] = samplePhotoBytes(
        width: 320,
        height: 480,
      );
      stores.repository.settings = const WallpaperSettings(
        defaultWallpaper: ChatWallpaper.photo(path, dim: 0.4, blur: true),
      );
    }
  }

  final PagedChatsRepository repository;
  final (int, int) imageSize;
  final WallpaperTestStores stores;
  final chain = FakeChainRepository();
  final online = StreamController<Set<String>>.broadcast();
  final locationWorld = LocationWorld();
  final providers = ProviderCounter();
  final drafts = CountingDraftStore();

  Widget app() {
    return ProviderScope(
      observers: [providers],
      overrides: [
        chatsRepositoryProvider.overrideWithValue(repository),
        chainRepositoryProvider.overrideWithValue(chain),
        onlineUserIdsProvider.overrideWith((ref) => online.stream),
        composerDraftStoreProvider.overrideWithValue(drafts),
        voiceMessageRecorderProvider.overrideWithValue(
          thread_test.FakeVoiceMessageRecorder(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          thread_test.FakeSettingsRepository(),
        ),
        ...filePreviewOverrides(),
        ...locationWorld.overrides,
        ...stores.overrides,
        authRepositoryProvider.overrideWithValue(
          thread_test.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const ChatThreadScreen(
          conversationId: 'conversation-1',
          title: 'Hike club',
        ),
      ),
    );
  }

  /// Phone-sized view, pictures served from memory.
  void prepare(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = FakeImageClient(
      samplePng(width: imageSize.$1, height: imageSize.$2),
    );
    debugNetworkImageHttpClientProvider = () => client;
  }

  /// Opens the chat and lets the first page, pictures and maps arrive.
  Future<void> open(WidgetTester tester) async {
    prepare(tester);
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ScrollPosition position(WidgetTester tester) {
    final list = find.byKey(const ValueKey('chat-message-list'));
    return tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
  }

  Future<void> close(WidgetTester tester) async {
    debugNetworkImageHttpClientProvider = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }
}
