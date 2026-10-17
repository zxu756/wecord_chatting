import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/pat/pat_info.dart';
import 'package:wecord/features/pat/pat_repository.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings → profile: "Pat suffix", the words that follow your name when
/// someone pats you ("You patted Ada's shoulder"). Opens [showPatSuffixSheet].
class PatSuffixRow extends ConsumerWidget {
  const PatSuffixRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suffix = ref.watch(patSuffixProvider).value ?? '';
    return SettingsRow(
      key: const ValueKey('pat-suffix-row'),
      icon: Icons.waving_hand_outlined,
      title: tr('Pat suffix'),
      value: suffix.isEmpty ? tr('None') : suffix,
      onTap: () => unawaited(showPatSuffixSheet(context)),
    );
  }
}

/// Edits the pat suffix: a short field, a few ideas, and a preview of how a
/// pat reads to friends.
Future<void> showPatSuffixSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Pat suffix'),
    builder: (context, _) => const PatSuffixSheet(),
  );
}

class PatSuffixSheet extends ConsumerStatefulWidget {
  const PatSuffixSheet({super.key});

  @override
  ConsumerState<PatSuffixSheet> createState() => _PatSuffixSheetState();
}

class _PatSuffixSheetState extends ConsumerState<PatSuffixSheet> {
  final _controller = TextEditingController();
  var _loaded = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(patRepositoryProvider).setSuffix(value);
      ref.invalidate(patSuffixProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr("Couldn't save the suffix. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final current = ref.watch(patSuffixProvider);
    if (!_loaded && current.hasValue) {
      _loaded = true;
      _controller.text = current.value ?? '';
    }
    final profile = ref.watch(currentProfileProvider).value;
    final ideas = [tr("'s shoulder"), tr("'s head"), tr("'s hand")];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('pat-suffix-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Friends see this after your name when they pat you. Double '
                'tap a friend\'s picture in a chat to pat them.',
              ),
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            WeCordTextField(
              controller: _controller,
              fieldKey: const ValueKey('pat-suffix-field'),
              label: tr('Pat suffix'),
              hint: tr("e.g. 's shoulder"),
              maxLength: patSuffixMaxLength,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) => unawaited(_save(value)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final idea in ideas)
                  WeCordChip(
                    label: idea,
                    selected: _controller.text.trim() == idea,
                    onPressed: _saving
                        ? null
                        : () => setState(() => _controller.text = idea),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Row(
                children: [
                  Icon(Icons.waving_hand_outlined, size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      key: const ValueKey('pat-suffix-preview'),
                      patSentence(
                        PatInfo(
                          actorId: 'friend',
                          targetId: 'me',
                          actorName: tr('Bart'),
                          targetName: profile?.displayLabel ?? tr('You'),
                          suffix: _controller.text.trim(),
                        ),
                        currentUserId: 'someone-else',
                      ),
                      style: TextStyle(fontSize: 14, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: c.dangerText),
                ),
              ),
            const SizedBox(height: 16),
            WeCordButton(
              key: const ValueKey('pat-suffix-save'),
              label: tr('Save'),
              expand: true,
              loading: _saving,
              onPressed: _saving
                  ? null
                  : () => unawaited(_save(_controller.text)),
            ),
          ],
        ),
      ),
    );
  }
}
