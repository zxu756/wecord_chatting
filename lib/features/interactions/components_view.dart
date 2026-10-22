import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_markdown_text.dart'
    show linkLauncherProvider;
import 'package:wecord/features/interactions/interactions_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message_components.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The buttons, links and lists a bot put on a message (or on a private
/// reply). Every text is drawn as plain text; a link asks before it opens and
/// shows where it goes; a press goes to the server, which checks that the
/// person may press it, and the app then waits a few seconds for the bot to
/// answer.
///
/// [targetId] is the message (or the bot's private reply) the components are
/// on.
class MessageComponentsView extends ConsumerStatefulWidget {
  const MessageComponentsView({
    required this.components,
    required this.targetId,
    this.botName = '',
    super.key,
  });

  final MessageComponents components;
  final String targetId;

  /// Shown in "Sent to {bot}".
  final String botName;

  @override
  ConsumerState<MessageComponentsView> createState() =>
      _MessageComponentsViewState();
}

enum _NoteKind { waiting, done, problem }

class _Note {
  const _Note(this.kind, this.text);

  final _NoteKind kind;
  final String text;
}

class _MessageComponentsViewState extends ConsumerState<MessageComponentsView> {
  final _busy = <String>{};
  _Note? _note;
  var _generation = 0;

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _send(String componentId, Object? values) async {
    if (_busy.contains(componentId)) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy.add(componentId);
      _note = null;
    });
    final repository = ref.read(interactionsRepositoryProvider);
    final wait = ref.read(interactionWaitProvider);
    try {
      final receipt = await repository.submit(
        messageId: widget.targetId,
        componentId: componentId,
        values: values,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      final bot = receipt.botName.isEmpty ? widget.botName : receipt.botName;
      setState(() {
        _busy.remove(componentId);
        _note = _Note(
          _NoteKind.waiting,
          bot.isEmpty
              ? tr('Sent. Waiting for the bot…')
              : tr('Sent to {bot}. Waiting for an answer…', {'bot': bot}),
        );
      });
      unawaited(_watch(receipt, bot, generation, wait));
    } on InteractionException catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _busy.remove(componentId);
        _note = _Note(_NoteKind.problem, error.message);
      });
    } on Object {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _busy.remove(componentId);
        _note = _Note(
          _NoteKind.problem,
          tr('Could not reach the bot. Try again.'),
        );
      });
    }
  }

  /// Looks at the press until the bot answers or the time is up.
  Future<void> _watch(
    InteractionReceipt receipt,
    String bot,
    int generation,
    ({Duration limit, Duration every}) wait,
  ) async {
    final repository = ref.read(interactionsRepositoryProvider);
    var waited = Duration.zero;
    while (waited < wait.limit) {
      await Future<void>.delayed(wait.every);
      waited += wait.every;
      if (!mounted || generation != _generation) {
        return;
      }
      try {
        final status = await repository.status(receipt.interactionId);
        if (!mounted || generation != _generation) {
          return;
        }
        switch (status.state) {
          case InteractionState.answered:
            setState(() {
              _note = status.responseKind == 'ack'
                  ? _Note(_NoteKind.done, tr('Done.'))
                  : null;
            });
            return;
          case InteractionState.expired:
            _timedOut(bot);
            return;
          case InteractionState.pending:
            break;
        }
      } on Object {
        // Try again at the next look.
      }
    }
    if (mounted && generation == _generation) {
      _timedOut(bot);
    }
  }

  void _timedOut(String bot) {
    setState(() {
      _note = _Note(
        _NoteKind.problem,
        bot.isEmpty
            ? tr('The bot did not answer.')
            : tr('{bot} did not answer.', {'bot': bot}),
      );
    });
  }

  Future<void> _pressButton(ButtonComponent button) async {
    final modal = button.modal;
    if (modal == null) {
      await _send(button.id, null);
      return;
    }
    final answers = await showComponentFormSheet(context, modal);
    if (answers == null || !mounted) {
      return;
    }
    await _send(button.id, answers);
  }

  Future<void> _pickFrom(SelectComponent select) async {
    final chosen = await showComponentSelectSheet(context, select);
    if (chosen == null || !mounted) {
      return;
    }
    await _send(select.id, chosen);
  }

  Future<void> _openLink(LinkComponent link) async {
    final open = await showComponentLinkSheet(context, link.uri);
    if (open != true || !mounted) {
      return;
    }
    try {
      await ref.read(linkLauncherProvider)(context, link.uri);
    } on Object {
      // The system could not open it; nothing more to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final note = _note;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          key: const ValueKey('message-components'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in widget.components.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: row.first is SelectComponent
                    ? _SelectField(
                        select: row.first as SelectComponent,
                        busy: _busy.contains((row.first as SelectComponent).id),
                        onPressed: () =>
                            _pickFrom(row.first as SelectComponent),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final component in row)
                            switch (component) {
                              ButtonComponent() => ComponentButton(
                                key: ValueKey('component-${component.id}'),
                                label: component.label,
                                style: component.style,
                                busy: _busy.contains(component.id),
                                enabled: !component.disabled,
                                hint: component.modal == null
                                    ? null
                                    : tr('Opens a form'),
                                onPressed: () => _pressButton(component),
                              ),
                              LinkComponent() => ComponentButton(
                                key: ValueKey(
                                  'component-link-${component.uri}',
                                ),
                                label: component.label,
                                style: ComponentButtonStyle.secondary,
                                icon: Icons.open_in_new_rounded,
                                hint: tr('Opens a website'),
                                onPressed: () => _openLink(component),
                              ),
                              SelectComponent() => const SizedBox.shrink(),
                            },
                        ],
                      ),
              ),
            if (note != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  key: const ValueKey('component-status'),
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: switch (note.kind) {
                          _NoteKind.waiting => SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: c.muted,
                            ),
                          ),
                          _NoteKind.done => Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: c.successText,
                          ),
                          _NoteKind.problem => Icon(
                            Icons.error_outline_rounded,
                            size: 14,
                            color: c.dangerText,
                          ),
                        },
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          note.text,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: note.kind == _NoteKind.problem
                                ? c.dangerText
                                : c.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One button of a bot. Wraps long labels instead of cutting them.
class ComponentButton extends StatelessWidget {
  const ComponentButton({
    required this.label,
    required this.onPressed,
    this.style = ComponentButtonStyle.secondary,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.hint,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final ComponentButtonStyle style;
  final IconData? icon;
  final bool busy;
  final bool enabled;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final (fill, foreground, border) = switch (style) {
      ComponentButtonStyle.primary => (c.accent, c.onAccent, c.accent),
      ComponentButtonStyle.secondary => (c.raised, c.ink, c.lineSoft),
      ComponentButtonStyle.danger => (c.raised, c.dangerText, c.danger),
    };
    final minHeight = WeCordCareTheme.maybeOf(context)?.buttonHeight ?? 40;
    return WeCordPressable(
      onPressed: enabled && !busy ? onPressed : null,
      semanticLabel: label,
      hint: hint,
      mergeSemantics: false,
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: WeCordMotion.quick,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight, minWidth: 64),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: hovered && enabled
                    ? Color.alphaBlend(
                        (tokens.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.06),
                        fill,
                      )
                    : fill,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                border: Border.all(color: border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy) ...[
                      SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else if (icon != null) ...[
                      Icon(icon, size: 16, color: foreground),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The closed drop-down list: the placeholder, or what was chosen first.
class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.select,
    required this.busy,
    required this.onPressed,
  });

  final SelectComponent select;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final defaults = select.defaults;
    final shown = defaults.isEmpty
        ? (select.placeholder ?? tr('Choose…'))
        : [
            for (final option in select.options)
              if (defaults.contains(option.value)) option.label,
          ].join(', ');
    final label = select.placeholder ?? tr('Choose…');
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 380),
      child: WeCordPressable(
        key: ValueKey('component-${select.id}'),
        onPressed: select.disabled || busy ? null : onPressed,
        semanticLabel: label,
        hint: tr('Opens a list'),
        mergeSemantics: false,
        excludeSemantics: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          return AnimatedOpacity(
            opacity: select.disabled ? 0.45 : 1,
            duration: WeCordMotion.quick,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: hovered ? c.raisedStrong : c.raised,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                border: Border.all(color: c.lineSoft),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        shown,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          color: defaults.isEmpty ? c.muted : c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    busy
                        ? SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.muted,
                            ),
                          )
                        : Icon(
                            Icons.expand_more_rounded,
                            size: 20,
                            color: c.muted,
                          ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------- sheets

/// The list of choices of a drop-down. Resolves to the chosen option values
/// (one for a single list, between min and max for a multiple one); null when
/// closed without choosing.
Future<List<String>?> showComponentSelectSheet(
  BuildContext context,
  SelectComponent select,
) {
  return showWeCordSheet<List<String>>(
    context,
    title: select.placeholder ?? tr('Choose…'),
    builder: (context, _) => _SelectSheet(select: select),
  );
}

class _SelectSheet extends StatefulWidget {
  const _SelectSheet({required this.select});

  final SelectComponent select;

  @override
  State<_SelectSheet> createState() => _SelectSheetState();
}

class _SelectSheetState extends State<_SelectSheet> {
  late final _chosen = <String>{...widget.select.defaults};

  bool get _enough => _chosen.length >= widget.select.minValues;

  void _toggle(SelectOption option) {
    final select = widget.select;
    if (!select.multiple) {
      Navigator.of(context).pop([option.value]);
      return;
    }
    setState(() {
      if (!_chosen.remove(option.value) && _chosen.length < select.maxValues) {
        _chosen.add(option.value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final select = widget.select;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              key: const ValueKey('component-options'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final option in select.options)
                  WeCordPressable(
                    key: ValueKey('component-option-${option.value}'),
                    onPressed: () => _toggle(option),
                    semanticLabel: option.description == null
                        ? option.label
                        : '${option.label}, ${option.description}',
                    selected: _chosen.contains(option.value),
                    mergeSemantics: false,
                    excludeSemantics: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                    ),
                    builder: (context, states) => Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: states.contains(WidgetState.hovered)
                            ? c.raised
                            : null,
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.label,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.25,
                                    fontWeight: FontWeight.w600,
                                    color: c.ink,
                                  ),
                                ),
                                if (option.description case final text?)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.25,
                                        color: c.muted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (select.multiple || _chosen.contains(option.value))
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Icon(
                                select.multiple
                                    ? (_chosen.contains(option.value)
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank)
                                    : Icons.check_rounded,
                                size: 22,
                                color: _chosen.contains(option.value)
                                    ? c.accent
                                    : c.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (select.multiple)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: WeCordButton(
                key: const ValueKey('component-options-send'),
                label: tr('Send'),
                variant: WeCordButtonVariant.accent,
                expand: true,
                onPressed: _enough
                    ? () => Navigator.of(context).pop(_chosen.toList())
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// The form a button opens. Resolves to the answers by field id; null when
/// closed without sending.
Future<Map<String, String>?> showComponentFormSheet(
  BuildContext context,
  ComponentModal modal,
) {
  return showWeCordSheet<Map<String, String>>(
    context,
    title: modal.title,
    builder: (context, _) => _FormSheet(modal: modal),
  );
}

class _FormSheet extends StatefulWidget {
  const _FormSheet({required this.modal});

  final ComponentModal modal;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final _controllers = {
    for (final field in widget.modal.fields) field.id: TextEditingController(),
  };
  var _tried = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _complete => [
    for (final field in widget.modal.fields)
      if (field.required) _controllers[field.id]!.text.trim().isNotEmpty,
  ].every((filled) => filled);

  void _send() {
    if (!_complete) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop({
      for (final field in widget.modal.fields)
        field.id: _controllers[field.id]!.text.trim(),
    });
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
              for (final field in widget.modal.fields) ...[
                WeCordTextField(
                  fieldKey: ValueKey('component-field-${field.id}'),
                  controller: _controllers[field.id],
                  label: field.required
                      ? field.label
                      : tr('{label} (optional)', {'label': field.label}),
                  hint: field.placeholder,
                  maxLength: field.maxLength,
                  maxLines: field.paragraph ? 5 : 1,
                  minLines: field.paragraph ? 3 : null,
                  keyboardType: field.paragraph
                      ? TextInputType.multiline
                      : TextInputType.text,
                  errorText:
                      _tried &&
                          field.required &&
                          _controllers[field.id]!.text.trim().isEmpty
                      ? tr('This field is required.')
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                tr('This goes to the bot, which can read it.'),
                style: TextStyle(fontSize: 12.5, height: 1.3, color: c.muted),
              ),
              const SizedBox(height: 12),
              WeCordButton(
                key: const ValueKey('component-form-send'),
                label: tr('Send'),
                variant: WeCordButtonVariant.accent,
                expand: true,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before a bot's link button opens a website, showing where it goes.
/// Resolves to true to open it.
Future<bool?> showComponentLinkSheet(BuildContext context, Uri uri) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Open this link?'),
    builder: (context, _) {
      final c = context.tokens.colors;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('A bot added this button. It goes to:'),
                style: TextStyle(fontSize: 14, height: 1.3, color: c.muted),
              ),
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('component-link-target'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uri.host,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      uri.toString(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              WeCordButton(
                key: const ValueKey('component-link-open'),
                label: tr('Open'),
                variant: WeCordButtonVariant.accent,
                expand: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              WeCordButton(
                label: tr('Cancel'),
                variant: WeCordButtonVariant.secondary,
                expand: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
}
