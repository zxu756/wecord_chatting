import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:wecord/features/circles/circle_automod_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Limits the server enforces (see `202610160021_member_onboarding.sql`).
abstract final class CircleOnboardingLimits {
  static const rules = 20;
  static const ruleLength = 300;
  static const welcomeLength = 2000;
}

/// A circle's rules and welcome message, as one member sees them.
class CircleOnboarding {
  const CircleOnboarding({
    this.enabled = false,
    this.rules = const [],
    this.welcomeMessage,
    this.needsAcceptance = false,
  });

  factory CircleOnboarding.fromJson(Map<String, dynamic> json) {
    final rules = json['rules'];
    return CircleOnboarding(
      enabled: json['enabled'] == true,
      rules: rules is List ? [for (final rule in rules) '$rule'] : const [],
      welcomeMessage: json['welcome_message'] as String?,
      needsAcceptance: json['needs_acceptance'] == true,
    );
  }

  /// New members must accept [rules] before taking part.
  final bool enabled;
  final List<String> rules;
  final String? welcomeMessage;

  /// The current member has yet to accept the rules.
  final bool needsAcceptance;
}

final circleOnboardingRepositoryProvider = Provider<CircleOnboardingRepository>(
  (ref) {
    try {
      return CircleOnboardingRepository(
        SupabaseRpcDataSource(ref.watch(supabaseClientProvider)),
      );
    } on ProviderException {
      return const CircleOnboardingRepository(UninitializedRpcDataSource());
    }
  },
);

/// The circle's onboarding for the current member.
final circleOnboardingProvider = FutureProvider.autoDispose
    .family<CircleOnboarding, String>((ref, circleId) {
      return ref.watch(circleOnboardingRepositoryProvider).load(circleId);
    });

class CircleOnboardingRepository {
  const CircleOnboardingRepository(this._dataSource);

  final RpcDataSource _dataSource;

  Future<CircleOnboarding> load(String circleId) async {
    final json = await _dataSource.rpc('get_circle_onboarding', {
      'target_circle_id': circleId,
    });
    return json is Map<String, dynamic>
        ? CircleOnboarding.fromJson(json)
        : const CircleOnboarding();
  }

  Future<void> save({
    required String circleId,
    required bool enabled,
    required List<String> rules,
    required String welcomeMessage,
  }) async {
    final welcome = welcomeMessage.trim();
    await _dataSource.rpc('set_circle_onboarding', {
      'target_circle_id': circleId,
      'is_enabled': enabled,
      'rule_list': [
        for (final rule in rules)
          if (rule.trim().isNotEmpty) rule.trim(),
      ],
      'welcome': welcome.isEmpty ? null : welcome,
    });
  }

  /// Accepts the rules; returns the welcome message, if there is one.
  Future<String?> acceptRules(String circleId) async {
    final json = await _dataSource.rpc('accept_circle_rules', {
      'target_circle_id': circleId,
    });
    if (json is Map<String, dynamic>) {
      final welcome = (json['welcome_message'] as String?)?.trim() ?? '';
      return welcome.isEmpty ? null : welcome;
    }
    return null;
  }
}

/// Shows [child] (the circle), with a bar asking to accept the circle's
/// rules while the current member has not. The rules open on their own
/// the first time.
class CircleOnboardingGate extends ConsumerStatefulWidget {
  const CircleOnboardingGate({
    required this.circleId,
    required this.circleName,
    required this.child,
    super.key,
  });

  final String circleId;
  final String circleName;
  final Widget child;

  @override
  ConsumerState<CircleOnboardingGate> createState() =>
      _CircleOnboardingGateState();
}

class _CircleOnboardingGateState extends ConsumerState<CircleOnboardingGate> {
  var _shownRules = false;

  @override
  Widget build(BuildContext context) {
    final onboarding = ref
        .watch(circleOnboardingProvider(widget.circleId))
        .value;
    final needsAcceptance = onboarding?.needsAcceptance ?? false;
    if (onboarding != null && needsAcceptance && !_shownRules) {
      _shownRules = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openRules(onboarding));
        }
      });
    }
    final c = context.tokens.colors;
    // The same shape with or without the bar, so the circle below keeps
    // its state when the bar goes away.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onboarding != null && needsAcceptance)
          Material(
            key: const ValueKey('circle-rules-bar'),
            color: c.accentSoft,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                child: Row(
                  children: [
                    Icon(Icons.rule, size: 20, color: c.accentText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr(
                          'Read and accept the rules of {circle} to start '
                          'chatting.',
                          {'circle': widget.circleName},
                        ),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.accentText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    WeCordButton(
                      label: tr('Read rules'),
                      variant: WeCordButtonVariant.accent,
                      size: WeCordButtonSize.small,
                      onPressed: () => _openRules(onboarding),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: needsAcceptance,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  Future<void> _openRules(CircleOnboarding onboarding) async {
    final accepted = await showCircleDialog<bool>(
      context,
      builder: (context) => CircleRulesDialog(
        circleName: widget.circleName,
        rules: onboarding.rules,
      ),
    );
    if (accepted != true || !mounted) {
      return;
    }
    final String? welcome;
    try {
      welcome = await ref
          .read(circleOnboardingRepositoryProvider)
          .acceptRules(widget.circleId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not accept the rules. Try again.'))),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(circleOnboardingProvider(widget.circleId));
    await showCircleDialog<void>(
      context,
      builder: (context) =>
          CircleWelcomeDialog(circleName: widget.circleName, message: welcome),
    );
  }
}

/// The circle's rules, numbered, with a box to tick before accepting.
class CircleRulesDialog extends StatefulWidget {
  const CircleRulesDialog({
    required this.circleName,
    required this.rules,
    super.key,
  });

  final String circleName;
  final List<String> rules;

  @override
  State<CircleRulesDialog> createState() => _CircleRulesDialogState();
}

class _CircleRulesDialogState extends State<CircleRulesDialog> {
  var _agreed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleDialog(
      title: tr('Rules of {circle}', {'circle': widget.circleName}),
      message: tr('Accept these rules to send messages, react and join voice.'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, rule) in widget.rules.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.accentText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              rule,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: c.ink,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          WeCordPressable(
            key: const ValueKey('circle-rules-agree'),
            toggled: _agreed,
            pressedScale: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            onPressed: () {
              WeCordHaptics.selection();
              setState(() => _agreed = !_agreed);
            },
            builder: (context, states) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: WeCordMotion.quick,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _agreed ? c.accent : c.raised,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _agreed
                        ? Icon(Icons.check_rounded, size: 18, color: c.onAccent)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr('I have read and agree to the rules'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Not now'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('circle-rules-accept'),
          label: tr('Accept'),
          onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}

/// Shown once, right after accepting the rules.
class CircleWelcomeDialog extends StatelessWidget {
  const CircleWelcomeDialog({
    required this.circleName,
    this.message,
    super.key,
  });

  final String circleName;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Welcome to {circle}!', {'circle': circleName}),
      message:
          message ?? tr('You can now send messages, react and join voice.'),
      actions: [
        CircleDialogAction.primary(
          key: const ValueKey('circle-welcome-done'),
          label: tr("Let's go"),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

void openCircleOnboardingSettings(BuildContext context, CircleDetail detail) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleOnboardingSettingsScreen(detail: detail),
    ),
  );
}

/// Circle settings → Onboarding: whether new members must accept the
/// rules, the rules, and the welcome message.
class CircleOnboardingSettingsScreen extends ConsumerWidget {
  const CircleOnboardingSettingsScreen({required this.detail, super.key});

  final CircleDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(circleOnboardingProvider(detail.circle.id));
    return onboarding.when(
      loading: () => CirclePageScaffold(
        title: tr('Onboarding'),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => CirclePageScaffold(
        title: tr('Onboarding'),
        body: CircleEmptyState(
          icon: Icons.rule,
          title: tr('Could not load onboarding.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () =>
                ref.invalidate(circleOnboardingProvider(detail.circle.id)),
          ),
        ),
      ),
      data: (onboarding) =>
          _OnboardingEditor(circleId: detail.circle.id, initial: onboarding),
    );
  }
}

class _OnboardingEditor extends ConsumerStatefulWidget {
  const _OnboardingEditor({required this.circleId, required this.initial});

  final String circleId;
  final CircleOnboarding initial;

  @override
  ConsumerState<_OnboardingEditor> createState() => _OnboardingEditorState();
}

class _OnboardingEditorState extends ConsumerState<_OnboardingEditor> {
  late var _enabled = widget.initial.enabled;
  late final _rules = [
    for (final rule in widget.initial.rules) TextEditingController(text: rule),
    if (widget.initial.rules.isEmpty) TextEditingController(),
  ];
  late final _welcome = TextEditingController(
    text: widget.initial.welcomeMessage ?? '',
  );
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _rules) {
      controller.dispose();
    }
    _welcome.dispose();
    super.dispose();
  }

  List<String> get _ruleTexts => [
    for (final controller in _rules)
      if (controller.text.trim().isNotEmpty) controller.text.trim(),
  ];

  Future<void> _save() async {
    if (_enabled && _ruleTexts.isEmpty) {
      setState(() => _error = tr('Add at least one rule first.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(circleOnboardingRepositoryProvider)
          .save(
            circleId: widget.circleId,
            enabled: _enabled,
            rules: _ruleTexts,
            welcomeMessage: _welcome.text,
          );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save onboarding. Try again.');
        });
      }
      return;
    }
    ref.invalidate(circleOnboardingProvider(widget.circleId));
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(tr('Onboarding saved.'))));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('Onboarding'),
      actions: [
        WeCordButton(
          key: const ValueKey('onboarding-save'),
          label: tr('Save'),
          size: WeCordButtonSize.medium,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      body: ListView(
        padding: circlePagePadding(context),
        children: [
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
                key: const ValueKey('onboarding-error'),
                style: TextStyle(
                  color: c.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SettingsGroup(
            children: [
              SettingsRow.toggle(
                key: const ValueKey('onboarding-enabled'),
                icon: Icons.rule,
                tone: SettingsTone.success,
                title: tr('Members must accept the rules'),
                subtitle: tr(
                  'New members can read channels, but cannot send '
                  'messages, react or join voice until they accept. '
                  'Everyone already here counts as having accepted.',
                ),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
          SettingsSectionHeader(tr('Rules')),
          CircleCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, controller) in _rules.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.accentText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: WeCordTextField(
                            fieldKey: ValueKey('onboarding-rule-$index'),
                            controller: controller,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(
                                CircleOnboardingLimits.ruleLength,
                              ),
                            ],
                            minLines: 1,
                            maxLines: 3,
                            hint: tr('Rule {number}', {'number': index + 1}),
                          ),
                        ),
                        WeCordIconButton(
                          tooltip: tr('Remove rule'),
                          icon: Icons.remove_circle_outline,
                          variant: WeCordButtonVariant.ghost,
                          onPressed: () => setState(() {
                            _rules.removeAt(index).dispose();
                          }),
                        ),
                      ],
                    ),
                  ),
                if (_rules.length < CircleOnboardingLimits.rules)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: WeCordButton(
                      key: const ValueKey('onboarding-add-rule'),
                      label: tr('Add rule'),
                      icon: Icons.add_rounded,
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      onPressed: () =>
                          setState(() => _rules.add(TextEditingController())),
                    ),
                  ),
              ],
            ),
          ),
          SettingsSectionHeader(tr('Welcome message')),
          CircleCard(
            child: WeCordTextField(
              fieldKey: const ValueKey('onboarding-welcome'),
              controller: _welcome,
              maxLength: CircleOnboardingLimits.welcomeLength,
              minLines: 2,
              maxLines: 6,
              hint: tr('Shown once to members after they accept the rules.'),
            ),
          ),
        ],
      ),
    );
  }
}
