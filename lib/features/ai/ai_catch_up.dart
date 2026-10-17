import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Unread messages from which a chat offers to summarize what was missed.
const aiCatchUpThreshold = 20;

/// Lets the chat's header menu ask the catch-up card for a summary.
class AiCatchUpController extends ChangeNotifier {
  var _requests = 0;

  /// How many summaries were asked for.
  int get requests => _requests;

  void requestSummary() {
    _requests++;
    notifyListeners();
  }
}

enum _Phase { hidden, offer, loading, done, empty, error }

/// The glass card above a chat's messages that summarizes what the reader
/// missed. It offers itself when the chat opens with at least
/// [aiCatchUpThreshold] unread messages, and runs when the header menu's
/// Summarize asks through [controller]. Dismissible; the summary stays
/// until then.
class AiCatchUpBanner extends ConsumerStatefulWidget {
  const AiCatchUpBanner({
    required this.conversationId,
    required this.controller,
    required this.unreadCount,
    required this.readMarker,
    required this.firstUnreadId,
    required this.onJumpToMessage,
    this.circleId,
    this.desktop = false,
    super.key,
  });

  final String conversationId;
  final String? circleId;
  final AiCatchUpController controller;

  /// The conversation's unread count, null until the list has it. The
  /// first value seen decides the offer: the chat marks itself read.
  final int? unreadCount;

  /// The reader's read position when the chat opened, if known.
  final ConversationReadMarker? readMarker;

  /// The first unread message once the chat has placed its NEW divider.
  final String? firstUnreadId;

  /// Scrolls the chat to a message.
  final ValueChanged<String> onJumpToMessage;
  final bool desktop;

  @override
  ConsumerState<AiCatchUpBanner> createState() => _AiCatchUpBannerState();
}

class _AiCatchUpBannerState extends ConsumerState<AiCatchUpBanner> {
  var _phase = _Phase.hidden;
  int? _unreadAtOpen;
  var _dismissedOffer = false;
  var _handledRequests = 0;
  var _recentMode = false;
  AiSummary? _summary;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _handledRequests = widget.controller.requests;
    widget.controller.addListener(_onRequested);
    _noteUnread();
  }

  @override
  void didUpdateWidget(covariant AiCatchUpBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onRequested);
      widget.controller.addListener(_onRequested);
    }
    _noteUnread();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onRequested);
    super.dispose();
  }

  void _noteUnread() {
    final count = widget.unreadCount;
    if (_unreadAtOpen != null || count == null) {
      return;
    }
    _unreadAtOpen = count;
    if (count >= aiCatchUpThreshold && _phase == _Phase.hidden) {
      _phase = _Phase.offer;
    }
  }

  void _onRequested() {
    if (widget.controller.requests == _handledRequests || !mounted) {
      return;
    }
    _handledRequests = widget.controller.requests;
    unawaited(_run());
  }

  Future<void> _run() async {
    final generation = ++_generation;
    final marker = widget.readMarker;
    final hasUnread =
        marker != null &&
        ((_unreadAtOpen ?? 0) > 0 || widget.firstUnreadId != null);
    setState(() {
      _phase = _Phase.loading;
      _recentMode = !hasUnread;
      _error = null;
    });
    try {
      final summary = await ref
          .read(aiRepositoryProvider)
          .summarize(
            conversationId: widget.conversationId,
            afterMessageId: marker?.lastReadMessageId,
            recent: !hasUnread,
            language: AiLanguage.appLanguage,
          );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _summary = summary;
        _phase = summary == null ? _Phase.empty : _Phase.done;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (error is AiNotConfiguredException) {
        ref.invalidate(aiStatusProvider);
      }
      setState(() {
        _error = error;
        _phase = _Phase.error;
      });
    }
  }

  void _dismiss() {
    _generation++;
    setState(() {
      _dismissedOffer = true;
      _phase = _Phase.hidden;
    });
  }

  String? get _jumpTarget {
    if (_recentMode) {
      return null;
    }
    return widget.firstUnreadId ?? _summary?.firstMessageId;
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(aiAvailableProvider(widget.circleId));
    if (!available || _phase == _Phase.hidden) {
      return const SizedBox.shrink();
    }
    if (_phase == _Phase.offer && _dismissedOffer) {
      return const SizedBox.shrink();
    }
    return AiCatchUpCard(
      key: const ValueKey('ai-catch-up-card'),
      desktop: widget.desktop,
      state: switch (_phase) {
        _Phase.offer => AiCatchUpState.offer,
        _Phase.loading => AiCatchUpState.loading,
        _Phase.done => AiCatchUpState.done,
        _Phase.empty => AiCatchUpState.empty,
        _ => AiCatchUpState.error,
      },
      unreadCount: _unreadAtOpen ?? 0,
      recent: _recentMode,
      summary: _summary,
      error: _error,
      onSummarize: () => unawaited(_run()),
      onJump: _jumpTarget == null
          ? null
          : () => widget.onJumpToMessage(_jumpTarget!),
      onDismiss: _dismiss,
    );
  }
}

enum AiCatchUpState { offer, loading, done, empty, error }

/// What [AiCatchUpBanner] shows, for each state.
class AiCatchUpCard extends StatelessWidget {
  const AiCatchUpCard({
    required this.state,
    required this.onDismiss,
    this.unreadCount = 0,
    this.recent = false,
    this.summary,
    this.error,
    this.onSummarize,
    this.onJump,
    this.desktop = false,
    super.key,
  });

  final AiCatchUpState state;
  final int unreadCount;
  final bool recent;
  final AiSummary? summary;
  final Object? error;
  final VoidCallback? onSummarize;

  /// Scrolls to the first unread message; null when there is none to go to.
  final VoidCallback? onJump;
  final VoidCallback onDismiss;
  final bool desktop;

  String _title() {
    return switch (state) {
      AiCatchUpState.offer => tr('{count} unread messages', {
        'count': unreadCount,
      }),
      AiCatchUpState.loading => tr('Summarizing…'),
      AiCatchUpState.done =>
        recent ? tr('Recent messages') : tr('What you missed'),
      AiCatchUpState.empty => tr('Nothing to summarize'),
      AiCatchUpState.error => tr("Couldn't summarize"),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final maxBody = math.min(
      desktop ? 360.0 : 300.0,
      MediaQuery.sizeOf(context).height * 0.38,
    );
    final retry =
        state == AiCatchUpState.error &&
        error is! AiNotConfiguredException &&
        error is! AiLimitReachedException &&
        error is! AiDisabledInCircleException;

    Widget? body;
    switch (state) {
      case AiCatchUpState.offer:
        body = Text(
          tr('Get a short summary of what happened while you were away.'),
          style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
        );
      case AiCatchUpState.loading:
        body = null;
      case AiCatchUpState.done:
        body = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxBody),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final bullet in summary?.bullets ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 1, right: 8),
                              child: Text(
                                '•',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  height: 1.4,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              bullet,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.4,
                                color: c.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      tr('Written by AI. Check anything important.'),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case AiCatchUpState.empty:
        body = Text(
          tr('There is nothing new here to catch up on.'),
          style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
        );
      case AiCatchUpState.error:
        body = Text(
          aiErrorMessage(error ?? const AiFailedException()),
          style: TextStyle(fontSize: 13.5, height: 1.4, color: c.dangerText),
        );
    }

    final actions = <Widget>[
      if (state == AiCatchUpState.offer)
        WeCordButton(
          key: const ValueKey('ai-catch-up-summarize'),
          label: tr('Summarize what you missed'),
          icon: Icons.auto_awesome_rounded,
          variant: WeCordButtonVariant.accent,
          onPressed: onSummarize,
        ),
      if (state == AiCatchUpState.done && onJump != null)
        WeCordButton(
          key: const ValueKey('ai-catch-up-jump'),
          label: tr('Jump to first unread'),
          icon: Icons.arrow_upward_rounded,
          variant: WeCordButtonVariant.secondary,
          onPressed: onJump,
        ),
      if (retry)
        WeCordButton(
          key: const ValueKey('ai-catch-up-retry'),
          label: tr('Try again'),
          variant: WeCordButtonVariant.secondary,
          onPressed: onSummarize,
        ),
    ];

    return Padding(
      padding: desktop
          ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
          : const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: _title(),
        child: WeCordGlass(
          elevation: GlassElevation.float,
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: c.accentText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title(),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (state == AiCatchUpState.loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.muted,
                        ),
                      ),
                    ),
                  WeCordIconButton(
                    key: const ValueKey('ai-catch-up-dismiss'),
                    tooltip: tr('Dismiss'),
                    icon: Icons.close_rounded,
                    size: 32,
                    iconSize: 18,
                    variant: WeCordButtonVariant.ghost,
                    onPressed: onDismiss,
                  ),
                ],
              ),
              if (body != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 8, 0),
                  child: body,
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
                  child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
