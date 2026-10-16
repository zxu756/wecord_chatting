import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/search_highlight.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Results grouped by where they were sent, in the order each place first
/// appears.
List<SearchResultGroup> groupSearchHits(List<SearchHit> hits) {
  final groups = <String, SearchResultGroup>{};
  for (final hit in hits) {
    groups
        .putIfAbsent(
          hit.conversationId,
          () => SearchResultGroup(hit.conversationId, hit.place),
        )
        .hits
        .add(hit);
  }
  return groups.values.toList(growable: false);
}

class SearchResultGroup {
  SearchResultGroup(this.conversationId, this.place);

  final String conversationId;
  final SearchPlace? place;
  final hits = <SearchHit>[];
}

/// "128 results", "1 result", "1000+ results".
String searchTotalLabel(int total, {bool capped = false}) {
  if (capped) {
    return tr('{count}+ results', {'count': total});
  }
  return total == 1 ? tr('1 result') : tr('{count} results', {'count': total});
}

/// When a result was sent: "Today 9:20", "10/14 9:20".
String searchHitTime(DateTime value, {DateTime? now}) {
  return '${chatDayLabel(value, now: now)} ${chatClockTime(value)}';
}

/// The text a result shows: the message as one line of text, starting near
/// the first match.
String searchHitText(ChatMessage message, List<String> terms) {
  return searchSnippet(pinnedMessagePreview(message), terms);
}

/// A place's header above its results.
class SearchGroupHeader extends StatelessWidget {
  const SearchGroupHeader({required this.group, this.count, super.key});

  final SearchResultGroup group;

  /// Matches in this place (from the first page), when known.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final place = group.place;
    final label = place?.label ?? tr('Conversation');
    final subtitle = place?.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          SearchPlaceAvatar(place: place, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle != null)
                    TextSpan(
                      text: '  $subtitle',
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count case final count?)
            Text(
              '$count',
              key: ValueKey('search-group-count-${group.conversationId}'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
        ],
      ),
    );
  }
}

/// A channel's tag tile, a group's squircle or the other person's avatar.
class SearchPlaceAvatar extends StatelessWidget {
  const SearchPlaceAvatar({required this.place, this.size = 36, super.key});

  final SearchPlace? place;
  final double size;

  @override
  Widget build(BuildContext context) {
    final place = this.place;
    if (place == null) {
      return SettingsIconTile(icon: Icons.chat_bubble_outline, size: size);
    }
    return switch (place.type) {
      ConversationType.channel => SettingsIconTile(
        icon: Icons.tag_rounded,
        size: size,
      ),
      ConversationType.thread => SettingsIconTile(
        icon: Icons.forum_outlined,
        size: size,
      ),
      ConversationType.group => ResolvedAvatar(
        name: place.label,
        avatarUrl: place.avatarUrl,
        size: size,
        squircle: true,
      ),
      ConversationType.direct => ResolvedAvatar(
        name: place.label,
        avatarUrl: place.avatarUrl,
        size: size,
      ),
    };
  }
}

/// One result: who, when, the text with its matches marked, and the
/// messages around it on demand. Tapping opens the conversation at it.
class SearchHitTile extends ConsumerStatefulWidget {
  const SearchHitTile({
    required this.hit,
    required this.terms,
    required this.onOpen,
    this.first = false,
    this.last = false,
    super.key,
  });

  final SearchHit hit;
  final List<String> terms;
  final VoidCallback onOpen;

  /// Round the top or bottom corners (the first and last of a group).
  final bool first;
  final bool last;

  @override
  ConsumerState<SearchHitTile> createState() => _SearchHitTileState();
}

class _SearchHitTileState extends ConsumerState<SearchHitTile> {
  var _expanded = false;
  Future<SearchContext>? _context;

  void _toggleContext() {
    setState(() {
      _expanded = !_expanded;
      _context ??= ref
          .read(messageSearchRepositoryProvider)
          .context(widget.hit.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final radius = BorderRadius.vertical(
      top: Radius.circular(widget.first ? WeCordRadii.xl : 0),
      bottom: Radius.circular(widget.last ? WeCordRadii.xl : 0),
    );
    return Container(
      decoration: BoxDecoration(color: c.panel, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_expanded)
            _ContextMessages(
              future: _context!,
              before: true,
              terms: widget.terms,
            ),
          _HitBody(
            hit: widget.hit,
            terms: widget.terms,
            onOpen: widget.onOpen,
            expanded: _expanded,
            onToggleContext: _toggleContext,
            radius: _expanded ? BorderRadius.zero : radius,
          ),
          if (_expanded)
            _ContextMessages(
              future: _context!,
              before: false,
              terms: widget.terms,
            ),
          if (!widget.last)
            Padding(
              padding: const EdgeInsets.only(left: 62),
              child: Container(height: 1, color: c.lineSoft),
            ),
        ],
      ),
    );
  }
}

class _HitBody extends StatelessWidget {
  const _HitBody({
    required this.hit,
    required this.terms,
    required this.onOpen,
    required this.expanded,
    required this.onToggleContext,
    required this.radius,
  });

  final SearchHit hit;
  final List<String> terms;
  final VoidCallback onOpen;
  final bool expanded;
  final VoidCallback onToggleContext;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final message = hit.message;
    final text = searchHitText(message, terms);
    final attachmentIcon = switch (message.type) {
      MessageType.image => Icons.image_outlined,
      MessageType.file =>
        message.fileAttachment?.isVideo == true
            ? Icons.movie_outlined
            : Icons.insert_drive_file_outlined,
      MessageType.voice => Icons.mic_none_rounded,
      MessageType.poll => Icons.poll_outlined,
      MessageType.sticker => Icons.emoji_emotions_outlined,
      _ => null,
    };
    return WeCordPressable(
      key: ValueKey('search-hit-${hit.id}'),
      onPressed: onOpen,
      pressedScale: 1,
      semanticLabel: '${hit.senderName}: $text',
      shape: RoundedRectangleBorder(borderRadius: radius),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          decoration: BoxDecoration(
            color: c.ink.withValues(alpha: hovered ? 0.035 : 0),
            borderRadius: radius,
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ResolvedAvatar(
                name: hit.senderName.isEmpty ? '?' : hit.senderName,
                avatarUrl: hit.senderAvatarUrl,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hit.senderName.isEmpty
                                ? tr('Unknown')
                                : hit.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          searchHitTime(message.createdAt),
                          style: TextStyle(fontSize: 12, color: c.subtle),
                        ),
                        if (hit.pinned) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.push_pin_rounded,
                            size: 13,
                            color: c.subtle,
                            semanticLabel: tr('Pinned'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (attachmentIcon != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 6),
                            child: Icon(
                              attachmentIcon,
                              size: 16,
                              color: c.muted,
                            ),
                          ),
                        ],
                        Expanded(
                          child: Text.rich(
                            highlightSearchMatches(
                              text,
                              terms,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.4,
                                color: c.ink,
                              ),
                              highlight: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.accentText,
                                backgroundColor: c.accentSoft,
                              ),
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              WeCordIconButton(
                key: ValueKey('search-hit-context-${hit.id}'),
                icon: expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                tooltip: expanded ? tr('Hide context') : tr('Show context'),
                size: 32,
                iconSize: 18,
                variant: WeCordButtonVariant.ghost,
                selected: expanded,
                onPressed: onToggleContext,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The message just before (or after) a result, quieter than it.
class _ContextMessages extends StatelessWidget {
  const _ContextMessages({
    required this.future,
    required this.before,
    required this.terms,
  });

  final Future<SearchContext> future;
  final bool before;
  final List<String> terms;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return FutureBuilder<SearchContext>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return before
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(62, 10, 14, 0),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: c.faint,
                    backgroundColor: c.lineSoft,
                  ),
                )
              : const SizedBox.shrink();
        }
        final data = snapshot.data;
        final messages = before
            ? data?.before ?? const <SearchHit>[]
            : data?.after ?? const <SearchHit>[];
        if (snapshot.hasError || messages.isEmpty) {
          return before
              ? const SizedBox(height: 4)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(62, 0, 14, 10),
                  child: Text(
                    snapshot.hasError
                        ? tr('Could not load the messages around it.')
                        : tr('Nothing after this.'),
                    style: TextStyle(fontSize: 12.5, color: c.subtle),
                  ),
                );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final hit in messages)
              Padding(
                key: ValueKey('search-context-${hit.id}'),
                padding: EdgeInsets.fromLTRB(62, before ? 10 : 0, 14, 10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                  decoration: BoxDecoration(
                    color: c.well,
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${hit.senderName}  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.muted,
                          ),
                        ),
                        TextSpan(text: pinnedMessagePreview(hit.message)),
                        TextSpan(
                          text: '  ${chatClockTime(hit.message.createdAt)}',
                          style: TextStyle(fontSize: 11.5, color: c.subtle),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.muted,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A quiet icon and a line or two of text in place of results.
class SearchHint extends StatelessWidget {
  const SearchHint({
    required this.icon,
    required this.title,
    this.text,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsIconTile(icon: icon, size: 56),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          if (text case final text?) ...[
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
            ),
          ],
          if (action case final action?) ...[
            const SizedBox(height: 14),
            action,
          ],
        ],
      ),
    );
  }
}

/// Keeps a callback from running more than once per frame burst (the list
/// asks for more while it is still building the last page).
class LoadMoreGate {
  var _pending = false;

  void request(Future<void> Function() load) {
    if (_pending) {
      return;
    }
    _pending = true;
    unawaited(load().whenComplete(() => _pending = false));
  }
}
