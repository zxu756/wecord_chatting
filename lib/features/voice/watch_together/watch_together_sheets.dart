import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';
import 'package:wecord/features/voice/watch_together/watch_together_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

// -------------------------------------------------------------- the button --

/// The watch together button of a call: starts sharing a link when nothing is
/// on, opens the options while something is. Shown to everyone in a
/// connected call.
class WatchTogetherButton extends ConsumerWidget {
  const WatchTogetherButton({this.size, super.key});

  /// The button's size; the header size by default.
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final active = ref.watch(watchTogetherProvider.select((s) => s.active));
    if (session == null || !session.isConnected) {
      return const SizedBox.shrink();
    }
    return VoiceControlButton(
      key: const ValueKey('voice-watch-button'),
      icon: active ? Icons.smart_display_rounded : Icons.smart_display_outlined,
      tooltip: active
          ? tr('Watching together')
          : tr('Watch or listen together'),
      on: active,
      size: size ?? (usesTouchInput(context) ? 42 : 38),
      onPressed: () => unawaited(showWatchTogetherSheet(context, ref)),
    );
  }
}

/// Opens the start form when nothing is on, the options when something is.
Future<void> showWatchTogetherSheet(BuildContext context, WidgetRef ref) {
  return showWeCordSheet<void>(
    context,
    title: tr('Watch or listen together'),
    builder: (sheetContext, _) => const WatchTogetherSheet(),
  );
}

// ------------------------------------------------------------- the sheet --

class WatchTogetherSheet extends ConsumerStatefulWidget {
  const WatchTogetherSheet({super.key});

  @override
  ConsumerState<WatchTogetherSheet> createState() => _WatchTogetherSheetState();
}

class _WatchTogetherSheetState extends ConsumerState<WatchTogetherSheet> {
  final _link = TextEditingController();
  var _changing = false;
  var _showProblem = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watch = ref.watch(watchTogetherProvider);
    final showForm = !watch.active || (watch.isHost && _changing);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: showForm ? _form(context, watch) : _options(context, watch),
    );
  }

  // ----------------------------------------------------------- the form --

  WatchLinkResult get _result => parseWatchLink(_link.text);

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _link.text = text;
      _showProblem = false;
    });
  }

  Future<void> _start() async {
    final result = _result;
    if (result.link == null) {
      setState(() => _showProblem = true);
      return;
    }
    final navigator = Navigator.of(context);
    final problem = await ref
        .read(watchTogetherProvider.notifier)
        .start(_link.text);
    if (!mounted) {
      return;
    }
    if (problem != null) {
      setState(() => _showProblem = true);
      return;
    }
    navigator.pop();
  }

  Widget _form(BuildContext context, WatchTogetherState watch) {
    final c = context.tokens.colors;
    final result = _result;
    final link = result.link;
    final typed = _link.text.trim().isNotEmpty;
    final problem = _showProblem ? result.problem : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Point(
          icon: Icons.sync_rounded,
          text: tr(
            'Share a link to a video or a song. Everyone in the call plays it on their own device, and what you play, pause or skip to is kept in step.',
          ),
        ),
        _Point(
          icon: Icons.cloud_off_outlined,
          text: tr(
            'Only the playing position is shared. The video or music itself is never sent through the call.',
          ),
        ),
        _Point(
          icon: Icons.headphones_outlined,
          text: tr('Wear headphones so the sound does not echo into the call.'),
        ),
        const SizedBox(height: 10),
        WeCordTextField(
          fieldKey: const ValueKey('watch-link-field'),
          controller: _link,
          label: tr('Link'),
          hint: 'https://…',
          prefixIcon: Icons.link_rounded,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          errorText: problem == null ? null : _problemText(problem),
          onChanged: (_) => setState(() => _showProblem = false),
          onSubmitted: (_) => unawaited(_start()),
          suffix: IconButton(
            key: const ValueKey('watch-paste'),
            tooltip: tr('Paste'),
            icon: const Icon(Icons.content_paste_rounded, size: 20),
            onPressed: () => unawaited(_paste()),
          ),
        ),
        if (link != null) ...[
          const SizedBox(height: 10),
          _KindHint(link: link),
        ] else if (!typed)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Text(
              tr(
                'Video files (MP4), streams (HLS) and music files (MP3, M4A) stay in step. Web pages like YouTube or Bilibili are played by each person on their own.',
              ),
              key: const ValueKey('watch-formats'),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
            ),
          ),
        const SizedBox(height: 16),
        WeCordButton(
          key: const ValueKey('watch-start'),
          label: watch.active ? tr('Switch to this link') : tr('Start'),
          icon: Icons.play_arrow_rounded,
          expand: true,
          size: WeCordButtonSize.large,
          onPressed: link == null && typed
              ? () => setState(() => _showProblem = true)
              : (typed ? () => unawaited(_start()) : null),
        ),
        if (watch.active) ...[
          const SizedBox(height: 8),
          WeCordButton(
            label: tr('Cancel'),
            variant: WeCordButtonVariant.secondary,
            expand: true,
            onPressed: () => setState(() => _changing = false),
          ),
        ],
      ],
    );
  }

  String _problemText(WatchLinkProblem problem) {
    return switch (problem) {
      WatchLinkProblem.empty => tr('Enter a link to share.'),
      WatchLinkProblem.invalid => tr('That does not look like a web link.'),
      WatchLinkProblem.notHttps => tr('Only secure https:// links work.'),
      WatchLinkProblem.tooLong => tr('That link is too long.'),
      WatchLinkProblem.privateAddress => tr(
        'That address is only on a private network, so the others cannot open it.',
      ),
    };
  }

  // -------------------------------------------------------- the options --

  Widget _options(BuildContext context, WatchTogetherState watch) {
    final c = context.tokens.colors;
    final controller = ref.read(watchTogetherProvider.notifier);
    final link = watch.link!;
    final navigator = Navigator.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                watch.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                watch.isHost
                    ? tr('You are the host')
                    : tr('Hosted by {name}', {
                        'name': watch.hostName ?? tr('Someone'),
                      }),
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const SizedBox(height: 2),
              Text(
                link.uri.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ],
          ),
        ),
        if (!link.synced)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 2),
            child: Text(
              tr(
                'This kind of link can only be played by each person on their own, so the progress cannot be kept in step.',
              ),
              style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
            ),
          ),
        SettingsGroup(
          separatorIndent: 58,
          footer: tr(
            'These only change your own screen and sound. Everyone else keeps watching.',
          ),
          children: [
            if (link.synced)
              SettingsRow.toggle(
                key: const ValueKey('watch-sheet-mute'),
                icon: Icons.volume_off_outlined,
                title: tr('Mute on my side'),
                value: watch.muted,
                onChanged: (value) => unawaited(controller.setMuted(value)),
              ),
            if (!link.isAudio)
              SettingsRow.toggle(
                key: const ValueKey('watch-sheet-hide'),
                icon: Icons.visibility_off_outlined,
                title: tr('Hide picture'),
                value: watch.hidden,
                onChanged: (value) {
                  controller.setHidden(value);
                  navigator.pop();
                },
              ),
            if (!watch.isHost)
              SettingsRow(
                key: const ValueKey('watch-sheet-leave'),
                icon: watch.dismissed
                    ? Icons.play_circle_outline_rounded
                    : Icons.exit_to_app_rounded,
                title: watch.dismissed
                    ? tr('Watch again')
                    : tr('Stop watching on my side'),
                onTap: () {
                  if (watch.dismissed) {
                    controller.rejoin();
                  } else {
                    controller.leaveMine();
                  }
                  navigator.pop();
                },
              ),
          ],
        ),
        if (watch.isHost) ...[
          const SizedBox(height: 16),
          WeCordButton(
            key: const ValueKey('watch-change'),
            label: tr('Change link'),
            icon: Icons.swap_horiz_rounded,
            variant: WeCordButtonVariant.secondary,
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () => setState(() {
              _changing = true;
              _link.clear();
              _showProblem = false;
            }),
          ),
          const SizedBox(height: 8),
          WeCordButton(
            key: const ValueKey('watch-end'),
            label: tr('End for everyone'),
            icon: Icons.stop_rounded,
            variant: WeCordButtonVariant.secondary,
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () {
              navigator.pop();
              unawaited(controller.end());
            },
          ),
        ],
      ],
    );
  }
}

/// What kind of link it is and whether it stays in step.
class _KindHint extends StatelessWidget {
  const _KindHint({required this.link});

  final WatchLink link;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (icon, text) = switch (link.kind) {
      WatchLinkKind.video => (
        Icons.movie_outlined,
        tr('Video · everyone stays in step'),
      ),
      WatchLinkKind.hls => (
        Icons.live_tv_outlined,
        tr('Video stream (HLS) · everyone stays in step'),
      ),
      WatchLinkKind.audio => (
        Icons.headphones_outlined,
        tr('Music or audio · everyone stays in step'),
      ),
      WatchLinkKind.webPage => (
        Icons.language_rounded,
        tr(
          'Web page · each person plays it on their own, and the progress cannot be kept in step.',
        ),
      ),
    };
    final warn = link.kind == WatchLinkKind.webPage
        ? c.warningText
        : c.successText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const ValueKey('watch-kind-hint'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: warn,
                ),
              ),
            ),
          ],
        ),
        if (kIsWeb && link.kind == WatchLinkKind.hls)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 26),
            child: Text(
              tr(
                'Some browsers cannot play HLS streams. Safari can; otherwise try an MP4 link.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.35, color: c.muted),
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}
