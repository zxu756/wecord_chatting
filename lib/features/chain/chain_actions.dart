import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Runs a change to a chain, shows what went wrong as a snack bar, and reads
/// the chain again straight away (Realtime would do it a moment later).
/// Returns whether it worked.
Future<bool> runChainAction(
  BuildContext context,
  WidgetRef ref,
  String chainId,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    ref.invalidate(chainProvider(chainId));
    if (success != null) {
      messenger?.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } on ChainException catch (error) {
    ref.invalidate(chainProvider(chainId));
    messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("That didn't work. Try again."))),
    );
    return false;
  }
}

Future<void> copyChainList(BuildContext context, ChainSnapshot chain) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: chain.exportText()));
  messenger?.showSnackBar(SnackBar(content: Text(tr('List copied.'))));
}

Future<void> shareChainList(BuildContext context, ChainSnapshot chain) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SharePlus.instance.share(
      ShareParams(text: chain.exportText(), title: chain.title),
    );
  } on Object {
    // No share sheet here (some desktops): the list goes to the clipboard.
    await Clipboard.setData(ClipboardData(text: chain.exportText()));
    messenger?.showSnackBar(SnackBar(content: Text(tr('List copied.'))));
  }
}

/// Opens the note sheet: joining (a note is optional) or, when the person is
/// in the chain, editing or removing their line.
Future<void> showChainNoteSheet(
  BuildContext context, {
  required ChainSnapshot chain,
}) {
  return showWeCordSheet<void>(
    context,
    title: chain.myEntry == null ? tr('Join the chain') : tr('Your line'),
    builder: (context, _) => ChainNoteSheet(chain: chain),
  );
}

class ChainNoteSheet extends ConsumerStatefulWidget {
  const ChainNoteSheet({required this.chain, super.key});

  final ChainSnapshot chain;

  @override
  ConsumerState<ChainNoteSheet> createState() => _ChainNoteSheetState();
}

class _ChainNoteSheetState extends ConsumerState<ChainNoteSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.chain.myEntry?.note ?? '',
  );
  var _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final chain = widget.chain;
    final joining = chain.myEntry == null;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    ChainWriteResult? result;
    final ok = await runChainAction(context, ref, chain.id, () async {
      final repository = ref.read(chainRepositoryProvider);
      result = joining
          ? await repository.join(chain.id, _note.text)
          : await repository.updateNote(chain.id, _note.text);
    });
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() => _busy = false);
      return;
    }
    navigator.pop();
    if (result?.noteHeld == true) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Your line is in, without the note: this circle reviews what new members write.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _remove() async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final ok = await runChainAction(
      context,
      ref,
      widget.chain.id,
      () => ref.read(chainRepositoryProvider).leave(widget.chain.id),
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final chain = widget.chain;
    final joining = chain.myEntry == null;
    final number = joining
        ? chain.entries.length + 1
        : chain.entries.indexWhere((e) => e.id == chain.myEntryId) + 1;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              chain.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            WeCordTextField(
              fieldKey: const ValueKey('chain-note-field'),
              controller: _note,
              label: tr('Note (optional)'),
              hint: chain.example.isNotEmpty
                  ? chain.example
                  : tr('For example: bringing snacks'),
              helperText: tr('You will be number {number}.', {
                'number': number,
              }),
              maxLength: 200,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_save()),
            ),
            const SizedBox(height: 12),
            WeCordButton(
              key: const ValueKey('chain-note-save'),
              label: joining ? tr('Join') : tr('Save'),
              variant: WeCordButtonVariant.accent,
              size: WeCordButtonSize.large,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
            if (!joining) ...[
              const SizedBox(height: 8),
              WeCordButton(
                key: const ValueKey('chain-note-remove'),
                label: tr('Remove my line'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _busy ? null : _remove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
