import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_automod_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

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
    } on AssertionError {
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
        .valueOrNull;
    final needsAcceptance = onboarding?.needsAcceptance ?? false;
    if (onboarding != null && needsAcceptance && !_shownRules) {
      _shownRules = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openRules(onboarding));
        }
      });
    }
    final colors = Theme.of(context).colorScheme;
    // The same shape with or without the bar, so the circle below keeps
    // its state when the bar goes away.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onboarding != null && needsAcceptance)
          Material(
            key: const ValueKey('circle-rules-bar'),
            color: colors.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.rule, color: colors.onSecondaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr(
                          'Read and accept the rules of {circle} to start '
                          'chatting.',
                          {'circle': widget.circleName},
                        ),
                        style: TextStyle(color: colors.onSecondaryContainer),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _openRules(onboarding),
                      child: Text(tr('Read rules')),
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
    final accepted = await showDialog<bool>(
      context: context,
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
    await showDialog<void>(
      context: context,
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
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Rules of {circle}', {'circle': widget.circleName})),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Accept these rules to send messages, react and join voice.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final (index, rule) in widget.rules.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(rule)),
                  ],
                ),
              ),
            CheckboxListTile(
              key: const ValueKey('circle-rules-agree'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              title: Text(tr('I have read and agree to the rules')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Not now')),
        ),
        FilledButton(
          key: const ValueKey('circle-rules-accept'),
          onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
          child: Text(tr('Accept')),
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
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.celebration_outlined, color: theme.colorScheme.primary),
      title: Text(tr('Welcome to {circle}!', {'circle': circleName})),
      content: Text(
        message ?? tr('You can now send messages, react and join voice.'),
        textAlign: TextAlign.center,
      ),
      actions: [
        FilledButton(
          key: const ValueKey('circle-welcome-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr("Let's go")),
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
      loading: () => Scaffold(
        appBar: AppBar(title: Text(tr('Onboarding'))),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(tr('Onboarding'))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Could not load onboarding.')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(circleOnboardingProvider(detail.circle.id)),
                child: Text(tr('Try again')),
              ),
            ],
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Onboarding')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const ValueKey('onboarding-save'),
              onPressed: _saving ? null : _save,
              child: Text(tr('Save')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error case final error?) ...[
            Text(
              error,
              key: const ValueKey('onboarding-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile(
            key: const ValueKey('onboarding-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Members must accept the rules')),
            subtitle: Text(
              tr(
                'New members can read channels, but cannot send messages, '
                'react or join voice until they accept. Everyone already '
                'here counts as having accepted.',
              ),
            ),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const Divider(height: 32),
          Text(tr('Rules'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (index, controller) in _rules.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('onboarding-rule-$index'),
                      controller: controller,
                      maxLength: CircleOnboardingLimits.ruleLength,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr('Rule {number}', {'number': index + 1}),
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Remove rule'),
                    onPressed: () => setState(() {
                      _rules.removeAt(index).dispose();
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
          if (_rules.length < CircleOnboardingLimits.rules)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('onboarding-add-rule'),
                onPressed: () =>
                    setState(() => _rules.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: Text(tr('Add rule')),
              ),
            ),
          const Divider(height: 32),
          Text(tr('Welcome message'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('onboarding-welcome'),
            controller: _welcome,
            maxLength: CircleOnboardingLimits.welcomeLength,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: tr(
                'Shown once to members after they accept the rules.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
