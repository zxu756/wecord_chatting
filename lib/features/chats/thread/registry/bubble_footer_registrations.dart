// Where bubble footer entries are registered.
//
// To add something under or inside a message bubble (a read status, a
// translation, an edit history link ...), write a `BubbleFooterEntry` in your
// feature's own file and add it to [bubbleFooterExtensions] with one line.
// The built-in entries (see bubble_footer_builtin.dart) use orders 100, 200,
// ... within each placement; pick a number in between to place yours.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/read_status/read_status_chat.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_builtin.dart';

/// Feature entries for the footer slot. Append yours here.
final List<BubbleFooterEntry> bubbleFooterExtensions = [
  // myFeatureFooterEntry,
  readStatusFooterEntry,
];

/// The slot's registry. Tests can override it to add or drop entries.
final bubbleFooterRegistryProvider = Provider<BubbleFooterRegistry>(
  (ref) => BubbleFooterRegistry([
    ...builtInBubbleFooterEntries,
    ...bubbleFooterExtensions,
  ]),
);
