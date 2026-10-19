// Favorites 2.0 (the Saved page with folders, tags and search; the sheets to
// add a note or a link and to file an entry), for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/saved_note_image.dart';

import '../features/later/later_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A one-pixel picture for the notes' thumbnails.
final favoritesPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xdd, 0x8d, 0xb0, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

SavedMessage _entry(
  String id, {
  SavedKind kind = SavedKind.message,
  String body = '',
  String? title,
  String? url,
  String? folderId,
  List<String> tags = const [],
  String? note,
  bool done = false,
  bool available = true,
  int minutesAgo = 30,
  Map<String, dynamic> extra = const {},
  List<SavedImage> images = const [],
  String senderName = 'Bart the Bold',
}) {
  return SavedMessage(
    id: id,
    kind: kind,
    messageId: kind.isOwn ? null : 'target-$id',
    conversationId: kind == SavedKind.message ? 'dm-1' : null,
    savedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
    doneAt: done ? DateTime.now() : null,
    senderId: available && !kind.isOwn ? 'user-2' : null,
    senderName: available && !kind.isOwn ? senderName : '',
    body: available ? body : '',
    available: available,
    title: title,
    url: url,
    folderId: folderId,
    tags: tags,
    note: note,
    extra: extra,
    images: images,
  );
}

/// What the person has kept: a message, a Moment, a post, a link, a note with
/// a picture, plain text, and a Moment that is gone, in two folders.
FakeSavedMessagesRepository favoritesRepository() {
  return FakeSavedMessagesRepository(
    [
      _entry(
        'm1',
        body: 'Bring the tripod and the long lens on Saturday',
        folderId: 'f-trips',
        tags: const ['gear'],
        minutesAgo: 25,
      ),
      _entry(
        'mo1',
        kind: SavedKind.moment,
        body: 'Sunrise at the lake, worth the early start',
        folderId: 'f-trips',
        tags: const ['photos', 'gear'],
        note: 'Look at the colors before we go back',
        extra: const {'photo_count': 3, 'moment_kind': 'photos'},
        senderName: 'Grace Hopper',
        minutesAgo: 90,
      ),
      _entry(
        'cp1',
        kind: SavedKind.circlePost,
        body: 'Club trip plan: leave at 7, back before dark',
        extra: const {'circle_name': 'Hiking club'},
        senderName: 'Linus',
        minutesAgo: 200,
      ),
      _entry(
        'l1',
        kind: SavedKind.link,
        url: 'https://example.com/trails/north-lot',
        title: 'North lot trail map',
        folderId: 'f-work',
        tags: const ['maps'],
        minutesAgo: 400,
      ),
      _entry(
        'n1',
        kind: SavedKind.note,
        title: 'Packing list',
        body: 'Tent, stove, long lens, two sets of layers, water for the day',
        tags: const ['gear'],
        images: const [
          SavedImage(path: 'user-1/n1-0.jpg'),
          SavedImage(path: 'user-1/n1-1.jpg'),
        ],
        minutesAgo: 600,
      ),
      _entry(
        't1',
        kind: SavedKind.text,
        body: 'Call the cabin about parking',
        minutesAgo: 900,
      ),
      _entry(
        'gone',
        kind: SavedKind.moment,
        available: false,
        minutesAgo: 3000,
      ),
      _entry(
        'd1',
        body: 'Book the cabin before Friday',
        done: true,
        minutesAgo: 5000,
      ),
    ],
    const [
      SavedFolder(id: 'f-trips', name: 'Trips'),
      SavedFolder(id: 'f-work', name: 'Work'),
    ],
  );
}

/// Opens the Saved page with [repository].
Future<void> openFavorites(
  WidgetTester tester,
  PhoneWorld world, [
  FakeSavedMessagesRepository? repository,
]) async {
  world.extraOverrides = [
    savedMessagesRepositoryProvider.overrideWithValue(
      repository ?? favoritesRepository(),
    ),
    savedImageProviderFactory.overrideWithValue(
      (url) => MemoryImage(favoritesPixel),
    ),
  ];
  world.imagePicker.nextImage = ChatImageUpload(
    bytes: favoritesPixel,
    fileName: 'photo.png',
    mimeType: 'image/png',
  );
  await world.open(tester, '/saved');
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    // A card far down the lazy list: scroll the list to it.
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

final favoritesA11yScreens = <A11yScreen>[
  A11yScreen('favorites-list', (tester, world) async {
    await openFavorites(tester, world);
  }),
  A11yScreen('favorites-folder', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-folder-f-trips');
  }),
  A11yScreen('favorites-search', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-search-toggle');
    await tester.enterText(
      find.byKey(const ValueKey('saved-search-field')),
      'gear',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }),
  A11yScreen('favorites-empty', (tester, world) async {
    await openFavorites(
      tester,
      world,
      FakeSavedMessagesRepository(const [], const [
        SavedFolder(id: 'f-trips', name: 'Trips'),
      ]),
    );
  }),
  A11yScreen('favorites-add-menu', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-add');
  }),
  A11yScreen('favorites-new-note', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-add');
    await _tap(tester, 'saved-add-note');
    await tester.enterText(
      find.byKey(const ValueKey('saved-note-title')),
      'Ideas for June',
    );
    await tester.enterText(
      find.byKey(const ValueKey('saved-note-body')),
      'A cabin by the lake, with a long table.',
    );
    await _tap(tester, 'saved-note-add-picture');
  }),
  A11yScreen('favorites-new-link', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-add');
    await _tap(tester, 'saved-add-link');
  }),
  A11yScreen('favorites-edit', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-edit-mo1');
  }),
  A11yScreen('favorites-edit-note', (tester, world) async {
    await openFavorites(tester, world);
    await _tap(tester, 'saved-edit-n1');
  }),
  A11yScreen('favorites-folder-menu', (tester, world) async {
    await openFavorites(tester, world);
    final folder = find.byKey(const ValueKey('saved-folder-f-trips'));
    await tester.ensureVisible(folder);
    await tester.pump();
    await tester.longPress(folder);
    await settle(tester);
  }),
  A11yScreen(
    'favorites-list-desktop',
    (tester, world) async {
      await openFavorites(tester, world);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
