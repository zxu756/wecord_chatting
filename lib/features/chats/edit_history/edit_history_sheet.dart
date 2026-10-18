import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/edit_history/edit_history_repository.dart';
import 'package:wecord/features/chats/edit_history/edit_version.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the list of a message's versions, newest first: the text it has now,
/// then what it said before each edit, with the time of each.
Future<void> showEditHistory(BuildContext context, ChatMessage message) {
  return showWeCordSheet<void>(
    context,
    title: tr('Edit history'),
    builder: (context, _) => EditHistoryView(message: message),
  );
}

/// The content of the edit history sheet.
class EditHistoryView extends ConsumerWidget {
  const EditHistoryView({required this.message, this.now, super.key});

  final ChatMessage message;

  /// The time "now" for the spoken ages; tests set it.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(messageEditHistoryProvider(message.id));
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: history.when(
          loading: () => const SheetSpinner(),
          error: (error, stackTrace) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetNote(
                text: tr('Could not load the edit history.'),
                error: true,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: WeCordButton(
                  key: const ValueKey('edit-history-retry'),
                  label: tr('Retry'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: () =>
                      ref.invalidate(messageEditHistoryProvider(message.id)),
                ),
              ),
            ],
          ),
          data: (versions) =>
              _VersionList(message: message, versions: versions, now: now),
        ),
      ),
    );
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.message,
    required this.versions,
    required this.now,
  });

  final ChatMessage message;
  final List<MessageEditVersion> versions;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _VersionCard(
          key: const ValueKey('edit-version-current'),
          label: tr('Current'),
          current: true,
          body: message.body,
          mentions: message.mentions,
          time: message.editedAt ?? message.createdAt,
          now: now,
        ),
        for (final version in versions) ...[
          const SizedBox(height: 10),
          _VersionCard(
            key: ValueKey('edit-version-${version.version}'),
            label: version.isOriginal
                ? tr('Original')
                : tr('Version {number}', {'number': version.version}),
            current: false,
            body: version.body,
            mentions: version.mentions,
            time: version.editedAt,
            now: now,
          ),
        ],
        if (versions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              tr('No earlier versions were saved for this message.'),
              key: const ValueKey('edit-history-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
          ),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.label,
    required this.current,
    required this.body,
    required this.mentions,
    required this.time,
    required this.now,
    super.key,
  });

  final String label;
  final bool current;
  final String body;
  final List<MessageMention> mentions;
  final DateTime time;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      container: true,
      label: spokenList([
        label,
        spokenAge(time, now: now),
        plainTextFromMarkdown(body),
      ]),
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: current ? c.accentSoft : c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          border: Border.all(color: current ? c.accent : c.lineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: current ? c.accentText : c.muted,
                    ),
                  ),
                ),
                Text(
                  formatPreviewTime(time),
                  style: TextStyle(fontSize: 12.5, color: c.subtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            MessageMarkdownText(body: body, mentions: mentions, color: c.ink),
          ],
        ),
      ),
    );
  }
}
