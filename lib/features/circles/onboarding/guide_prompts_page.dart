import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart'
    show circleDetailProvider;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/guide_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the questions; true when the member saved their answers.
Future<bool> openGuidePrompts(
  BuildContext context, {
  required String circleId,
  required String circleName,
  required CircleGuide guide,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (context) => GuidePromptsPage(
        circleId: circleId,
        circleName: circleName,
        guide: guide,
      ),
    ),
  );
  return saved ?? false;
}

/// "What are you into?": the circle's questions. The answers give the
/// member roles (and so the channels those roles open), shown under each
/// option before they pick it. They can come back and change them.
class GuidePromptsPage extends ConsumerStatefulWidget {
  const GuidePromptsPage({
    required this.circleId,
    required this.circleName,
    required this.guide,
    super.key,
  });

  final String circleId;
  final String circleName;
  final CircleGuide guide;

  @override
  ConsumerState<GuidePromptsPage> createState() => _GuidePromptsPageState();
}

class _GuidePromptsPageState extends ConsumerState<GuidePromptsPage> {
  late final Set<String> _picked = {
    for (final prompt in widget.guide.prompts)
      for (final option in prompt.options)
        if (option.selected) option.id,
  };
  var _saving = false;
  String? _error;

  void _toggle(GuidePrompt prompt, GuideOption option) {
    setState(() {
      _error = null;
      if (_picked.contains(option.id)) {
        _picked.remove(option.id);
        return;
      }
      if (prompt.singleSelect) {
        _picked.removeAll([for (final other in prompt.options) other.id]);
      }
      _picked.add(option.id);
    });
  }

  bool get _missingRequired => widget.guide.prompts.any(
    (prompt) =>
        prompt.required &&
        !prompt.options.any((option) => _picked.contains(option.id)),
  );

  Future<void> _save() async {
    if (_missingRequired) {
      setState(() => _error = tr('Answer the questions marked Required.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ({List<String> added, List<String> removed}) result;
    try {
      result = await ref
          .read(circleGuideRepositoryProvider)
          .answer(widget.circleId, _picked);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save your answers. Try again.');
        });
      }
      return;
    }
    ref.invalidate(circleGuideProvider(widget.circleId));
    // Their roles changed: the circle reads them again.
    ref.invalidate(circleDetailProvider(widget.circleId));
    if (!mounted) {
      return;
    }
    if (result.added.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            tr('You now have: {roles}', {'roles': result.added.join(', ')}),
          ),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('About you'),
      subtitle: widget.circleName,
      actions: [
        WeCordButton(
          key: const ValueKey('guide-prompts-save'),
          label: tr('Done'),
          size: WeCordButtonSize.medium,
          loading: _saving,
          onPressed: _saving ? null : () => unawaited(_save()),
        ),
      ],
      body: ListView(
        padding: circlePagePadding(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
            child: Text(
              tr(
                'Tell {circle} what you are into. Your answers can give you '
                'roles and show you the channels that fit. You can change '
                'them any time.',
                {'circle': widget.circleName},
              ),
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
          ),
          if (_error case final error?)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.dangerSoft,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Text(
                error,
                key: const ValueKey('guide-prompts-error'),
                style: TextStyle(
                  color: c.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final prompt in widget.guide.prompts) ...[
            _PromptHeader(prompt: prompt),
            SettingsGroup(
              separatorIndent: 14,
              children: [
                for (final option in prompt.options)
                  _OptionRow(
                    prompt: prompt,
                    option: option,
                    picked: _picked.contains(option.id),
                    onTap: () => _toggle(prompt, option),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PromptHeader extends StatelessWidget {
  const _PromptHeader({required this.prompt});

  final GuidePrompt prompt;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final hint = [
      if (prompt.required) tr('Required'),
      prompt.singleSelect ? tr('Pick one') : tr('Pick any'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              prompt.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: prompt.required ? c.accentText : c.subtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.prompt,
    required this.option,
    required this.picked,
    required this.onTap,
  });

  final GuidePrompt prompt;
  final GuideOption option;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final effects = [
      if (option.roles.isNotEmpty)
        tr('Gives you: {roles}', {
          'roles': option.roles.map((role) => role.name).join(', '),
        }),
      if (option.channels.isNotEmpty)
        tr('Shows: {channels}', {
          'channels': option.channels.map((ch) => '#${ch.name}').join(', '),
        }),
    ];
    final label = option.emoji == null
        ? option.label
        : '${option.emoji} ${option.label}';
    return WeCordPressable(
      key: ValueKey('guide-option-${option.id}'),
      selected: picked,
      semanticLabel: [label, ...effects].join('. '),
      excludeSemantics: true,
      onPressed: onTap,
      builder: (context, states) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: prompt.singleSelect
                      ? BoxShape.circle
                      : BoxShape.rectangle,
                  borderRadius: prompt.singleSelect
                      ? null
                      : BorderRadius.circular(6),
                  color: picked ? c.accent : Colors.transparent,
                  border: Border.all(
                    color: picked ? c.accent : c.track,
                    width: 2,
                  ),
                ),
                child: picked
                    ? Icon(Icons.check_rounded, size: 14, color: c.onAccent)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  for (final effect in effects)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        effect,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: c.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
