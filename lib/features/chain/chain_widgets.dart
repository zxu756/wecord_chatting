import 'package:flutter/material.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/later/later_time.dart' show describeWhen;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The deadline in words: "Closes Today 8:00 PM", or "Closed".
String chainStatusText(
  BuildContext context,
  ChainSnapshot chain,
  DateTime now,
) {
  if (chain.isClosed(now)) {
    return tr('Closed');
  }
  final deadline = chain.deadline;
  if (deadline == null) {
    return trIn('Chain', 'Open');
  }
  return tr('Closes {when}', {
    'when': describeWhen(
      MaterialLocalizations.of(context),
      deadline.toLocal(),
      now,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    ),
  });
}

/// "5 joined", "5 of 12 joined".
String chainCountText(ChainSnapshot chain) {
  final max = chain.maxEntries;
  if (max == null) {
    return tr('{count} joined', {'count': chain.entries.length});
  }
  return tr('{count} of {max} joined', {
    'count': chain.entries.length,
    'max': max,
  });
}

/// The small squircle with the list icon at the start of a chain card.
class ChainIconTile extends StatelessWidget {
  const ChainIconTile({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SettingsIconTile(
        icon: Icons.format_list_numbered_rounded,
        tone: SettingsTone.accent,
        size: size,
      ),
    );
  }
}

/// "Open", "Closes tomorrow 9 am" or "Closed" as a small pill.
class ChainStatusPill extends StatelessWidget {
  const ChainStatusPill({required this.text, this.closed = false, super.key});

  final String text;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: closed ? c.raised : c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (closed) ...[
            Icon(Icons.lock_outline_rounded, size: 12, color: c.muted),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: closed ? c.muted : c.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One numbered line: "3  Ada  bring snacks". Your own line is tinted.
class ChainLine extends StatelessWidget {
  const ChainLine({
    required this.number,
    required this.entry,
    required this.mine,
    this.trailing,
    this.avatar = false,
    super.key,
  });

  final int number;
  final ChainEntry entry;
  final bool mine;
  final Widget? trailing;

  /// Shows the person's avatar (the full list, not the card).
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final name = mine ? tr('{name} (you)', {'name': entry.displayName}) : null;
    final url = entry.avatarUrl;
    final line = Semantics(
      container: true,
      label: tr('{number}. {line}', {
        'number': number,
        'line': mine ? name! : entry.displayName,
      }),
      value: entry.note.trim().isEmpty ? null : entry.note.trim(),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$number.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: mine ? c.accentText : c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (avatar) ...[
              PersonAvatar(
                name: entry.displayName,
                size: 28,
                image: url == null ? null : NetworkImage(url),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: entry.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: mine ? c.accentText : c.ink,
                      ),
                    ),
                    if (entry.note.trim().isNotEmpty)
                      TextSpan(
                        text: '  ${entry.note.trim()}',
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: c.ink,
                        ),
                      ),
                  ],
                ),
                maxLines: avatar ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: avatar ? 6 : 4),
      decoration: BoxDecoration(
        color: mine ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: line),
          ?trailing,
        ],
      ),
    );
  }
}
