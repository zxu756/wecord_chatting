import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/shared/models/conversation.dart';

ConversationSummary chat(
  String id, {
  ConversationType type = ConversationType.direct,
  int unread = 0,
  bool markedUnread = false,
  bool muted = false,
  bool pinned = false,
  bool noteToSelf = false,
  Set<String> mentions = const {},
}) {
  return ConversationSummary(
    id: id,
    type: type,
    unreadCount: unread,
    title: id,
    isMarkedUnread: markedUnread,
    isMuted: muted,
    pinnedAt: pinned ? DateTime(2026, 10, 1) : null,
    isNoteToSelf: noteToSelf,
    mentionedUserIds: mentions,
  );
}

List<String> ids(Iterable<ConversationSummary> chats) => [
  for (final c in chats) c.id,
];

void main() {
  const groups = ChatFolder(
    id: 'f-groups',
    name: 'Groups',
    includeTypes: {ConversationType.group},
  );

  group('folderTakes', () {
    test('takes chats by kind', () {
      expect(
        folderTakes(groups, chat('g', type: ConversationType.group)),
        true,
      );
      expect(folderTakes(groups, chat('d')), false);
    });

    test('an empty folder takes nothing by itself', () {
      const empty = ChatFolder(id: 'f', name: 'Empty');
      expect(folderTakes(empty, chat('d')), false);
      expect(
        folderTakes(empty, chat('g', type: ConversationType.group)),
        false,
      );
    });

    test('filters apply to chats taken by kind', () {
      const unread = ChatFolder(
        id: 'f',
        name: 'Unread',
        includeTypes: {ConversationType.direct, ConversationType.group},
        onlyUnread: true,
        excludeMuted: true,
      );
      expect(folderTakes(unread, chat('a', unread: 2)), true);
      expect(folderTakes(unread, chat('b', markedUnread: true)), true);
      expect(folderTakes(unread, chat('c')), false);
      expect(folderTakes(unread, chat('d', unread: 2, muted: true)), false);
    });

    test('only muted takes the muted ones', () {
      const muted = ChatFolder(
        id: 'f',
        name: 'Muted',
        includeTypes: {ConversationType.direct},
        onlyMuted: true,
      );
      expect(folderTakes(muted, chat('a', muted: true)), true);
      expect(folderTakes(muted, chat('b')), false);
    });

    test('a chat listed by id is in whatever the filters say', () {
      const folder = ChatFolder(
        id: 'f',
        name: 'Picked',
        includeIds: {'read-muted'},
        onlyUnread: true,
        excludeMuted: true,
      );
      expect(folderTakes(folder, chat('read-muted', muted: true)), true);
      expect(folderTakes(folder, chat('other', unread: 3)), false);
    });

    test('exclusion beats everything', () {
      const folder = ChatFolder(
        id: 'f',
        name: 'Not this one',
        includeTypes: {ConversationType.group},
        includeIds: {'g'},
        excludeIds: {'g'},
      );
      expect(
        folderTakes(folder, chat('g', type: ConversationType.group)),
        false,
      );
    });

    test('the note to self is never in a folder', () {
      const everything = ChatFolder(
        id: 'f',
        name: 'All',
        includeTypes: {ConversationType.direct},
        includeIds: {'note'},
      );
      expect(folderTakes(everything, chat('note', noteToSelf: true)), false);
    });
  });

  group('lists', () {
    final all = [
      chat('a'),
      chat('p1', type: ConversationType.group, pinned: true),
      chat('g1', type: ConversationType.group),
      chat('p2', type: ConversationType.group, pinned: true),
      chat('g2', type: ConversationType.group),
    ];

    test('pinned chats come first in a folder, in their own order', () {
      expect(ids(chatsInFolder(groups, all)), ['p1', 'p2', 'g1', 'g2']);
    });

    test(
      'the Unread view lists every unread chat, muted too, pinned first',
      () {
        final chats = [
          chat('read'),
          chat('u1', unread: 1),
          chat('quiet', unread: 5, muted: true),
          chat('manual', markedUnread: true, pinned: true),
          chat('note', noteToSelf: true, unread: 1),
        ];
        final entries = chatListEntries(
          chats: chats,
          folders: const [],
          selected: unreadFilterId,
          userId: 'me',
        );
        expect(ids(entries.map((e) => (e as ConversationEntry).conversation)), [
          'manual',
          'u1',
          'quiet',
        ]);
      },
    );

    test('an unknown folder shows everything', () {
      final entries = chatListEntries(
        chats: all,
        folders: const [],
        selected: 'gone',
        userId: 'me',
      );
      expect(entries, hasLength(all.length));
    });
  });

  group('counts', () {
    test('muted chats are quiet: they do not count', () {
      final summary = FolderSummary.of([
        chat('a', unread: 4),
        chat('b', markedUnread: true),
        chat('c', unread: 9, muted: true),
        chat('d'),
      ], 'me');
      expect(summary.unread, 2);
      expect(summary.mention, false);
    });

    test('a mention in an unread chat shows the dot, even when muted', () {
      expect(
        FolderSummary.of([
          chat('a', unread: 1, mentions: {'me'}),
        ], 'me').mention,
        true,
      );
      expect(
        FolderSummary.of([
          chat('a', unread: 1, muted: true, mentions: {'me'}),
        ], 'me').mention,
        true,
      );
    });

    test('a mention that was read, or of someone else, is no dot', () {
      expect(
        FolderSummary.of([
          chat('a', mentions: {'me'}),
        ], 'me').mention,
        false,
      );
      expect(
        FolderSummary.of([
          chat('a', unread: 1, mentions: {'you'}),
        ], 'me').mention,
        false,
      );
      expect(FolderSummary.of([chat('a', unread: 1)], null).mention, false);
    });
  });

  group('the folded folder', () {
    const folded = ChatFolder(
      id: 'fold',
      name: 'Folded group chats',
      includeIds: {'g2', 'g3', 'p'},
      folded: true,
    );
    final chats = [
      chat('note', noteToSelf: true),
      chat('d1', unread: 1),
      chat('g1', type: ConversationType.group),
      chat('g2', type: ConversationType.group, unread: 2),
      chat('p', type: ConversationType.group, pinned: true),
      chat('g3', type: ConversationType.group, unread: 1, mentions: {'me'}),
      chat('d2'),
    ];

    List<String> labels(List<ChatListEntry> entries) => [
      for (final entry in entries)
        switch (entry) {
          ConversationEntry(:final conversation) => conversation.id,
          FoldedEntry(:final folder) => '[${folder.id}]',
        },
    ];

    test('its chats give way to one row where the first one was', () {
      final entries = chatListEntries(
        chats: chats,
        folders: const [folded],
        selected: null,
        userId: 'me',
      );
      expect(labels(entries), ['note', 'd1', 'g1', '[fold]', 'p', 'd2']);
      final row = entries.whereType<FoldedEntry>().single;
      expect(ids(row.members), ['g2', 'g3']);
      expect(row.summary.unread, 2);
      expect(row.summary.mention, true);
    });

    test('a pinned chat stays out of the fold', () {
      final entries = chatListEntries(
        chats: chats,
        folders: const [folded],
        selected: null,
        userId: 'me',
      );
      expect(labels(entries), contains('p'));
    });

    test('opened, the folder lists its chats one by one', () {
      final entries = chatListEntries(
        chats: chats,
        folders: const [folded],
        selected: 'fold',
        userId: 'me',
      );
      expect(labels(entries), ['p', 'g2', 'g3']);
    });

    test('with nothing to fold there is no row', () {
      final entries = chatListEntries(
        chats: [chat('d1')],
        folders: const [folded],
        selected: null,
        userId: 'me',
      );
      expect(entries.whereType<FoldedEntry>(), isEmpty);
    });

    test('it still shows in the Unread view as ordinary chats', () {
      final entries = chatListEntries(
        chats: chats,
        folders: const [folded],
        selected: unreadFilterId,
        userId: 'me',
      );
      expect(entries.whereType<FoldedEntry>(), isEmpty);
      expect(labels(entries), ['d1', 'g2', 'g3']);
    });
  });

  group('withChatIn', () {
    test('puts a chat in by id when the rules do not take it', () {
      final next = withChatIn(groups, chat('d'), include: true);
      expect(next.includeIds, {'d'});
      expect(folderTakes(next, chat('d')), true);
    });

    test('leaves a chat the rules already take to the rules', () {
      final next = withChatIn(
        groups,
        chat('g', type: ConversationType.group),
        include: true,
      );
      expect(next.includeIds, isEmpty);
    });

    test('taking a chat out lists it by id when it was picked', () {
      final picked = groups.copyWith(includeIds: {'d'});
      final next = withChatIn(picked, chat('d'), include: false);
      expect(next.includeIds, isEmpty);
      expect(next.excludeIds, isEmpty);
    });

    test('taking out a chat the rules take excludes it', () {
      final g = chat('g', type: ConversationType.group);
      final next = withChatIn(groups, g, include: false);
      expect(next.excludeIds, {'g'});
      expect(folderTakes(next, g), false);
      // And putting it back clears the exclusion.
      final back = withChatIn(next, g, include: true);
      expect(back.excludeIds, isEmpty);
      expect(folderTakes(back, g), true);
    });
  });

  group('the folder itself', () {
    test('reads the server row', () {
      final folder = ChatFolder.fromJson({
        'id': 'f1',
        'name': 'Work',
        'icon': 'work',
        'sort_key': 3,
        'include_types': ['group', 'channel', 'bogus'],
        'include_ids': ['a', 'b'],
        'exclude_ids': <String>[],
        'only_unread': true,
        'exclude_muted': true,
        'only_muted': false,
        'folded': false,
      });
      expect(folder.includeTypes, {
        ConversationType.group,
        ConversationType.channel,
      });
      expect(folder.includeIds, {'a', 'b'});
      expect(folder.sortKey, 3);
      expect(folder.onlyUnread, true);
      expect(
        folder.toRules()['include_types'],
        containsAll(['group', 'channel']),
      );
    });

    test('an unknown icon falls back to the plain folder', () {
      expect(chatFolderIcon('nope'), chatFolderIcon('folder'));
    });

    test('templates start where they say', () {
      final unread = ChatFolderTemplate.unread.build('Unread');
      expect(unread.onlyUnread, true);
      expect(unread.excludeMuted, true);
      expect(unread.includeTypes, hasLength(3));
      final muted = ChatFolderTemplate.muted.build('Muted');
      expect(muted.onlyMuted, true);
      expect(muted.excludeMuted, false);
      expect(ChatFolderTemplate.groups.build('G').includeTypes, {
        ConversationType.group,
      });
      expect(ChatFolderTemplate.directMessages.build('D').includeTypes, {
        ConversationType.direct,
      });
      final fold = ChatFolderTemplate.foldedGroups.build('F');
      expect(fold.folded, true);
      expect(fold.includeTypes, isEmpty);
      expect(fold.isDraft, true);
    });
  });
}
