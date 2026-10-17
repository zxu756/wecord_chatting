import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

// "Note to self" (文件传输助手): a chat with nobody else in it, for sending
// text, photos, files and voice between your own phone and computer. It is a
// direct conversation with one member that the server makes the first time
// it is opened (migration 202610180033); the app lists it first, before it
// exists too, and makes it when it is tapped.

/// The id of the "Note to self" row shown before the server made the chat.
const noteToSelfPlaceholderId = 'note-to-self-placeholder';

/// The words of the row and the chat's header.
String noteToSelfTitle() => tr('Note to self');

/// What the row says while there is nothing in the chat.
String noteToSelfHint() => tr('Send text, photos and files to your devices');

/// The row for a note to self the server has not made yet.
const noteToSelfPlaceholder = ConversationSummary(
  id: noteToSelfPlaceholderId,
  type: ConversationType.direct,
  unreadCount: 0,
  title: 'Note to self',
  memberCount: 1,
  isNoteToSelf: true,
);

/// [chats] with the note to self first: the server's own, or the
/// placeholder while there is none. The server already puts it first; this
/// keeps it there when the list is changed locally.
List<ConversationSummary> withNoteToSelfFirst(List<ConversationSummary> chats) {
  final note = chats.where((chat) => chat.isNoteToSelf).firstOrNull;
  return [
    note ?? noteToSelfPlaceholder,
    for (final chat in chats)
      if (!chat.isNoteToSelf) chat,
  ];
}

/// The server side of the note to self.
abstract interface class NoteToSelfRepository {
  /// The conversation id of the user's note to self, made when missing.
  Future<String> ensure();
}

final noteToSelfRepositoryProvider = Provider<NoteToSelfRepository>((ref) {
  try {
    return SupabaseNoteToSelfRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedNoteToSelfRepository();
  }
});

class SupabaseNoteToSelfRepository implements NoteToSelfRepository {
  const SupabaseNoteToSelfRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> ensure() async {
    return await _client.rpc('get_note_to_self') as String;
  }
}

class _UninitializedNoteToSelfRepository implements NoteToSelfRepository {
  const _UninitializedNoteToSelfRepository();

  @override
  Future<String> ensure() async =>
      throw StateError('Supabase is not initialized.');
}

/// Opens the note to self: the chat [conversation] names when it exists,
/// otherwise made first. Called for the placeholder row.
Future<void> openNoteToSelf(
  BuildContext context,
  ProviderContainer container,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final String id;
  try {
    id = await container.read(noteToSelfRepositoryProvider).ensure();
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("Couldn't open your note to self."))),
    );
    return;
  }
  container.invalidate(conversationsProvider);
  if (!context.mounted) {
    return;
  }
  openPage(
    context,
    '${ChatsScreen.path}/$id',
    extra: ChatThreadRouteExtra(
      title: noteToSelfTitle(),
      type: ConversationType.direct,
    ),
  );
}

/// The avatar of the note to self in lists and headers: an accent squircle
/// with a devices icon (the thing you send between your own devices).
class NoteToSelfAvatar extends StatelessWidget {
  const NoteToSelfAvatar({this.size = 46, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ThingAvatar(
      key: const ValueKey('note-to-self-avatar'),
      icon: Icons.devices_rounded,
      size: size,
      color: c.accentSoft,
      foregroundColor: c.accentText,
      semanticLabel: noteToSelfTitle(),
    );
  }
}
