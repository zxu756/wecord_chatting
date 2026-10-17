import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/features/later/later_time.dart'
    show describeWhen, schedulePicks;
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the chain form for [conversationId]. Resolves to true once the card
/// is posted.
Future<bool?> showChainCreateSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('New chain'),
    detents: const [0.7, 0.94],
    builder: (context, scrollController) => ChainCreateSheet(
      conversationId: conversationId,
      scrollController: scrollController,
    ),
  );
}

/// The chain form: a title, an optional description and example line, and an
/// optional deadline and cap. Posting puts the card into the chat.
class ChainCreateSheet extends ConsumerStatefulWidget {
  const ChainCreateSheet({
    required this.conversationId,
    this.scrollController,
    super.key,
  });

  final String conversationId;
  final ScrollController? scrollController;

  @override
  ConsumerState<ChainCreateSheet> createState() => _ChainCreateSheetState();
}

class _ChainCreateSheetState extends ConsumerState<ChainCreateSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _example = TextEditingController();
  final _max = TextEditingController();
  DateTime? _deadline;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _example.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showWhenSheet(
      context,
      title: tr('Deadline'),
      picks: schedulePicks,
      initial: _deadline,
    );
    if (picked != null && mounted) {
      setState(() => _deadline = picked);
    }
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('Give the chain a title.'));
      return;
    }
    final max = int.tryParse(_max.text.trim());
    if (_max.text.trim().isNotEmpty && (max == null || max < 1 || max > 500)) {
      setState(() => _error = tr('Max entries is a number from 1 to 500.'));
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(chainRepositoryProvider)
          .create(
            widget.conversationId,
            ChainDraft(
              title: title,
              description: _description.text,
              example: _example.text,
              deadline: _deadline,
              maxEntries: max,
            ),
          );
      if (mounted) {
        navigator.pop(true);
      }
    } on ChainException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr("Couldn't post the chain. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final deadline = _deadline;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Everyone in the chat can add a line. The card updates for all of them as it fills.',
              ),
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 16),
            WeCordTextField(
              fieldKey: const ValueKey('chain-title-field'),
              controller: _title,
              label: tr('Title'),
              hint: tr('Saturday hike sign-up'),
              maxLength: 120,
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            WeCordTextField(
              fieldKey: const ValueKey('chain-description-field'),
              controller: _description,
              label: tr('Description (optional)'),
              hint: tr('Meet at the gate at 8.'),
              maxLines: 4,
              minLines: 2,
              maxLength: 1000,
            ),
            const SizedBox(height: 12),
            WeCordTextField(
              fieldKey: const ValueKey('chain-example-field'),
              controller: _example,
              label: tr('Example line (optional)'),
              hint: tr('1. Ada +1'),
              maxLength: 200,
            ),
            const SizedBox(height: 12),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('chain-deadline-row'),
                  icon: Icons.event_outlined,
                  title: tr('Deadline'),
                  value: deadline == null
                      ? tr('None')
                      : describeWhen(
                          MaterialLocalizations.of(context),
                          deadline.toLocal(),
                          DateTime.now(),
                          alwaysUse24HourFormat:
                              MediaQuery.alwaysUse24HourFormatOf(context),
                        ),
                  onTap: () => unawaited(_pickDeadline()),
                ),
                if (deadline != null)
                  SettingsRow(
                    key: const ValueKey('chain-deadline-clear'),
                    icon: Icons.close_rounded,
                    title: tr('Remove deadline'),
                    showChevron: false,
                    onTap: () => setState(() => _deadline = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            WeCordTextField(
              fieldKey: const ValueKey('chain-max-field'),
              controller: _max,
              label: tr('Max entries (optional)'),
              hint: tr('No limit'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 3,
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const ValueKey('chain-create-error'),
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            WeCordButton(
              key: const ValueKey('chain-post'),
              label: tr('Post chain'),
              variant: WeCordButtonVariant.accent,
              size: WeCordButtonSize.large,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _post,
            ),
          ],
        ),
      ),
    );
  }
}
