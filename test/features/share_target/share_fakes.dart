import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/share_target/share_target_gateway.dart';
import 'package:wecord/features/share_target/shared_content.dart';

/// What "Share to WeCord" leaves waiting, held in memory.
class FakeShareTargetGateway implements ShareTargetGateway {
  FakeShareTargetGateway([this.content]);

  SharedContent? content;
  var cleared = 0;

  @override
  Future<SharedContent?> read() async => content;

  @override
  Future<void> clear() async {
    cleared++;
    content = null;
  }
}

/// The note to self the server makes on first use.
class FakeShareNoteToSelf implements NoteToSelfRepository {
  var ensured = 0;

  @override
  Future<String> ensure() async {
    ensured++;
    return 'note-1';
  }
}

/// A shared file whose bytes are [bytes].
SharedFile sharedFile(
  String name, {
  String mimeType = 'application/pdf',
  List<int> bytes = const [1, 2, 3, 4],
}) {
  return SharedFile(
    name: name,
    mimeType: mimeType,
    size: bytes.length,
    read: () async => Uint8List.fromList(bytes),
  );
}

List<Override> shareOverrides(
  FakeShareTargetGateway gateway, {
  FakeShareNoteToSelf? notes,
}) {
  return [
    shareTargetGatewayProvider.overrideWithValue(gateway),
    noteToSelfRepositoryProvider.overrideWithValue(
      notes ?? FakeShareNoteToSelf(),
    ),
  ];
}

/// A 1x1 PNG.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
