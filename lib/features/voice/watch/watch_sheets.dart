import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_media_screen.dart'
    show chatMediaProvider;
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/watch/watch_controller.dart';
import 'package:wecord/features/voice/watch/watch_embed_player_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/voice/watch/watch_embed_player_web.dart'
    show embedPlayersSupported;
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart'
    show MessageType, formatFileSize;
import 'package:wecord/shared/ui/ui.dart';

// ----------------------------------------------------------------- start --

/// Asks what to watch or listen to, and starts it for the whole call.
Future<void> showWatchStartSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Watch together'),
    detents: const [0.6, 0.92],
    initialDetent: 0.78,
    builder: (sheetContext, scrollController) =>
        WatchStartView(scrollController: scrollController),
  );
}

enum _StartTab { chat, link }

class WatchStartView extends ConsumerStatefulWidget {
  const WatchStartView({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<WatchStartView> createState() => _WatchStartViewState();
}

class _WatchStartViewState extends ConsumerState<WatchStartView> {
  var _tab = _StartTab.chat;
  final _link = TextEditingController();
  WatchLinkProblem? _problem;
  var _failed = false;
  var _starting = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _start(WatchSource source, {String? title}) async {
    if (_starting) {
      return;
    }
    setState(() {
      _starting = true;
      _failed = false;
    });
    final navigator = Navigator.of(context);
    final started = await ref
        .read(watchTogetherProvider.notifier)
        .start(source, title: title);
    if (!mounted) {
      return;
    }
    if (started) {
      navigator.pop();
    } else {
      setState(() {
        _starting = false;
        _failed = true;
      });
    }
  }

  void _startLink() {
    final result = parseWatchLink(_link.text);
    final source = result.source;
    if (source == null) {
      setState(() => _problem = result.problem);
      return;
    }
    setState(() => _problem = null);
    unawaited(_start(source));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Point(
            icon: Icons.devices_rounded,
            text: tr(
              "Everyone in the call plays it on their own device, and WeCord keeps you in step. Nothing is uploaded, downloaded or shared again.",
            ),
          ),
          _Point(
            icon: Icons.headphones_rounded,
            text: tr('Use headphones, or the sound goes round the call.'),
          ),
          const SizedBox(height: 10),
          WeCordSegmented<_StartTab>(
            segments: [
              WeCordSegment(
                value: _StartTab.chat,
                label: tr('From this chat'),
                key: const ValueKey('watch-tab-chat'),
              ),
              WeCordSegment(
                value: _StartTab.link,
                label: tr('A link'),
                key: const ValueKey('watch-tab-link'),
              ),
            ],
            selected: _tab,
            expand: true,
            semanticLabel: tr('What to watch'),
            onChanged: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: 14),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                key: const ValueKey('watch-start-failed'),
                tr('Could not start. Check your connection and try again.'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ),
          if (_tab == _StartTab.chat) _chatFiles() else _linkForm(),
        ],
      ),
    );
  }

  Widget _chatFiles() {
    final session = ref.watch(voiceSessionProvider);
    final c = context.tokens.colors;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final media = ref.watch(chatMediaProvider(session.conversationId));
    return media.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              tr('Could not load this chat’s files.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: c.muted),
            ),
            const SizedBox(height: 8),
            WeCordButton(
              label: tr('Try again'),
              variant: WeCordButtonVariant.secondary,
              onPressed: () =>
                  ref.invalidate(chatMediaProvider(session.conversationId)),
            ),
          ],
        ),
      ),
      data: (items) {
        final files = <(PreviewFile, String)>[];
        for (final item in items) {
          if (item.type != MessageType.file) {
            continue;
          }
          final file = PreviewFile.fromMediaItem(item);
          if (file == null) {
            continue;
          }
          if (file.kind == PreviewKind.video ||
              file.kind == PreviewKind.audio) {
            files.add((file, item.senderName));
          }
        }
        if (files.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              key: const ValueKey('watch-no-files'),
              tr(
                'No videos or songs in this chat yet. Send one first, or paste a link.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
            ),
          );
        }
        return SettingsGroup(
          separatorIndent: 58,
          children: [
            for (final (file, sender) in files)
              SettingsRow(
                key: ValueKey('watch-file-${file.messageId ?? file.path}'),
                icon: file.kind == PreviewKind.audio
                    ? Icons.headphones_rounded
                    : Icons.movie_outlined,
                title: file.name,
                subtitle: '$sender · ${formatFileSize(file.size)}',
                onTap: _starting
                    ? null
                    : () => unawaited(
                        _start(
                          WatchFileSource.fromPreview(file),
                          title: file.name,
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }

  String? _problemText(WatchLinkProblem? problem) {
    return switch (problem) {
      null => null,
      WatchLinkProblem.notALink => tr('That does not look like a link.'),
      WatchLinkProblem.notHttps => tr('Only links that start with https work.'),
      WatchLinkProblem.shortLink => tr(
        'Paste the full Bilibili link (it has bilibili.com/video/ in it), not the short one.',
      ),
      WatchLinkProblem.risky => tr(
        'This link looks risky, so it can not be played together.',
      ),
      WatchLinkProblem.unsupported => tr(
        'This link is not something a call can play. Try a YouTube or Bilibili video, or a link to an mp4 or mp3 file.',
      ),
    };
  }

  Widget _linkForm() {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('watch-link-field'),
          controller: _link,
          label: tr('Video or song link'),
          hint: tr('YouTube, Bilibili, or a link to an mp4 or mp3 file'),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onChanged: (_) {
            if (_problem != null) {
              setState(() => _problem = null);
            }
          },
          onSubmitted: (_) => _startLink(),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 8),
          Text(
            _problemText(_problem)!,
            key: const ValueKey('watch-link-problem'),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.dangerText),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          embedPlayersSupported
              ? tr(
                  'YouTube plays right here and is controlled together. Bilibili can not be controlled: everyone presses play, and you can send "play now" hints.',
                )
              : tr(
                  'In this app YouTube and Bilibili open in your browser, and you send "play now" hints. Links to mp4 and mp3 files play here and stay in step.',
                ),
          key: const ValueKey('watch-link-note'),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.subtle),
        ),
        const SizedBox(height: 14),
        WeCordButton(
          key: const ValueKey('watch-start-link'),
          label: tr('Start watching'),
          variant: WeCordButtonVariant.primary,
          size: WeCordButtonSize.large,
          expand: true,
          loading: _starting,
          onPressed: _startLink,
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- manage --

/// What is on and what this person can do about it: open control to
/// everyone, choose something else, stop for themselves, or (host and
/// moderators) for everyone.
Future<void> showWatchManageSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Watching together'),
    builder: (sheetContext, _) => const WatchManageView(),
  );
}

class WatchManageView extends ConsumerWidget {
  const WatchManageView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(watchTogetherProvider);
    final controller = ref.read(watchTogetherProvider.notifier);
    final session = ref.watch(voiceSessionProvider);
    final c = context.tokens.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (!watch.active || session == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, 28 + bottom),
        child: Text(
          tr('Nothing is being watched.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, color: c.muted),
        ),
      );
    }
    final isHost = controller.isHost;
    final canStop = controller.canStop;
    final host = isHost
        ? tr('You')
        : (watch.nameOf(watch.hostId ?? '') ?? tr('Someone'));
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 20 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            watch.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tr('Host: {name}', {'name': host}),
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 14),
          SettingsGroup(
            separatorIndent: 58,
            footer: isHost
                ? tr('Anyone in the call can play, pause and move it.')
                : null,
            children: [
              if (isHost)
                SettingsRow.toggle(
                  key: const ValueKey('watch-open-control'),
                  icon: Icons.groups_2_outlined,
                  title: tr('Everyone can control'),
                  value: watch.controlOpen,
                  onChanged: (value) =>
                      unawaited(controller.setControlOpen(value)),
                ),
              if (isHost)
                SettingsRow(
                  key: const ValueKey('watch-change'),
                  icon: Icons.swap_horiz_rounded,
                  title: tr('Choose something else'),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(showWatchStartSheet(context));
                  },
                ),
              SettingsRow(
                key: const ValueKey('watch-leave-for-me'),
                icon: Icons.visibility_off_outlined,
                title: watch.dismissed
                    ? tr('Watch again')
                    : tr('Stop watching on my screen'),
                onTap: () {
                  if (watch.dismissed) {
                    controller.rejoin();
                  } else {
                    controller.leaveForMe();
                  }
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          if (canStop) ...[
            const SizedBox(height: 18),
            WeCordButton(
              key: const ValueKey('watch-stop'),
              label: tr('Stop for everyone'),
              icon: Icons.stop_circle_outlined,
              variant: WeCordButtonVariant.secondary,
              expand: true,
              size: WeCordButtonSize.large,
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(controller.stop());
              },
            ),
          ],
        ],
      ),
    );
  }
}
