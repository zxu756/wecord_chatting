part of '../chat_thread_screen.dart';

// Composer extras: slowmode, the read-only notice, reply/edit banners, paste.

/// Rebuilds [builder] every second until [until], with the whole seconds
/// left (0 once it has passed or without [until]).
class _SlowmodeGate extends StatefulWidget {
  const _SlowmodeGate({required this.until, required this.builder});

  final DateTime? until;
  final Widget Function(BuildContext context, int remainingSeconds) builder;

  @override
  State<_SlowmodeGate> createState() => _SlowmodeGateState();
}

class _SlowmodeGateState extends State<_SlowmodeGate> {
  Timer? _ticker;

  int get _remainingSeconds {
    final until = widget.until;
    if (until == null) {
      return 0;
    }
    final left = until.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _SlowmodeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (_remainingSeconds == 0) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_remainingSeconds == 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _remainingSeconds);
  }
}

class _SlowmodeBanner extends StatelessWidget {
  const _SlowmodeBanner({required this.remainingSeconds});

  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: c.muted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        key: const ValueKey('composer-slowmode'),
        children: [
          Icon(Icons.timer_outlined, size: 15, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr('Slowmode is enabled'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (remainingSeconds > 0)
            Text(
              formatSlowmodeCountdown(remainingSeconds),
              key: const ValueKey('composer-slowmode-countdown'),
              style: style.copyWith(
                color: c.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// Takes the composer's place where the current user may not send.
class _ReadOnlyComposerNotice extends StatelessWidget {
  const _ReadOnlyComposerNotice({
    required this.desktop,
    required this.bottomGap,
    this.timedOutUntil,
    this.threadLocked = false,
  });

  final DateTime? timedOutUntil;

  /// The thread is locked: only moderators can reply.
  final bool threadLocked;
  final bool desktop;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 10,
        0,
        desktop ? 24 : 10,
        bottomGap,
      ),
      child: WeCordGlass(
        key: const ValueKey('chat-read-only-notice'),
        borderRadius: BorderRadius.circular(desktop ? 22 : WeCordRadii.xxl),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              timedOutUntil == null
                  ? Icons.lock_outline_rounded
                  : Icons.timer_outlined,
              size: 18,
              color: c.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(switch (timedOutUntil) {
                _ when threadLocked => tr(
                  'This thread is locked. Only moderators can reply.',
                ),
                final until? => tr(
                  "You're timed out until {time}. "
                  'You can read, but not send messages or react.',
                  {'time': formatTimeoutEnd(until)},
                ),
                null => tr(
                  "You don't have permission to send messages in this "
                  'channel',
                ),
              }, style: TextStyle(fontSize: 14, height: 1.4, color: c.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replying to or editing a message: a glass strip over the composer.
class _ComposerModeBanner extends StatelessWidget {
  const _ComposerModeBanner({
    required this.text,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String text;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordGlass(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: c.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          WeCordIconButton(
            tooltip: tooltip,
            icon: Icons.close_rounded,
            size: 32,
            iconSize: 18,
            variant: WeCordButtonVariant.ghost,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

/// Pastes pictures and files from the macOS pasteboard into the tray. When
/// the pasteboard holds none (plain text), the text field's own paste runs.
class _PasteFilesAction extends ContextAction<PasteTextIntent> {
  _PasteFilesAction({
    required this.read,
    required this.onFiles,
    required this.canAttach,
  });

  final Future<List<XFile>> Function() read;
  final void Function(List<XFile> files) onFiles;
  final bool Function() canAttach;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    unawaited(_paste(intent));
    return null;
  }

  Future<void> _paste(PasteTextIntent intent) async {
    final files = canAttach() ? await read() : const <XFile>[];
    if (files.isNotEmpty) {
      onFiles(files);
      return;
    }
    callingAction?.invoke(intent);
  }
}
