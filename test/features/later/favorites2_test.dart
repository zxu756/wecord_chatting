import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/later/saved_actions.dart';
import 'package:wecord/features/later/saved_filters.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/saved_note_image.dart';
import 'package:wecord/features/later/saved_sheets.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'later_fakes.dart';

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

/// A phone as wide as a phone and tall enough to lay the whole list out.
const _tall = PhoneViewport(
  name: '390x2600',
  size: Size(390, 2600),
  devicePixelRatio: 1,
  topInset: 47,
  bottomInset: 34,
);

const _trips = SavedFolder(id: 'f-trips', name: 'Trips');
const _work = SavedFolder(id: 'f-work', name: 'Work');

FakeSavedMessagesRepository _repository() {
  return FakeSavedMessagesRepository(
    [
      _entry(
        'm1',
        body: 'Bring the tripod',
        folderId: 'f-trips',
        tags: const ['gear'],
      ),
      _entry(
        'mo1',
        kind: SavedKind.moment,
        body: 'Sunrise at the lake',
        folderId: 'f-trips',
        tags: const ['photos', 'gear'],
        note: 'Look at the colors',
        extra: const {'photo_count': 3, 'moment_kind': 'photos'},
        senderName: 'Grace',
      ),
      _entry(
        'cp1',
        kind: SavedKind.circlePost,
        body: 'Club trip plan',
        extra: const {'circle_name': 'Hiking club'},
        senderName: 'Linus',
      ),
      _entry(
        'l1',
        kind: SavedKind.link,
        url: 'https://example.com/trails/north-lot',
        title: 'Trail map',
        folderId: 'f-work',
      ),
      _entry(
        'n1',
        kind: SavedKind.note,
        title: 'Packing list',
        body: 'tent, stove, lens',
        tags: const ['gear'],
        images: const [SavedImage(path: 'user-1/n1-0.jpg')],
      ),
      _entry('t1', kind: SavedKind.text, body: 'Call the cabin'),
      _entry('gone', kind: SavedKind.moment, available: false, minutesAgo: 400),
      _entry('d1', body: 'Book the cabin', done: true, folderId: 'f-trips'),
    ],
    const [_trips, _work],
  );
}

/// Scrolls [target] into view (the chip rows scroll sideways), then taps.
Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

Future<void> longPressVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.longPress(target);
}

void main() {
  group('model', () {
    test('parses every kind from the server', () {
      final moment = SavedMessage.fromJson({
        'saved_id': 's1',
        'kind': 'moment',
        'target_id': 'mo-1',
        'saved_at': '2026-10-25T10:00:00+00:00',
        'available': true,
        'folder_id': 'f1',
        'tags': ['photos', 'Gear'],
        'note': 'nice',
        'sender_id': 'u2',
        'sender_display_name': 'Grace',
        'content_body': 'Sunrise',
        'extra': {'photo_count': 2, 'thumb': 'u2/p-0-t.jpg'},
      });
      expect(moment.kind, SavedKind.moment);
      expect(moment.messageId, 'mo-1');
      expect(moment.body, 'Sunrise');
      expect(moment.senderName, 'Grace');
      expect(moment.tags, ['photos', 'Gear']);
      expect(moment.note, 'nice');
      expect(moment.folderId, 'f1');
      expect(moment.extra['thumb'], 'u2/p-0-t.jpg');
      expect(moment.targetKey, 'moment:mo-1');

      final post = SavedMessage.fromJson({
        'saved_id': 's2',
        'kind': 'circle_post',
        'target_id': 'p-1',
        'circle_id': 'c-1',
        'saved_at': '2026-10-25T10:00:00+00:00',
        'available': true,
        'content_body': 'Plan',
      });
      expect(post.kind, SavedKind.circlePost);
      expect(post.circleId, 'c-1');
      expect(post.targetKey, 'circle_post:p-1');

      final note = SavedMessage.fromJson({
        'saved_id': 's3',
        'kind': 'note',
        'saved_at': '2026-10-25T10:00:00+00:00',
        'available': true,
        'title': 'Packing',
        'body': 'tent',
        'content_body': 'ignored',
        'images': [
          {'path': 'u1/s3-0.jpg', 'w': 800, 'h': 600},
        ],
      });
      expect(note.kind.isOwn, isTrue);
      expect(note.body, 'tent');
      expect(note.title, 'Packing');
      expect(note.images.single.path, 'u1/s3-0.jpg');
      expect(note.images.single.width, 800);
    });

    test('a row from an older server is a message', () {
      final saved = SavedMessage.fromJson({
        'saved_id': 's1',
        'message_id': 'm1',
        'conversation_id': 'c1',
        'saved_at': '2026-10-17T10:00:00+00:00',
        'body': 'Bring the tripod',
        'type': 'text',
        'available': true,
      });
      expect(saved.kind, SavedKind.message);
      expect(saved.messageId, 'm1');
      expect(saved.body, 'Bring the tripod');
      expect(saved.type, MessageType.text);
      expect(saved.tags, isEmpty);
    });

    test('an entry that is no longer visible shows no text', () {
      final saved = SavedMessage.fromJson({
        'saved_id': 's1',
        'kind': 'moment',
        'target_id': 'mo-1',
        'saved_at': '2026-10-25T10:00:00+00:00',
        'available': false,
        'content_body': 'Sunrise',
        'tags': ['kept'],
      });
      expect(saved.available, isFalse);
      expect(saved.body, isEmpty);
      expect(saved.tags, ['kept']);
    });

    test('the kinds round-trip through their wire names', () {
      for (final kind in SavedKind.values) {
        expect(SavedKind.fromJson(kind.wire), kind);
      }
      expect(SavedKind.circlePost.wire, 'circle_post');
      expect(SavedKind.fromJson('something else'), SavedKind.message);
      expect(SavedKind.link.isOwn && SavedKind.note.isOwn, isTrue);
      expect(SavedKind.moment.isOwn || SavedKind.message.isOwn, isFalse);
    });

    test('saved target keys come from the list', () async {
      final container = ProviderContainer(
        overrides: [
          savedMessagesRepositoryProvider.overrideWithValue(_repository()),
        ],
      );
      addTearDown(container.dispose);
      container
        ..listen(savedTargetKeysProvider, (_, _) {})
        ..listen(savedMessageIdsProvider, (_, _) {});
      await container.read(savedMessagesProvider.future);
      final keys = container.read(savedTargetKeysProvider);
      expect(keys, contains('moment:target-mo1'));
      expect(keys, contains('circle_post:target-cp1'));
      expect(keys.any((key) => key.startsWith('link')), isFalse);
      // Only messages are in the message menu's set.
      expect(container.read(savedMessageIdsProvider), {
        'target-m1',
        'target-d1',
      });
    });
  });

  group('filters', () {
    final all = _repository().entries;

    List<String> ids(SavedView view) => [
      for (final item in filterSaved(all, view)) item.id,
    ];

    test('active and done are apart', () {
      expect(ids(const SavedView()), isNot(contains('d1')));
      expect(ids(const SavedView(status: SavedFilter.done)), ['d1']);
    });

    test('a folder narrows, and so does a tag (any case)', () {
      expect(ids(const SavedView(folderId: 'f-trips')), ['m1', 'mo1']);
      expect(
        ids(const SavedView(folderId: 'f-trips', status: SavedFilter.done)),
        ['d1'],
      );
      expect(ids(const SavedView(tag: 'GEAR')), ['m1', 'mo1', 'n1']);
      expect(ids(const SavedView(folderId: 'f-trips', tag: 'photos')), ['mo1']);
    });

    test('a search looks through done ones too', () {
      expect(ids(SavedView(matchIds: {'d1', 'l1'})), ['l1', 'd1']);
      expect(ids(SavedView(matchIds: {})), isEmpty);
    });

    test('folders and tags are counted', () {
      expect(folderCounts(all), {'f-trips': 3, 'f-work': 1});
      final tags = tagCounts(all);
      expect(tags.first, (tag: 'gear', count: 3));
      expect(tags.map((t) => t.tag), ['gear', 'photos']);
    });

    test('copyWith keeps and clears', () {
      const view = SavedView(folderId: 'f', tag: 't');
      expect(view.copyWith(status: SavedFilter.done).folderId, 'f');
      expect(view.copyWith(folderId: null).folderId, isNull);
      expect(view.copyWith(folderId: null).tag, 't');
      expect(view.copyWith(matchIds: {'a'}).matchIds, {'a'});
    });

    test('tags are tidied like the server does', () {
      expect(tidySavedTag('  #Gear  '), 'Gear');
      expect(tidySavedTag('##big   idea'), 'big idea');
      expect(tidySavedTag('#'), isEmpty);
      expect(tidySavedTag('a' * 40), 'a' * 24);
    });

    test('a typed address is made whole, or refused', () {
      expect(normalizeSavedLink('example.com/a'), 'https://example.com/a');
      expect(normalizeSavedLink(' http://example.com '), 'http://example.com');
      expect(normalizeSavedLink('javascript:alert(1)'), isNull);
      expect(normalizeSavedLink('not a link'), isNull);
      expect(normalizeSavedLink('localhost'), isNull);
      expect(normalizeSavedLink('ftp://example.com'), isNull);
      expect(normalizeSavedLink(''), isNull);
    });
  });

  group('the Saved page', () {
    Future<PhoneWorld> open(
      WidgetTester tester,
      FakeSavedMessagesRepository repository, {
      List<Override> overrides = const [],
    }) async {
      usePhoneViewport(tester, _tall);
      final world = PhoneWorld()
        ..imagePicker.nextImage = ChatImageUpload(
          bytes: _pixel,
          fileName: 'photo.png',
          mimeType: 'image/png',
        )
        ..extraOverrides = [
          savedMessagesRepositoryProvider.overrideWithValue(repository),
          savedImageProviderFactory.overrideWithValue(
            (url) => MemoryImage(_pixel),
          ),
          ...overrides,
        ];
      await world.open(tester, '/saved');
      await settle(tester);
      return world;
    }

    testWidgets('shows every kind with its folder, tags and remark', (
      tester,
    ) async {
      await open(tester, _repository());

      expect(find.text('Bring the tripod'), findsOneWidget);
      expect(find.text('Sunrise at the lake'), findsOneWidget);
      expect(find.text('Moment · 3 photos'), findsOneWidget);
      expect(find.text('Club trip plan'), findsOneWidget);
      expect(find.text('Circle post · Hiking club'), findsOneWidget);
      expect(find.text('Trail map'), findsWidgets);
      expect(find.text('example.com/trails/north-lot'), findsOneWidget);
      expect(find.text('Packing list'), findsOneWidget);
      expect(find.text('tent, stove, lens'), findsOneWidget);
      expect(find.text('Call the cabin'), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-remark-mo1')), findsOneWidget);
      expect(find.text('Look at the colors'), findsOneWidget);
      // Not the done one.
      expect(find.text('Book the cabin'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an entry that is no longer visible says so', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      expect(find.text('No longer visible'), findsOneWidget);
      // It can be filed and removed, not opened.
      expect(find.byKey(const ValueKey('saved-jump-gone')), findsNothing);
      expect(find.byKey(const ValueKey('saved-edit-gone')), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('saved-remove-gone')));
      await settle(tester);
      expect(repository.removed, ['gone']);
      expect(find.text('No longer visible'), findsNothing);
    });

    testWidgets('folders narrow the list, with their counts', (tester) async {
      await open(tester, _repository());

      expect(find.text('Trips 3'), findsOneWidget);
      expect(find.text('Work 1'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-folder-f-trips')),
      );
      await settle(tester);
      expect(find.text('Bring the tripod'), findsOneWidget);
      expect(find.text('Sunrise at the lake'), findsOneWidget);
      expect(find.text('Club trip plan'), findsNothing);
      expect(find.text('Packing list'), findsNothing);

      // The done one of the same folder is under Done.
      await tapVisible(tester, find.byKey(const ValueKey('saved-filter-done')));
      await settle(tester);
      expect(find.text('Book the cabin'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey('saved-folder-all')));
      await settle(tester);
      expect(find.text('Book the cabin'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-filter-active')),
      );
      await settle(tester);
      expect(find.text('Club trip plan'), findsOneWidget);
    });

    testWidgets('tags narrow the list, on the chip or on a card', (
      tester,
    ) async {
      await open(tester, _repository());

      await tapVisible(tester, find.byKey(const ValueKey('saved-tag-gear')));
      await settle(tester);
      expect(find.text('Bring the tripod'), findsOneWidget);
      expect(find.text('Packing list'), findsOneWidget);
      expect(find.text('Club trip plan'), findsNothing);

      // Tapping the same chip again lets go.
      await tapVisible(tester, find.byKey(const ValueKey('saved-tag-gear')));
      await settle(tester);
      expect(find.text('Club trip plan'), findsOneWidget);

      // A tag on a card does the same.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-tag-of-mo1-photos')),
      );
      await settle(tester);
      expect(find.text('Sunrise at the lake'), findsOneWidget);
      expect(find.text('Bring the tripod'), findsNothing);
    });

    testWidgets('nothing in a folder says so', (tester) async {
      final repository = FakeSavedMessagesRepository(
        [_entry('m1', body: 'Hello')],
        const [_trips],
      );
      await open(tester, repository);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-folder-f-trips')),
      );
      await settle(tester);
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('search finds entries, done ones too', (tester) async {
      final repository = _repository();
      await open(tester, repository);

      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-search-toggle')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-field')),
        'cabin',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      expect(repository.searches, ['cabin']);
      // "Call the cabin" (active) and "Book the cabin" (done).
      expect(find.text('Call the cabin'), findsOneWidget);
      expect(find.text('Book the cabin'), findsOneWidget);
      expect(find.text('Bring the tripod'), findsNothing);
      // The Active / Done chips step aside.
      expect(find.byKey(const ValueKey('saved-filter-done')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('saved-search-field')),
        'zebra',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.text('Nothing found'), findsOneWidget);

      // Clearing the field, or closing the search, brings the list back.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-search-toggle')),
      );
      await settle(tester);
      expect(find.text('Bring the tripod'), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-filter-done')), findsOneWidget);
    });

    testWidgets('a failed search says so', (tester) async {
      final repository = _repository()..failSearch = true;
      await open(tester, repository);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-search-toggle')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-search-field')),
        'cabin',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.text('Could not search. Try again.'), findsOneWidget);
    });

    testWidgets('a link opens through the link launcher', (tester) async {
      final world = await open(tester, _repository());
      expect(find.text('Open link'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('saved-jump-l1')));
      await settle(tester);
      expect(
        world.openedLinks.single.toString(),
        'https://example.com/trails/north-lot',
      );
    });

    testWidgets('done and undo work for any kind', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-done-l1')));
      await settle(tester);
      expect(repository.doneCalls, [(id: 'l1', done: true)]);
      expect(find.byKey(const ValueKey('saved-done-l1')), findsNothing);
    });

    testWidgets('removing a note takes its pictures with it', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-remove-n1')));
      await settle(tester);
      expect(repository.removed, ['n1']);
      expect(repository.removedImages, ['user-1/n1-0.jpg']);
      expect(find.text('Packing list'), findsNothing);
    });

    testWidgets('a failing server shows an error and keeps the entry', (
      tester,
    ) async {
      final repository = _repository();
      await open(tester, repository);
      repository.failWrites = true;
      await tapVisible(tester, find.byKey(const ValueKey('saved-remove-m1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('saved-error')), findsOneWidget);
      expect(find.text('Bring the tripod'), findsOneWidget);
    });

    testWidgets('a folder is made from the page and selected', (tester) async {
      final repository = _repository();
      await open(tester, repository);

      await tapVisible(tester, find.byKey(const ValueKey('saved-new-folder')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-name-field')),
        'Recipes',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-name-save')));
      await settle(tester);

      expect(repository.folderList.map((f) => f.name), contains('Recipes'));
      expect(find.text('Recipes'), findsOneWidget);
      // The new folder is empty.
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('holding a folder renames or deletes it', (tester) async {
      final repository = _repository();
      await open(tester, repository);

      await longPressVisible(
        tester,
        find.byKey(const ValueKey('saved-folder-f-work')),
      );
      await settle(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-folder-rename')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-name-field')),
        'Office',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-name-save')));
      await settle(tester);
      expect(repository.folderList.map((f) => f.name), contains('Office'));

      await longPressVisible(
        tester,
        find.byKey(const ValueKey('saved-folder-f-work')),
      );
      await settle(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-folder-delete')),
      );
      await settle(tester);
      expect(repository.folderList.map((f) => f.id), ['f-trips']);
      // Its link stays, without a folder.
      expect(
        repository.entries.firstWhere((e) => e.id == 'l1').folderId,
        isNull,
      );
    });

    testWidgets('holding a tag renames it everywhere', (tester) async {
      final repository = _repository();
      await open(tester, repository);

      await longPressVisible(
        tester,
        find.byKey(const ValueKey('saved-tag-gear')),
      );
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-tag-rename')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-name-field')),
        '#equipment',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-name-save')));
      await settle(tester);
      expect(repository.renamedTags, [(from: 'gear', to: 'equipment')]);
      expect(find.byKey(const ValueKey('saved-tag-equipment')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-tag-gear')), findsNothing);
    });

    testWidgets('holding a tag can delete it', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      await longPressVisible(
        tester,
        find.byKey(const ValueKey('saved-tag-photos')),
      );
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-tag-delete')));
      await settle(tester);
      expect(repository.renamedTags, [(from: 'photos', to: '')]);
      expect(find.byKey(const ValueKey('saved-tag-photos')), findsNothing);
    });
  });

  group('editing and adding', () {
    Future<void> open(
      WidgetTester tester,
      FakeSavedMessagesRepository repository, {
      List<Override> overrides = const [],
    }) async {
      usePhoneViewport(tester, _tall);
      final world = PhoneWorld()
        ..imagePicker.nextImage = ChatImageUpload(
          bytes: _pixel,
          fileName: 'photo.png',
          mimeType: 'image/png',
        )
        ..extraOverrides = [
          savedMessagesRepositoryProvider.overrideWithValue(repository),
          savedImageProviderFactory.overrideWithValue(
            (url) => MemoryImage(_pixel),
          ),
          ...overrides,
        ];
      await world.open(tester, '/saved');
      await settle(tester);
    }

    testWidgets('filing a message: folder, tags and a remark', (tester) async {
      final repository = _repository();
      await open(tester, repository);

      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-m1')));
      await settle(tester);
      expect(find.text('Edit'), findsWidgets);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-pick-folder-f-work')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-tag-field')),
        '#camera, lens',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-tag-add')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('saved-tag-chip-camera')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('saved-tag-chip-lens')), findsOneWidget);
      // Tapping a tag on the entry takes it off.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-tag-chip-gear')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-edit-remark')),
        'for the June trip',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-save')));
      await settle(tester);

      expect(repository.updates, hasLength(1));
      final patch = repository.updates.single.patch;
      expect(repository.updates.single.id, 'm1');
      expect(patch['folder_id'], 'f-work');
      expect(patch['tags'], ['camera', 'lens']);
      expect(patch['note'], 'for the June trip');
      expect(patch.containsKey('title'), isFalse);
      final saved = repository.entries.firstWhere((e) => e.id == 'm1');
      expect(saved.folderId, 'f-work');
      expect(find.byKey(const ValueKey('saved-remark-m1')), findsOneWidget);
    });

    testWidgets('saving without a change closes without calling', (
      tester,
    ) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-m1')));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-save')));
      await settle(tester);
      expect(repository.updates, isEmpty);
      expect(find.byKey(const ValueKey('saved-edit-save')), findsNothing);
    });

    testWidgets('a note is edited whole, and a picture can be dropped', (
      tester,
    ) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-n1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('saved-edit-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-edit-remark')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('saved-edit-title')),
        'Packing',
      );
      await tester.enterText(
        find.byKey(const ValueKey('saved-edit-body')),
        'tent only',
      );
      await tapVisible(tester, find.byTooltip('Remove picture'));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-save')));
      await settle(tester);

      final patch = repository.updates.single.patch;
      expect(patch['title'], 'Packing');
      expect(patch['body'], 'tent only');
      expect(patch['images'], isEmpty);
      expect(repository.removedImages, ['user-1/n1-0.jpg']);
    });

    testWidgets('plain text cannot be emptied', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-t1')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-edit-body')),
        '   ',
      );
      await settle(tester);
      final save = tester.widget<WeCordButton>(
        find.byKey(const ValueKey('saved-edit-save')),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('a failed save keeps the sheet and says why', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-m1')));
      await settle(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-pick-folder-f-work')),
      );
      await settle(tester);
      repository.failWrites = true;
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-save')));
      await settle(tester);
      expect(find.byKey(const ValueKey('saved-sheet-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-edit-save')), findsOneWidget);
    });

    testWidgets('a new note with a picture, a folder and tags', (tester) async {
      final repository = FakeSavedMessagesRepository(const [], const [_trips]);
      await open(
        tester,
        repository,
        overrides: [
          savedPicturePreparerProvider.overrideWithValue(
            (bytes, fileName) async =>
                SavedNotePicture(bytes: bytes, width: 1, height: 1),
          ),
        ],
      );

      await tapVisible(tester, find.byKey(const ValueKey('saved-add')));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-add-note')));
      await settle(tester);

      // Nothing to save yet.
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('saved-note-save')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('saved-note-title')),
        'Ideas',
      );
      await tester.enterText(
        find.byKey(const ValueKey('saved-note-body')),
        'A cabin by the lake',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-note-add-picture')),
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey('saved-note-picture-0')),
        findsOneWidget,
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-pick-folder-f-trips')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-tag-field')),
        'dream',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-tag-add')));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-note-save')));
      await settle(tester);

      expect(repository.notes, hasLength(1));
      final note = repository.notes.single;
      expect(note.title, 'Ideas');
      expect(note.body, 'A cabin by the lake');
      expect(note.pictures, 1);
      expect(note.folderId, 'f-trips');
      expect(note.tags, ['dream']);
      expect(find.byKey(const ValueKey('saved-note-save')), findsNothing);
      expect(find.text('Ideas'), findsOneWidget);
    });

    testWidgets('a note takes at most four pictures', (tester) async {
      final repository = FakeSavedMessagesRepository();
      await open(
        tester,
        repository,
        overrides: [
          savedPicturePreparerProvider.overrideWithValue(
            (bytes, fileName) async => SavedNotePicture(bytes: bytes),
          ),
        ],
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-add')));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-add-note')));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tapVisible(
          tester,
          find.byKey(const ValueKey('saved-note-add-picture')),
        );
        await settle(tester);
      }
      expect(
        find.byKey(const ValueKey('saved-note-picture-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved-note-add-picture')),
        findsNothing,
      );
    });

    testWidgets('a picture that cannot be read says so', (tester) async {
      final repository = FakeSavedMessagesRepository();
      await open(
        tester,
        repository,
        overrides: [
          savedPicturePreparerProvider.overrideWithValue(
            (bytes, fileName) async => null,
          ),
        ],
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-add')));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-add-note')));
      await settle(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-note-add-picture')),
      );
      await settle(tester);
      expect(
        find.text('That picture could not be read. Try another.'),
        findsOneWidget,
      );
    });

    testWidgets('a link: the address is checked, then kept', (tester) async {
      final repository = FakeSavedMessagesRepository(const [], const [_work]);
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-add')));
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-add-link')));
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('saved-link-url')),
        'not a link',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-link-save')));
      await settle(tester);
      expect(find.text('Enter a web link'), findsOneWidget);
      expect(repository.links, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('saved-link-url')),
        'example.com/trails',
      );
      await tester.enterText(
        find.byKey(const ValueKey('saved-link-title')),
        'Trails',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-pick-folder-f-work')),
      );
      await settle(tester);
      await tapVisible(tester, find.byKey(const ValueKey('saved-link-save')));
      await settle(tester);

      expect(repository.links, [
        (
          url: 'https://example.com/trails',
          title: 'Trails',
          folderId: 'f-work',
        ),
      ]);
      expect(find.text('Trails'), findsWidgets);
    });

    testWidgets('a folder can be made while filing', (tester) async {
      final repository = _repository();
      await open(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-m1')));
      await settle(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('saved-pick-folder-new')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-name-field')),
        'Gear',
      );
      await tapVisible(tester, find.byKey(const ValueKey('saved-name-save')));
      await settle(tester);
      expect(repository.folderList.map((f) => f.name), contains('Gear'));
      await tapVisible(tester, find.byKey(const ValueKey('saved-edit-save')));
      await settle(tester);
      expect(
        repository.updates.single.patch['folder_id'],
        startsWith('folder-'),
      );
    });
  });

  group('keeping a Moment or a post', () {
    Future<(FakeSavedMessagesRepository, BuildContext, WidgetRef)> pump(
      WidgetTester tester,
      FakeSavedMessagesRepository repository,
    ) async {
      late BuildContext savedContext;
      late WidgetRef savedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedMessagesRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  final saved = isSavedTarget(ref, SavedKind.moment, 'mo-9');
                  return Text(saved ? 'kept' : 'not kept');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (repository, savedContext, savedRef);
    }

    testWidgets('saves once, then takes it out again', (tester) async {
      final repository = FakeSavedMessagesRepository();
      final (_, context, ref) = await pump(tester, repository);
      expect(find.text('not kept'), findsOneWidget);

      await toggleSavedTarget(
        context,
        ref,
        kind: SavedKind.moment,
        targetId: 'mo-9',
      );
      await tester.pumpAndSettle();
      expect(repository.savedItems, [
        (kind: SavedKind.moment, targetId: 'mo-9'),
      ]);
      expect(find.text('Saved for later'), findsOneWidget);
      expect(find.text('kept'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await toggleSavedTarget(
        context,
        ref,
        kind: SavedKind.moment,
        targetId: 'mo-9',
      );
      await tester.pumpAndSettle();
      expect(repository.removed, hasLength(1));
      expect(find.text('Removed from Saved'), findsOneWidget);
      expect(find.text('not kept'), findsOneWidget);
    });

    testWidgets('a post and a Moment with the same id are different', (
      tester,
    ) async {
      final repository = FakeSavedMessagesRepository([
        _entry('x', kind: SavedKind.circlePost).copyWithTarget('mo-9'),
      ]);
      final (_, context, ref) = await pump(tester, repository);
      expect(find.text('not kept'), findsOneWidget);
      await toggleSavedTarget(
        context,
        ref,
        kind: SavedKind.moment,
        targetId: 'mo-9',
      );
      await tester.pumpAndSettle();
      expect(repository.savedItems, hasLength(1));
      expect(repository.removed, isEmpty);
    });

    testWidgets('a failure says so', (tester) async {
      final repository = FakeSavedMessagesRepository()..failWrites = true;
      final (_, context, ref) = await pump(tester, repository);
      await toggleSavedTarget(
        context,
        ref,
        kind: SavedKind.circlePost,
        targetId: 'p-1',
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not update Saved. Try again.'), findsOneWidget);
    });
  });
}

final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xdd, 0x8d, 0xb0, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// The saved entry with a different target, for the test that a Moment and
/// a post never share a key.
extension on SavedMessage {
  SavedMessage copyWithTarget(String target) {
    return SavedMessage(
      id: id,
      kind: kind,
      messageId: target,
      savedAt: savedAt,
    );
  }
}
