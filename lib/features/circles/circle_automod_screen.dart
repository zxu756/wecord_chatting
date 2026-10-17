import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_automod_repository.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleAutoModScreen(BuildContext context, CircleDetail detail) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleAutoModScreen(detail: detail),
    ),
  );
}

/// A circle's AutoMod rules by kind, each with a switch, and buttons to
/// add more.
class CircleAutoModScreen extends ConsumerWidget {
  const CircleAutoModScreen({required this.detail, super.key});

  final CircleDetail detail;

  String get _circleId => detail.circle.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(circleAutoModRulesProvider(_circleId));
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('AutoMod'),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: CircleIcons.autoMod,
          title: tr('Could not load AutoMod rules.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () =>
                ref.invalidate(circleAutoModRulesProvider(_circleId)),
          ),
        ),
        data: (rules) => ListView(
          padding: circlePagePadding(context),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Text(
                tr(
                  'AutoMod checks messages as they are sent in this '
                  "circle's channels. Members who can manage the circle "
                  'are never checked.',
                ),
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
              ),
            ),
            for (final kind in AutoModRuleKind.values)
              _KindSection(
                kind: kind,
                rules: [
                  for (final rule in rules)
                    if (rule.kind == kind) rule,
                ],
                detail: detail,
              ),
          ],
        ),
      ),
    );
  }
}

String autoModKindTitle(AutoModRuleKind kind) => switch (kind) {
  AutoModRuleKind.keyword => tr('Custom keywords'),
  AutoModRuleKind.mentionSpam => tr('Mention spam'),
  AutoModRuleKind.spam => tr('Spam'),
};

String _kindDescription(AutoModRuleKind kind) => switch (kind) {
  AutoModRuleKind.keyword => tr(
    'Block words, phrases and patterns you choose.',
  ),
  AutoModRuleKind.mentionSpam => tr(
    'Block messages that mention too many people or roles at once.',
  ),
  AutoModRuleKind.spam => tr(
    'Block members who send too many messages too quickly.',
  ),
};

IconData _kindIcon(AutoModRuleKind kind) => switch (kind) {
  AutoModRuleKind.keyword => Icons.text_fields,
  AutoModRuleKind.mentionSpam => Icons.alternate_email,
  AutoModRuleKind.spam => Icons.speed,
};

/// "3 keywords, 1 pattern · Block, alert, time out".
String autoModRuleSummary(AutoModRule rule) {
  final what = switch (rule.kind) {
    AutoModRuleKind.keyword => [
      if (rule.keywords.isNotEmpty)
        tr('{count} keywords', {'count': rule.keywords.length}),
      if (rule.regexPatterns.isNotEmpty)
        tr('{count} patterns', {'count': rule.regexPatterns.length}),
    ].join(', '),
    AutoModRuleKind.mentionSpam => tr('More than {count} mentions', {
      'count': rule.mentionLimit ?? 0,
    }),
    AutoModRuleKind.spam => tr('More than {count} messages in {seconds}s', {
      'count': rule.messageLimit ?? 0,
      'seconds': rule.windowSeconds ?? 0,
    }),
  };
  final actions = [
    if (rule.blockMessage) tr('Block message'),
    if (rule.alertChannelId != null) tr('Send alert'),
    if (rule.timeoutSeconds != null) tr('Time out member'),
  ].join(', ');
  return actions.isEmpty ? what : '$what · $actions';
}

SettingsTone _kindTone(AutoModRuleKind kind) => switch (kind) {
  AutoModRuleKind.keyword => SettingsTone.accent,
  AutoModRuleKind.mentionSpam => SettingsTone.warning,
  AutoModRuleKind.spam => SettingsTone.danger,
};

class _KindSection extends ConsumerWidget {
  const _KindSection({
    required this.kind,
    required this.rules,
    required this.detail,
  });

  final AutoModRuleKind kind;
  final List<AutoModRule> rules;
  final CircleDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdd = rules.length < kind.maxPerCircle;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SettingsGroup(
        children: [
          SettingsRow(
            icon: _kindIcon(kind),
            tone: _kindTone(kind),
            title: autoModKindTitle(kind),
            subtitle: _kindDescription(kind),
          ),
          for (final rule in rules)
            SettingsRow(
              key: ValueKey('automod-rule-${rule.id}'),
              title: rule.name,
              subtitle: autoModRuleSummary(rule),
              onTap: () => _openEditor(context, rule),
              trailing: WeCordSwitch(
                value: rule.enabled,
                semanticLabel: rule.name,
                onChanged: (enabled) =>
                    _setEnabled(context, ref, rule, enabled),
              ),
            ),
          if (canAdd)
            SettingsRow(
              key: ValueKey('automod-add-${kind.key}'),
              icon: Icons.add_rounded,
              tone: SettingsTone.accent,
              title: tr('Create rule'),
              showChevron: false,
              onTap: () => _openEditor(context, AutoModRule.draft(kind)),
            ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, AutoModRule rule) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AutoModRuleEditor(detail: detail, rule: rule),
      ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    AutoModRule rule,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(circleAutoModRepositoryProvider)
          .saveRule(
            circleId: detail.circle.id,
            rule: rule.copyWith(enabled: enabled),
          );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not save the rule. Try again.'))),
      );
    }
    ref.invalidate(circleAutoModRulesProvider(detail.circle.id));
  }
}

/// Creates or edits one rule: what it looks for, what it does, and who
/// and where it skips.
class AutoModRuleEditor extends ConsumerStatefulWidget {
  const AutoModRuleEditor({
    required this.detail,
    required this.rule,
    super.key,
  });

  final CircleDetail detail;
  final AutoModRule rule;

  @override
  ConsumerState<AutoModRuleEditor> createState() => _AutoModRuleEditorState();
}

class _AutoModRuleEditorState extends ConsumerState<AutoModRuleEditor> {
  late final _name = TextEditingController(text: widget.rule.name);
  late final _keywords = TextEditingController(
    text: widget.rule.keywords.join(', '),
  );
  late final _patterns = TextEditingController(
    text: widget.rule.regexPatterns.join('\n'),
  );
  late final _mentionLimit = TextEditingController(
    text: '${widget.rule.mentionLimit ?? 20}',
  );
  late final _messageLimit = TextEditingController(
    text: '${widget.rule.messageLimit ?? 5}',
  );
  late final _windowSeconds = TextEditingController(
    text: '${widget.rule.windowSeconds ?? 5}',
  );
  late final _blockReason = TextEditingController(
    text: widget.rule.blockReason ?? '',
  );
  late var _block = widget.rule.blockMessage;
  late String? _alertChannelId = widget.rule.alertChannelId;
  late var _alert = widget.rule.alertChannelId != null;
  late int? _timeoutSeconds = widget.rule.timeoutSeconds;
  late final _exemptRoles = {...widget.rule.exemptRoleIds};
  late final _exemptChannels = {...widget.rule.exemptChannelIds};
  var _saving = false;
  String? _error;

  AutoModRuleKind get _kind => widget.rule.kind;

  bool get _isNew => widget.rule.id == null;

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _patterns.dispose();
    _mentionLimit.dispose();
    _messageLimit.dispose();
    _windowSeconds.dispose();
    _blockReason.dispose();
    super.dispose();
  }

  List<CircleChannel> get _alertChannels => [
    for (final channel in widget.detail.channels)
      if (!channel.isForum) channel,
  ];

  /// The rule as typed, or null after showing what is wrong.
  AutoModRule? _buildRule() {
    String? problem;
    final name = _name.text.trim();
    final keywords = parseAutoModKeywords(_keywords.text);
    final patterns = parseAutoModPatterns(_patterns.text);
    final mentionLimit = int.tryParse(_mentionLimit.text.trim());
    final messageLimit = int.tryParse(_messageLimit.text.trim());
    final windowSeconds = int.tryParse(_windowSeconds.text.trim());
    final alertChannelId = _alert ? _alertChannelId : null;
    if (name.isEmpty) {
      problem = tr('Give the rule a name.');
    } else if (_kind == AutoModRuleKind.keyword &&
        keywords.isEmpty &&
        patterns.isEmpty) {
      problem = tr('Add a keyword or a pattern.');
    } else if (_kind == AutoModRuleKind.keyword &&
        keywords.any(
          (keyword) =>
              keyword.length > AutoModLimits.keywordLength ||
              keyword.replaceAll('*', '').isEmpty,
        )) {
      problem = tr('Keywords are 1 to {count} characters besides *.', {
        'count': AutoModLimits.keywordLength,
      });
    } else if (keywords.length > AutoModLimits.keywords) {
      problem = tr('A rule holds up to {count} keywords.', {
        'count': AutoModLimits.keywords,
      });
    } else if (patterns.length > AutoModLimits.patterns ||
        patterns.any(
          (pattern) => pattern.length > AutoModLimits.patternLength,
        )) {
      problem = tr(
        'A rule holds up to {count} patterns of {length} characters.',
        {
          'count': AutoModLimits.patterns,
          'length': AutoModLimits.patternLength,
        },
      );
    } else if (_kind == AutoModRuleKind.mentionSpam &&
        (mentionLimit == null || mentionLimit < 1 || mentionLimit > 50)) {
      problem = tr('The mention limit is 1 to 50.');
    } else if (_kind == AutoModRuleKind.spam &&
        (messageLimit == null || messageLimit < 1 || messageLimit > 50)) {
      problem = tr('The message limit is 1 to 50.');
    } else if (_kind == AutoModRuleKind.spam &&
        (windowSeconds == null || windowSeconds < 1 || windowSeconds > 300)) {
      problem = tr('The time window is 1 to 300 seconds.');
    } else if (_alert && alertChannelId == null) {
      problem = tr('Choose a channel for alerts.');
    } else if (!_block && alertChannelId == null && _timeoutSeconds == null) {
      problem = tr('Choose at least one action.');
    }
    if (problem != null) {
      setState(() => _error = problem);
      return null;
    }
    final reason = _blockReason.text.trim();
    return AutoModRule(
      id: widget.rule.id,
      name: name,
      kind: _kind,
      enabled: widget.rule.enabled,
      keywords: _kind == AutoModRuleKind.keyword ? keywords : const [],
      regexPatterns: _kind == AutoModRuleKind.keyword ? patterns : const [],
      mentionLimit: _kind == AutoModRuleKind.mentionSpam ? mentionLimit : null,
      messageLimit: _kind == AutoModRuleKind.spam ? messageLimit : null,
      windowSeconds: _kind == AutoModRuleKind.spam ? windowSeconds : null,
      blockMessage: _block,
      blockReason: _block && reason.isNotEmpty ? reason : null,
      alertChannelId: alertChannelId,
      timeoutSeconds: _timeoutSeconds,
      exemptRoleIds: [
        for (final role in widget.detail.roles)
          if (_exemptRoles.contains(role.id)) role.id,
      ],
      exemptChannelIds: [
        for (final channel in widget.detail.channels)
          if (_exemptChannels.contains(channel.id)) channel.id,
      ],
    );
  }

  Future<void> _save() async {
    final rule = _buildRule();
    if (rule == null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(circleAutoModRepositoryProvider)
          .saveRule(circleId: widget.detail.circle.id, rule: rule);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _saveErrorText(error);
        });
      }
      return;
    }
    ref.invalidate(circleAutoModRulesProvider(widget.detail.circle.id));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _saveErrorText(Object error) {
    if (error is PostgrestException) {
      final pattern = RegExp(
        r'^Invalid pattern: (.*)$',
      ).firstMatch(error.message);
      if (pattern != null) {
        return tr('This pattern is not a valid regular expression: {pattern}', {
          'pattern': pattern.group(1),
        });
      }
      if (error.code == '54000') {
        return tr('This circle has as many rules of this kind as it can.');
      }
    }
    return tr('Could not save the rule. Try again.');
  }

  Future<void> _delete() async {
    final id = widget.rule.id;
    if (id == null) {
      return;
    }
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete rule'),
      message: tr('Delete {name}? AutoMod stops checking for it.', {
        'name': widget.rule.name,
      }),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(circleAutoModRepositoryProvider).deleteRule(id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not delete the rule. Try again.');
        });
      }
      return;
    }
    ref.invalidate(circleAutoModRulesProvider(widget.detail.circle.id));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _chooseAlertChannel() async {
    final channelId = await showCircleActionMenu<String>(
      context,
      title: tr('Alert channel'),
      items: [
        for (final channel in _alertChannels)
          CircleMenuItem(
            value: channel.id,
            icon: channel.id == _alertChannelId
                ? Icons.check_rounded
                : Icons.tag,
            tone: channel.id == _alertChannelId
                ? SettingsTone.accent
                : SettingsTone.neutral,
            label: '#${channel.name}',
          ),
      ],
    );
    if (channelId != null && mounted) {
      setState(() => _alertChannelId = channelId);
    }
  }

  List<(String, int)> get _durationOptions => [
    for (final (label, duration) in circleTimeoutDurations)
      (tr(label), duration.inSeconds),
    if (_timeoutSeconds case final seconds?
        when !circleTimeoutDurations.any(
          (option) => option.$2.inSeconds == seconds,
        ))
      (tr('{count} seconds', {'count': seconds}), seconds),
  ];

  Future<void> _chooseDuration() async {
    final seconds = await showCircleActionMenu<int>(
      context,
      title: tr('Duration'),
      items: [
        for (final (label, value) in _durationOptions)
          CircleMenuItem(
            value: value,
            icon: value == _timeoutSeconds
                ? Icons.check_rounded
                : Icons.timer_outlined,
            tone: value == _timeoutSeconds
                ? SettingsTone.accent
                : SettingsTone.neutral,
            label: label,
          ),
      ],
    );
    if (seconds != null && mounted) {
      setState(() => _timeoutSeconds = seconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final numbers = [FilteringTextInputFormatter.digitsOnly];
    String? alertChannelName;
    for (final channel in _alertChannels) {
      if (channel.id == _alertChannelId) {
        alertChannelName = '#${channel.name}';
      }
    }
    String? durationLabel;
    for (final (label, value) in _durationOptions) {
      if (value == _timeoutSeconds) {
        durationLabel = label;
      }
    }
    return CirclePageScaffold(
      title: _isNew ? tr('Create rule') : tr('Edit rule'),
      actions: [
        if (!_isNew)
          WeCordIconButton(
            tooltip: tr('Delete rule'),
            icon: Icons.delete_outline,
            variant: WeCordButtonVariant.ghost,
            onPressed: _saving ? null : _delete,
          ),
        const SizedBox(width: 4),
        WeCordButton(
          key: const ValueKey('automod-save'),
          label: tr('Save'),
          size: WeCordButtonSize.medium,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      body: ListView(
        padding: circlePagePadding(context),
        children: [
          // Shown on top, where it is seen after tapping Save.
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
                key: const ValueKey('automod-error'),
                style: TextStyle(
                  color: c.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SettingsSectionHeader(autoModKindTitle(_kind)),
          CircleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeCordTextField(
                  fieldKey: const ValueKey('automod-name'),
                  controller: _name,
                  maxLength: AutoModLimits.nameLength,
                  label: tr('Rule name'),
                ),
                const SizedBox(height: 8),
                ..._triggerFields(numbers),
              ],
            ),
          ),
          SettingsSectionHeader(tr('Actions')),
          SettingsGroup(
            separatorIndent: 14,
            children: [
              SettingsRow.toggle(
                key: const ValueKey('automod-block'),
                title: tr('Block message'),
                subtitle: tr('Keep the message from being sent.'),
                value: _block,
                onChanged: (value) => setState(() => _block = value),
              ),
              if (_block)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: WeCordTextField(
                    fieldKey: const ValueKey('automod-reason'),
                    controller: _blockReason,
                    maxLength: AutoModLimits.blockReasonLength,
                    label: tr('Custom message (optional)'),
                    helperText: tr(
                      'Shown to members when their message is blocked.',
                    ),
                  ),
                ),
              SettingsRow.toggle(
                key: const ValueKey('automod-alert'),
                title: tr('Send alert'),
                subtitle: tr(
                  'Post who sent what, and where, in a channel you choose.',
                ),
                value: _alert,
                onChanged: (value) => setState(() => _alert = value),
              ),
              if (_alert)
                SettingsRow(
                  key: const ValueKey('automod-alert-channel'),
                  icon: Icons.tag,
                  title: tr('Alert channel'),
                  value: alertChannelName,
                  onTap: _chooseAlertChannel,
                ),
              SettingsRow.toggle(
                key: const ValueKey('automod-timeout'),
                title: tr('Time out member'),
                subtitle: tr(
                  "They can still read, but can't send messages, react, "
                  'start threads or join voice until it ends.',
                ),
                value: _timeoutSeconds != null,
                onChanged: (value) => setState(
                  () => _timeoutSeconds = value
                      ? circleTimeoutDurations.first.$2.inSeconds
                      : null,
                ),
              ),
              if (_timeoutSeconds != null)
                SettingsRow(
                  key: const ValueKey('automod-timeout-duration'),
                  icon: Icons.timer_outlined,
                  title: tr('Duration'),
                  value: durationLabel,
                  onTap: _chooseDuration,
                ),
            ],
          ),
          SettingsSectionHeader(tr('Exempt roles')),
          CircleCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in widget.detail.roles)
                  WeCordChip(
                    label: role.isDefault ? '@everyone' : role.name,
                    selected: _exemptRoles.contains(role.id),
                    onPressed: () => setState(
                      () => _exemptRoles.contains(role.id)
                          ? _exemptRoles.remove(role.id)
                          : _exemptRoles.add(role.id),
                    ),
                  ),
              ],
            ),
          ),
          SettingsSectionHeader(tr('Exempt channels')),
          CircleCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final channel in widget.detail.channels)
                  WeCordChip(
                    label: '#${channel.name}',
                    selected: _exemptChannels.contains(channel.id),
                    onPressed: () => setState(
                      () => _exemptChannels.contains(channel.id)
                          ? _exemptChannels.remove(channel.id)
                          : _exemptChannels.add(channel.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _triggerFields(List<TextInputFormatter> numbers) {
    switch (_kind) {
      case AutoModRuleKind.keyword:
        return [
          WeCordTextField(
            fieldKey: const ValueKey('automod-keywords'),
            controller: _keywords,
            minLines: 2,
            maxLines: 6,
            label: tr('Keywords'),
            helperText: tr(
              'Separate with commas. Keywords match whole words; use * '
              'for parts of words: *cat matches wildcat, cat* matches '
              'catch, *cat* matches anywhere.',
            ),
          ),
          const SizedBox(height: 16),
          WeCordTextField(
            fieldKey: const ValueKey('automod-patterns'),
            controller: _patterns,
            minLines: 1,
            maxLines: 6,
            label: tr('Regex patterns (optional)'),
            helperText: tr(
              'One regular expression per line, up to {count}. Matching '
              'ignores case.',
              {'count': AutoModLimits.patterns},
            ),
          ),
        ];
      case AutoModRuleKind.mentionSpam:
        return [
          WeCordTextField(
            fieldKey: const ValueKey('automod-mention-limit'),
            controller: _mentionLimit,
            keyboardType: TextInputType.number,
            inputFormatters: numbers,
            label: tr('Unique mentions allowed per message'),
            helperText: tr(
              'Messages with more user and role mentions than this match.',
            ),
          ),
        ];
      case AutoModRuleKind.spam:
        return [
          WeCordTextField(
            fieldKey: const ValueKey('automod-message-limit'),
            controller: _messageLimit,
            keyboardType: TextInputType.number,
            inputFormatters: numbers,
            label: tr('Messages allowed'),
          ),
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('automod-window'),
            controller: _windowSeconds,
            keyboardType: TextInputType.number,
            inputFormatters: numbers,
            label: tr('Within seconds'),
            helperText: tr(
              "Sending more messages than this across the circle's "
              'channels in that time matches.',
            ),
          ),
        ];
    }
  }
}
