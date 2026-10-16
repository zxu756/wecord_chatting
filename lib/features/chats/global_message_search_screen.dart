import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

class GlobalMessageSearchScreen extends ConsumerStatefulWidget {
  const GlobalMessageSearchScreen({super.key});

  static const path = '/search/messages';

  @override
  ConsumerState<GlobalMessageSearchScreen> createState() =>
      _GlobalMessageSearchScreenState();
}

class _GlobalMessageSearchScreenState
    extends ConsumerState<GlobalMessageSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _query = '';
  var _generation = 0;
  var _isLoading = false;
  Object? _error;
  List<DiscoveryResult>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(title: tr('Search')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: WeCordTextField(
                    controller: _controller,
                    autofocus: true,
                    onPaper: true,
                    hint: tr('Search WeCord'),
                    prefixIcon: Icons.search_rounded,
                    textInputAction: TextInputAction.search,
                    onChanged: _scheduleSearch,
                  ),
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.tokens.colors;
    final normalizedQuery = _query.trim();
    if (normalizedQuery.isEmpty) {
      return _SearchHint(
        icon: Icons.manage_search_rounded,
        text: tr('Search messages, groups, and Circles'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.dangerText),
          ),
        ),
      );
    }
    final results = _results ?? const <DiscoveryResult>[];
    if (results.isEmpty) {
      return _SearchHint(
        icon: Icons.search_off_rounded,
        text: tr('No matching results'),
      );
    }
    final grouped = _groupResults(results);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        for (final entry in grouped.entries)
          SettingsGroup(
            header: entry.key,
            separatorIndent: 66,
            children: [
              for (final result in entry.value)
                _DiscoveryResultTile(result: result),
            ],
          ),
      ],
    );
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    final normalizedQuery = value.trim();
    setState(() {
      _query = value;
      _error = null;
      if (normalizedQuery.isEmpty) {
        _isLoading = false;
        _results = null;
      } else {
        _isLoading = true;
      }
    });
    if (normalizedQuery.isEmpty) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_runSearch(normalizedQuery, generation));
    });
  }

  Future<void> _runSearch(String query, int generation) async {
    try {
      final results = await ref
          .read(chatsRepositoryProvider)
          .searchDiscovery(query);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _isLoading = false;
        _results = results;
      });
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = error;
        _results = null;
      });
    }
  }
}

class _DiscoveryResultTile extends StatelessWidget {
  const _DiscoveryResultTile({required this.result});

  final DiscoveryResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final subtitle = result.subtitle;
    final leading = switch (result.type) {
      DiscoveryResultType.contact => PersonAvatar(name: result.title, size: 40),
      DiscoveryResultType.group ||
      DiscoveryResultType.circle => ThingAvatar(label: result.title, size: 40),
      DiscoveryResultType.circleChannel || DiscoveryResultType.message =>
        SettingsIconTile(icon: _iconFor(result.type), size: 40),
    };
    return WeCordPressable(
      onPressed: () => _openResult(context, result),
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) {
        final highlighted =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          color: c.ink.withValues(alpha: highlighted ? 0.04 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          // Message bodies are markdown with `<:name:id>`
                          // emoji.
                          result.type == DiscoveryResultType.message
                              ? plainTextFromMarkdown(subtitle)
                              : subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: c.muted,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
            ],
          ),
        );
      },
    );
  }
}

/// A quiet icon and line of text in place of results.
class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsIconTile(icon: icon, size: 56),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, List<DiscoveryResult>> _groupResults(
  List<DiscoveryResult> results,
) {
  final grouped = <String, List<DiscoveryResult>>{};
  for (final result in results) {
    final title = _sectionTitle(result.type);
    grouped.putIfAbsent(title, () => <DiscoveryResult>[]).add(result);
  }
  return grouped;
}

String _sectionTitle(DiscoveryResultType type) {
  return switch (type) {
    DiscoveryResultType.contact => tr('Contacts'),
    DiscoveryResultType.group => tr('Groups'),
    DiscoveryResultType.circle => tr('Circles'),
    DiscoveryResultType.circleChannel => tr('Channels'),
    DiscoveryResultType.message => tr('Messages'),
  };
}

IconData _iconFor(DiscoveryResultType type) {
  return switch (type) {
    DiscoveryResultType.contact => Icons.person_outline,
    DiscoveryResultType.group => Icons.group_outlined,
    DiscoveryResultType.circle => Icons.bubble_chart_outlined,
    DiscoveryResultType.circleChannel => Icons.tag,
    DiscoveryResultType.message => Icons.chat_bubble_outline,
  };
}

void _openResult(BuildContext context, DiscoveryResult result) {
  switch (result.type) {
    case DiscoveryResultType.circle:
      final circleId = result.circleId ?? result.id;
      context.go('${CircleRoutes.path}/$circleId');
    case DiscoveryResultType.circleChannel:
    case DiscoveryResultType.group:
    case DiscoveryResultType.contact:
    case DiscoveryResultType.message:
      final conversationId = result.conversationId;
      if (conversationId != null) {
        openPage(context, '${ChatsScreen.path}/$conversationId');
      } else if (result.circleId != null) {
        context.go('${CircleRoutes.path}/${result.circleId}');
      }
  }
}
