import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/pat/pat_info.dart';
import 'package:wecord/features/pat/pat_repository.dart';
import 'package:wecord/features/pat/pat_shake.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The light system line of a pat in a chat: a small hand and "You patted
/// Ada's shoulder" / "Bart patted you". The patter sees "Undo" beside it for
/// 2 minutes; a pat that was taken back reads "… took back a pat".
class PatLine extends ConsumerStatefulWidget {
  const PatLine({required this.message, required this.pat, super.key});

  final ChatMessage message;
  final PatInfo pat;

  @override
  ConsumerState<PatLine> createState() => _PatLineState();
}

class _PatLineState extends ConsumerState<PatLine> {
  Timer? _expiry;
  var _undoing = false;
  var _wiggle = 0;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
    // A pat for me that just happened gives its hand a little wave.
    final me = ref.read(authStateProvider).value?.id;
    if (me != null &&
        widget.pat.targetId == me &&
        !widget.pat.undone &&
        _age < const Duration(seconds: 4)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _wiggle = 1);
        }
      });
    }
  }

  @override
  void didUpdateWidget(PatLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleExpiry();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Duration get _age =>
      clock.now().toUtc().difference(widget.message.createdAt.toUtc());

  /// Rebuilds once the undo window is over, so "Undo" goes away on its own.
  void _scheduleExpiry() {
    _expiry?.cancel();
    final left = patUndoWindow - _age;
    if (left > Duration.zero && !widget.pat.undone) {
      _expiry = Timer(left + const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  Future<void> _undo() async {
    if (_undoing) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _undoing = true);
    try {
      await ref.read(patRepositoryProvider).undo(widget.message.id);
    } on PatException catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            error.failure == PatFailure.undoExpired
                ? tr("It's too late to take that pat back.")
                : tr("Couldn't take the pat back. Try again."),
          ),
        ),
      );
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr("Couldn't take the pat back. Try again."))),
      );
    }
    if (mounted) {
      setState(() => _undoing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final me = ref.watch(authStateProvider.select((a) => a.value?.id));
    final pat = widget.pat;
    final canUndo =
        me != null && pat.actorId == me && !pat.undone && _age < patUndoWindow;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PatShake(
            trigger: _wiggle,
            child: Icon(
              pat.undone ? Icons.undo_rounded : Icons.waving_hand_outlined,
              size: 14,
              color: c.muted,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              patSentence(pat, currentUserId: me),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: c.muted,
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      key: ValueKey('pat-line-${widget.message.id}'),
      padding: EdgeInsets.fromLTRB(16, 4, 16, canUndo ? 2 : 10),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: pill),
            if (canUndo)
              WeCordTapTarget(
                minSize: Size.square(math.max(context.touchTargetSize, 32)),
                child: WeCordPressable(
                  key: const ValueKey('pat-undo'),
                  onPressed: _undoing ? null : () => unawaited(_undo()),
                  semanticLabel: tr('Take back the pat'),
                  excludeSemantics: true,
                  shape: const StadiumBorder(),
                  builder: (context, states) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      tr('Undo'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.accentText,
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
