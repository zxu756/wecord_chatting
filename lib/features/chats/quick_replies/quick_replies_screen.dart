import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/quick_replies/away_reply_sheet.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_repository.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Chats -> Quick replies.
void openQuickReplies(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const QuickRepliesScreen()),
  );
}

/// Settings -> Chats -> Quick replies: the phrases to send with a slash, and
/// the away auto-reply. Private to the person; they follow the account to
/// other devices.
class QuickRepliesScreen extends ConsumerWidget {
  const QuickRepliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final data = ref.watch(quickRepliesProvider);
    final replies = data.value;
    final canAdd = replies != null && replies.length < maxQuickReplies;
    final away = ref.watch(awayReplyProvider).value;
    return SettingsPage(
      title: tr('Quick replies'),
      actions: [
        if (canAdd)
          WeCordButton(
            key: const ValueKey('quick-replies-new'),
            label: tr('New'),
            icon: Icons.add_rounded,
            size: WeCordButtonSize.small,
            variant: WeCordButtonVariant.accent,
            onPressed: () => unawaited(showQuickReplyEditor(context)),
          ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: Text(
            tr(
              'Type / in a chat and pick a phrase to put it in the message box. Only you can see them.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        if (replies == null && data.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (replies == null)
          Center(
            child: WeCordButton(
              label: tr('Try again'),
              onPressed: () => ref.invalidate(quickRepliesProvider),
            ),
          )
        else if (replies.isEmpty)
          _EmptyReplies(
            onCreate: () => unawaited(showQuickReplyEditor(context)),
          )
        else
          SettingsGroup(
            children: [
              for (final reply in replies)
                SettingsRow(
                  key: ValueKey('quick-reply-row-${reply.shortcut}'),
                  icon: Icons.bolt_outlined,
                  tone: SettingsTone.accent,
                  title: '/${reply.shortcut}',
                  subtitle: reply.body.replaceAll(RegExp(r'\s+'), ' '),
                  onTap: () =>
                      unawaited(showQuickReplyEditor(context, reply: reply)),
                ),
            ],
          ),
        if (replies != null && replies.length >= maxQuickReplies)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Text(
              tr('You can keep up to {count} quick replies.', {
                'count': maxQuickReplies,
              }),
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        SettingsSectionHeader(tr('While you are away')),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('away-reply-row'),
              icon: Icons.beach_access_outlined,
              tone: SettingsTone.warning,
              title: tr('Auto-reply when away'),
              subtitle: away == null
                  ? tr('Answers friends who write to you while you are away')
                  : awayReplySummary(context, away, DateTime.now()),
              onTap: () => unawaited(showAwayReplySheet(context)),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyReplies extends StatelessWidget {
  const _EmptyReplies({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        children: [
          Icon(Icons.bolt_outlined, size: 32, color: c.muted),
          const SizedBox(height: 8),
          Text(
            tr('No quick replies yet'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              'Keep an address, a payment note or an answer you give often, and send it with a slash.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
          const SizedBox(height: 12),
          WeCordButton(
            key: const ValueKey('quick-replies-empty-new'),
            label: tr('New quick reply'),
            icon: Icons.add_rounded,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

/// Opens the sheet to make a quick reply, or change [reply]. Resolves to
/// true when something was saved or deleted.
Future<bool?> showQuickReplyEditor(BuildContext context, {QuickReply? reply}) {
  return showWeCordSheet<bool>(
    context,
    title: reply == null ? tr('New quick reply') : tr('Edit quick reply'),
    builder: (context, _) => QuickReplyEditor(reply: reply),
  );
}

class QuickReplyEditor extends ConsumerStatefulWidget {
  const QuickReplyEditor({this.reply, super.key});

  final QuickReply? reply;

  @override
  ConsumerState<QuickReplyEditor> createState() => _QuickReplyEditorState();
}

class _QuickReplyEditorState extends ConsumerState<QuickReplyEditor> {
  late final _shortcutController = TextEditingController(
    text: widget.reply?.shortcut,
  );
  late final _bodyController = TextEditingController(text: widget.reply?.body);
  var _saving = false;
  QuickReplyProblem? _problem;
  String? _errorText;

  @override
  void dispose() {
    _shortcutController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String? get _shortcutError => switch (_problem) {
    QuickReplyProblem.shortcut => tr(
      'Use up to {count} characters, with no spaces or slashes.',
      {'count': maxQuickReplyShortcutLength},
    ),
    QuickReplyProblem.taken => tr('You already use that shortcut.'),
    _ => null,
  };

  String? get _bodyError => switch (_problem) {
    QuickReplyProblem.body => tr(
      'Write the phrase, up to {count} characters.',
      {'count': maxQuickReplyBodyLength},
    ),
    _ => null,
  };

  Future<void> _save() async {
    final shortcut = _shortcutController.text;
    final body = _bodyController.text;
    final problem = checkQuickReply(shortcut, body);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
      _errorText = null;
    });
    final repository = ref.read(quickRepliesRepositoryProvider);
    try {
      final existing = widget.reply;
      if (existing == null) {
        await repository.create(shortcut: shortcut, body: body);
      } else {
        await repository.update(existing.id, shortcut: shortcut, body: body);
      }
      ref.invalidate(quickRepliesProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on QuickReplyException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = error.problem;
          if (error.problem == QuickReplyProblem.limit) {
            _errorText = tr('You can keep up to {count} quick replies.', {
              'count': maxQuickReplies,
            });
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = tr('Could not save the quick reply. Try again.');
        });
      }
    }
  }

  Future<void> _delete() async {
    final existing = widget.reply;
    if (existing == null) {
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref.read(quickRepliesRepositoryProvider).delete(existing.id);
      ref.invalidate(quickRepliesProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = tr('Could not delete the quick reply. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordTextField(
                fieldKey: const ValueKey('quick-reply-shortcut'),
                controller: _shortcutController,
                enabled: !_saving,
                label: tr('Shortcut'),
                hint: tr('address'),
                helperText: tr('Typed after the slash.'),
                errorText: _shortcutError,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _problem = null),
              ),
              const SizedBox(height: 12),
              WeCordTextField(
                fieldKey: const ValueKey('quick-reply-body'),
                controller: _bodyController,
                enabled: !_saving,
                label: tr('Phrase'),
                hint: tr('What is put in the message box'),
                errorText: _bodyError,
                minLines: 3,
                maxLines: 8,
                onChanged: (_) => setState(() => _problem = null),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ],
              const SizedBox(height: 20),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: 8,
                children: [
                  if (widget.reply != null)
                    WeCordButton(
                      key: const ValueKey('quick-reply-delete'),
                      label: tr('Delete'),
                      icon: Icons.delete_outline_rounded,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: _saving ? null : () => unawaited(_delete()),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WeCordButton(
                        label: tr('Cancel'),
                        variant: WeCordButtonVariant.secondary,
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      WeCordButton(
                        key: const ValueKey('quick-reply-save'),
                        label: tr('Save'),
                        loading: _saving,
                        onPressed: _saving ? null : () => unawaited(_save()),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
