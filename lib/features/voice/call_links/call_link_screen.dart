import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What a `/call/<code>` link is doing.
enum _Step { opening, joining, failed, blocked }

/// Opens a call link: joins the call or voice channel it leads to when the
/// current user may, and otherwise says why not on a friendly page.
class CallLinkScreen extends ConsumerStatefulWidget {
  const CallLinkScreen({required this.code, super.key});

  static const path = callLinkRoutePrefix;

  final String code;

  @override
  ConsumerState<CallLinkScreen> createState() => _CallLinkScreenState();
}

class _CallLinkScreenState extends ConsumerState<CallLinkScreen> {
  var _step = _Step.opening;
  CallLinkProblem? _problem;
  var _name = '';

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(_open));
  }

  Future<void> _open() async {
    if (!mounted) {
      return;
    }
    setState(() => _step = _Step.opening);
    final CallLinkResolution resolution;
    try {
      resolution = await ref
          .read(callLinksRepositoryProvider)
          .resolve(widget.code);
    } catch (_) {
      if (mounted) {
        setState(() => _step = _Step.failed);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (!resolution.isOk) {
      setState(() {
        _step = _Step.blocked;
        _problem = resolution.problem;
      });
      return;
    }
    setState(() {
      _step = _Step.joining;
      _name = resolution.name;
    });
    final joined = resolution.isChannel
        ? await joinVoiceChannel(
            context,
            ref,
            circleId: resolution.circleId!,
            channelId: resolution.channelId!,
            conversationId: resolution.conversationId!,
            channelName: resolution.name,
          )
        : await startDirectCall(
            context,
            ref,
            conversationId: resolution.conversationId!,
            name: resolution.name,
          );
    if (!mounted) {
      return;
    }
    final session = ref.read(voiceSessionProvider);
    if (joined && session != null) {
      context.go(voiceSessionPath(session));
      return;
    }
    setState(() => _step = _Step.failed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget body;
    switch (_step) {
      case _Step.opening:
      case _Step.joining:
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Semantics(
                liveRegion: true,
                child: Text(
                  _step == _Step.joining
                      ? tr('Joining {name}…', {'name': _name})
                      : tr('Opening the call link…'),
                  key: const ValueKey('call-link-status'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
        );
      case _Step.failed:
        body = CircleEmptyState(
          icon: Icons.error_outline_rounded,
          title: tr('Could not open the call link'),
          message: tr('Check your connection and try again.'),
          action: WeCordButton(
            key: const ValueKey('call-link-retry'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: _open,
            label: tr('Try again'),
          ),
        );
      case _Step.blocked:
        final (title, message) = switch (_problem) {
          CallLinkProblem.noAccess => (
            tr("You don't have access to this call"),
            tr(
              'Ask the person who sent the link to add you to the chat or '
              'circle, then open the link again.',
            ),
          ),
          CallLinkProblem.expired => (
            tr('This call link has expired'),
            tr('Ask the person who sent it for a new one.'),
          ),
          CallLinkProblem.revoked => (
            tr('This call link was turned off'),
            tr('Ask the person who sent it for a new one.'),
          ),
          _ => (
            tr("This call link doesn't exist"),
            tr('Check that the whole link was copied, then try again.'),
          ),
        };
        body = CircleEmptyState(
          icon: _problem == CallLinkProblem.noAccess
              ? Icons.lock_outline_rounded
              : Icons.link_off_rounded,
          title: title,
          message: message,
          action: WeCordButton(
            key: const ValueKey('call-link-home'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: () => context.go(HomeScreen.path),
            label: tr('Back to home'),
          ),
        );
    }
    return CirclePageScaffold(
      title: tr('Call link'),
      constrainBody: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: body,
        ),
      ),
    );
  }
}
