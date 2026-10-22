// Quick replies in a chat (A8).
//
// How it plugs into the chat page (see "Chat page extension points" in
// docs/design/wecord-design-language.md):
//
//  * Typing `/` in the message box lists the person's phrases before the
//    commands (slash_commands.dart); picking one puts it in the box.
//  * [quickRepliesComposerEntry] adds "Quick replies" to the composer's "+"
//    menu (composer_menu_registrations.dart) for phones, where a slash is
//    awkward to type: it opens [showQuickReplyPicker], and the page puts the
//    phrase in the box.
//  * [autoReplyFooterEntry] marks an auto-reply under its bubble
//    (bubble_footer_registrations.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart'
    show GlassMenuEntry;
import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_repository.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_screen.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Quick replies" in the "+" menu, after Send silently (850).
final quickRepliesComposerEntry = ComposerMenuContribution(
  id: 'quick-replies',
  order: 860,
  build: (ctx) {
    final pick = ctx.actions.pickQuickReply;
    if (pick == null) {
      return null;
    }
    return GlassMenuEntry(
      key: const ValueKey('composer-quick-replies-entry'),
      icon: Icons.bolt_outlined,
      label: tr('Quick replies'),
      onSelected: () => unawaited(pick()),
    );
  },
);

/// "Auto-reply" under a message the server sent for an away person.
const autoReplyFooterEntry = BubbleFooterEntry.below(
  id: 'auto-reply',
  order: 460,
  build: _autoReplyMark,
  wrap: BubbleFooterWrap.pill,
  cardGap: 4,
);

Widget? _autoReplyMark(BubbleFooterContext ctx) {
  if (!ctx.message.autoReply || ctx.isRecalled) {
    return null;
  }
  return const AutoReplyMark();
}

/// The small "Auto-reply" label with a beach umbrella.
class AutoReplyMark extends StatelessWidget {
  const AutoReplyMark({super.key});

  @override
  Widget build(BuildContext context) {
    final tint = context.tokens.colors.subtle;
    final label = tr('Auto-reply');
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          key: const ValueKey('auto-reply-mark'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.beach_access_outlined, size: 12, color: tint),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the list of the person's phrases; resolves to the one picked.
Future<QuickReply?> showQuickReplyPicker(BuildContext context) {
  return showWeCordSheet<QuickReply>(
    context,
    title: tr('Quick replies'),
    builder: (context, _) => const QuickReplyPicker(),
  );
}

class QuickReplyPicker extends ConsumerStatefulWidget {
  const QuickReplyPicker({super.key});

  @override
  ConsumerState<QuickReplyPicker> createState() => _QuickReplyPickerState();
}

class _QuickReplyPickerState extends ConsumerState<QuickReplyPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final data = ref.watch(quickRepliesProvider);
    final all = data.value;
    final query = _search.text.trim().toLowerCase();
    final shown = all == null
        ? const <QuickReply>[]
        : [
            for (final reply in all)
              if (query.isEmpty ||
                  reply.shortcut.contains(query) ||
                  reply.body.toLowerCase().contains(query))
                reply,
          ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (all != null && all.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: WeCordTextField(
                  fieldKey: const ValueKey('quick-reply-search'),
                  controller: _search,
                  hint: tr('Search quick replies'),
                  prefixIcon: Icons.search_rounded,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            Flexible(
              child: all == null && data.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : all == null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: WeCordButton(
                          label: tr('Try again'),
                          onPressed: () => ref.invalidate(quickRepliesProvider),
                        ),
                      ),
                    )
                  : shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      child: Text(
                        all.isEmpty
                            ? tr(
                                'No quick replies yet. Keep the phrases you send often and pick them here or with a slash.',
                              )
                            : tr('No quick reply matches.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: c.muted,
                        ),
                      ),
                    )
                  : Material(
                      type: MaterialType.transparency,
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final reply in shown)
                            ListTile(
                              key: ValueKey(
                                'quick-reply-pick-${reply.shortcut}',
                              ),
                              leading: const Icon(Icons.bolt_outlined),
                              title: Text(
                                '/${reply.shortcut}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                reply.body.replaceAll(RegExp(r'\s+'), ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.of(context).pop(reply),
                            ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: WeCordButton(
                  key: const ValueKey('quick-reply-manage'),
                  label: tr('Manage quick replies'),
                  icon: Icons.tune_rounded,
                  variant: WeCordButtonVariant.ghost,
                  onPressed: () => unawaited(
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (context) => const QuickRepliesScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
