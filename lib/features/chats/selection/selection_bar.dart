import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chats/selection/selection_actions.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/features/chats/selection/selection_forward_sheet.dart';
import 'package:wecord/features/chats/selection/selection_registrations.dart';
import 'package:wecord/features/chats/selection/selection_registry.dart';
import 'package:wecord/features/chats/selection/selection_rules.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The header of a chat in selection mode: Cancel and "3 selected". On
/// phones it floats as glass over the messages like the chat header it
/// replaces; on desktop it is the flat 58 bar.
class ChatSelectionHeader extends ConsumerWidget {
  const ChatSelectionHeader({
    required this.conversationId,
    required this.desktop,
    super.key,
  });

  final String conversationId;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final count = ref.watch(
      chatSelectionProvider(conversationId).select((state) => state.count),
    );
    final cancel = WeCordButton(
      key: const ValueKey('selection-cancel'),
      label: tr('Cancel'),
      variant: desktop
          ? WeCordButtonVariant.secondary
          : WeCordButtonVariant.ghost,
      size: WeCordButtonSize.small,
      onPressed: () =>
          ref.read(chatSelectionProvider(conversationId).notifier).cancel(),
    );
    final title = Semantics(
      liveRegion: true,
      header: true,
      child: Text(
        tr('{count} selected', {'count': count}),
        key: const ValueKey('selection-count'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: desktop ? TextAlign.start : TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: c.ink,
        ),
      ),
    );
    if (desktop) {
      return Container(
        key: const ValueKey('chat-selection-header'),
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            cancel,
          ],
        ),
      );
    }
    final top = MediaQuery.paddingOf(context).top;
    return WeCordGlass(
      key: const ValueKey('chat-selection-header'),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      padding: EdgeInsets.fromLTRB(10, top + 6, 10, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            cancel,
            Expanded(child: title),
            // Balances Cancel so the count stays centered.
            const SizedBox(width: 72),
          ],
        ),
      ),
    );
  }
}

/// The bar that replaces the composer in selection mode: Forward, Merge &
/// forward, Save, Copy and Delete for the selected messages.
class ChatSelectionBar extends ConsumerWidget {
  const ChatSelectionBar({
    required this.environment,
    required this.desktop,
    required this.bottomGap,
    super.key,
  });

  final SelectionEnvironment environment;
  final bool desktop;
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatSelectionProvider(environment.conversationId));
    final messages = state.ordered;
    final actions = SelectionActions(context, ref, environment);
    // Advanced chat privacy (G6) turns these four off; the server refuses
    // them as well.
    final restricted = ref.watch(
      restrictSharingProvider(environment.conversationId),
    );
    final restrictedHint = restricted
        ? tr('Turned off by advanced chat privacy.')
        : null;
    final canForward = !restricted && messages.any(canForwardMessage);
    final canSave = !restricted && messages.any(canSaveMessage);
    final canCopy =
        !restricted &&
        copyTextOfSelection(messages, nameOf: environment.senderName) != null;
    final canDelete = canDeleteSelection(
      messages,
      currentUserId: environment.currentUserId,
      canModerate: environment.canModerate,
    );

    final items = [
      _BarItem(
        key: const ValueKey('selection-forward'),
        icon: Icons.shortcut_rounded,
        label: tr('Forward'),
        hint: restrictedHint,
        onPressed: canForward
            ? () => unawaited(actions.forward(SelectionForwardMode.oneByOne))
            : null,
      ),
      _BarItem(
        key: const ValueKey('selection-merge'),
        icon: Icons.library_books_outlined,
        label: tr('Merge & forward'),
        hint: restrictedHint,
        onPressed: canForward
            ? () => unawaited(actions.forward(SelectionForwardMode.merged))
            : null,
      ),
      _BarItem(
        key: const ValueKey('selection-save'),
        icon: Icons.bookmark_border_rounded,
        label: tr('Save'),
        hint: restrictedHint,
        onPressed: canSave ? () => unawaited(actions.save()) : null,
      ),
      _BarItem(
        key: const ValueKey('selection-copy'),
        icon: Icons.copy_rounded,
        label: tr('Copy'),
        hint: restrictedHint,
        onPressed: canCopy ? () => unawaited(actions.copy()) : null,
      ),
      _BarItem(
        key: const ValueKey('selection-delete'),
        icon: Icons.delete_outline_rounded,
        label: tr('Delete'),
        destructive: true,
        hint: !canDelete && messages.isNotEmpty
            ? tr('You can only delete your own messages here.')
            : null,
        onPressed: canDelete ? () => unawaited(actions.delete()) : null,
      ),
      // What features add (selection_registrations.dart).
      for (final extra
          in ref
              .watch(selectionBarRegistryProvider)
              .entriesFor(
                SelectionBarContext(
                  context: context,
                  environment: environment,
                  messages: messages,
                  leaveSelection: () => ref
                      .read(
                        chatSelectionProvider(
                          environment.conversationId,
                        ).notifier,
                      )
                      .cancel(),
                ),
              ))
        _BarItem(
          key: extra.key,
          icon: extra.icon,
          label: extra.label,
          hint: extra.hint,
          onPressed: extra.onPressed,
        ),
    ];

    final c = context.tokens.colors;
    if (desktop) {
      return Container(
        key: const ValueKey('chat-selection-bar'),
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottomGap),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border(top: BorderSide(color: c.lineSoft)),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final item in items)
              Tooltip(
                message: item.hint ?? '',
                child: WeCordButton(
                  key: item.key,
                  label: item.label,
                  icon: item.icon,
                  variant: item.destructive
                      ? WeCordButtonVariant.danger
                      : WeCordButtonVariant.secondary,
                  onPressed: item.onPressed,
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      key: const ValueKey('chat-selection-bar'),
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomGap),
      child: WeCordGlass(
        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [for (final item in items) Expanded(child: item)]),
      ),
    );
  }
}

/// One button of the phone's selection bar: an icon over a short label.
class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.hint,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final enabled = onPressed != null;
    final color = !enabled
        ? c.faint
        : destructive
        ? c.dangerText
        : c.ink;
    return WeCordPressable(
      onPressed: onPressed,
      semanticLabel: label,
      hint: hint,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      builder: (context, states) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          decoration: BoxDecoration(
            color: states.contains(WidgetState.hovered)
                ? c.raised
                : c.raised.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
