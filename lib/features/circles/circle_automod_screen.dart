import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_automod_repository.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('AutoMod'))),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Could not load AutoMod rules.')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(circleAutoModRulesProvider(_circleId)),
                  child: Text(tr('Try again')),
                ),
              ],
            ),
          ),
        ),
        data: (rules) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                tr(
                  'AutoMod checks messages as they are sent in this '
                  "circle's channels. Members who can manage the circle "
                  'are never checked.',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
    final theme = Theme.of(context);
    final canAdd = rules.length < kind.maxPerCircle;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(_kindIcon(kind)),
            title: Text(
              autoModKindTitle(kind),
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(_kindDescription(kind)),
          ),
          for (final rule in rules)
            ListTile(
              key: ValueKey('automod-rule-${rule.id}'),
              contentPadding: const EdgeInsets.only(left: 72, right: 8),
              title: Text(rule.name),
              subtitle: Text(autoModRuleSummary(rule)),
              onTap: () => _openEditor(context, rule),
              trailing: Switch(
                value: rule.enabled,
                onChanged: (enabled) =>
                    _setEnabled(context, ref, rule, enabled),
              ),
            ),
          if (canAdd)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: ValueKey('automod-add-${kind.key}'),
                  onPressed: () =>
                      _openEditor(context, AutoModRule.draft(kind)),
                  icon: const Icon(Icons.add),
                  label: Text(tr('Create rule')),
                ),
              ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete rule')),
        content: Text(
          tr('Delete {name}? AutoMod stops checking for it.', {
            'name': widget.rule.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numbers = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? tr('Create rule') : tr('Edit rule')),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: tr('Delete rule'),
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const ValueKey('automod-save'),
              onPressed: _saving ? null : _save,
              child: Text(tr('Save')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Shown on top, where it is seen after tapping Save.
          if (_error case final error?) ...[
            Text(
              error,
              key: const ValueKey('automod-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            autoModKindTitle(_kind),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('automod-name'),
            controller: _name,
            maxLength: AutoModLimits.nameLength,
            decoration: InputDecoration(labelText: tr('Rule name')),
          ),
          const SizedBox(height: 8),
          ..._triggerFields(numbers),
          const Divider(height: 32),
          Text(tr('Actions'), style: theme.textTheme.titleMedium),
          SwitchListTile(
            key: const ValueKey('automod-block'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Block message')),
            subtitle: Text(tr('Keep the message from being sent.')),
            value: _block,
            onChanged: (value) => setState(() => _block = value),
          ),
          if (_block)
            TextField(
              key: const ValueKey('automod-reason'),
              controller: _blockReason,
              maxLength: AutoModLimits.blockReasonLength,
              decoration: InputDecoration(
                labelText: tr('Custom message (optional)'),
                helperText: tr(
                  'Shown to members when their message is blocked.',
                ),
              ),
            ),
          SwitchListTile(
            key: const ValueKey('automod-alert'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Send alert')),
            subtitle: Text(
              tr('Post who sent what, and where, in a channel you choose.'),
            ),
            value: _alert,
            onChanged: (value) => setState(() => _alert = value),
          ),
          if (_alert)
            DropdownButtonFormField<String>(
              key: const ValueKey('automod-alert-channel'),
              initialValue:
                  _alertChannels.any((channel) => channel.id == _alertChannelId)
                  ? _alertChannelId
                  : null,
              decoration: InputDecoration(labelText: tr('Alert channel')),
              items: [
                for (final channel in _alertChannels)
                  DropdownMenuItem(
                    value: channel.id,
                    child: Text('#${channel.name}'),
                  ),
              ],
              onChanged: (value) => setState(() => _alertChannelId = value),
            ),
          SwitchListTile(
            key: const ValueKey('automod-timeout'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Time out member')),
            subtitle: Text(
              tr(
                "They can still read, but can't send messages, react, start "
                'threads or join voice until it ends.',
              ),
            ),
            value: _timeoutSeconds != null,
            onChanged: (value) => setState(
              () => _timeoutSeconds = value
                  ? circleTimeoutDurations.first.$2.inSeconds
                  : null,
            ),
          ),
          if (_timeoutSeconds != null)
            DropdownButtonFormField<int>(
              key: const ValueKey('automod-timeout-duration'),
              initialValue: _timeoutSeconds,
              decoration: InputDecoration(labelText: tr('Duration')),
              items: [
                for (final (label, duration) in circleTimeoutDurations)
                  DropdownMenuItem(
                    value: duration.inSeconds,
                    child: Text(tr(label)),
                  ),
                if (!circleTimeoutDurations.any(
                  (option) => option.$2.inSeconds == _timeoutSeconds,
                ))
                  DropdownMenuItem(
                    value: _timeoutSeconds,
                    child: Text(
                      tr('{count} seconds', {'count': _timeoutSeconds}),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _timeoutSeconds = value),
            ),
          const Divider(height: 32),
          Text(tr('Exempt roles'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in widget.detail.roles)
                FilterChip(
                  label: Text(role.isDefault ? '@everyone' : role.name),
                  selected: _exemptRoles.contains(role.id),
                  onSelected: (selected) => setState(
                    () => selected
                        ? _exemptRoles.add(role.id)
                        : _exemptRoles.remove(role.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(tr('Exempt channels'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final channel in widget.detail.channels)
                FilterChip(
                  label: Text('#${channel.name}'),
                  selected: _exemptChannels.contains(channel.id),
                  onSelected: (selected) => setState(
                    () => selected
                        ? _exemptChannels.add(channel.id)
                        : _exemptChannels.remove(channel.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _triggerFields(List<TextInputFormatter> numbers) {
    switch (_kind) {
      case AutoModRuleKind.keyword:
        return [
          TextField(
            key: const ValueKey('automod-keywords'),
            controller: _keywords,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: tr('Keywords'),
              helperText: tr(
                'Separate with commas. Keywords match whole words; use * '
                'for parts of words: *cat matches wildcat, cat* matches '
                'catch, *cat* matches anywhere.',
              ),
              helperMaxLines: 4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('automod-patterns'),
            controller: _patterns,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: tr('Regex patterns (optional)'),
              helperText: tr(
                'One regular expression per line, up to {count}. Matching '
                'ignores case.',
                {'count': AutoModLimits.patterns},
              ),
              helperMaxLines: 3,
            ),
          ),
        ];
      case AutoModRuleKind.mentionSpam:
        return [
          TextField(
            key: const ValueKey('automod-mention-limit'),
            controller: _mentionLimit,
            keyboardType: TextInputType.number,
            inputFormatters: numbers,
            decoration: InputDecoration(
              labelText: tr('Unique mentions allowed per message'),
              helperText: tr(
                'Messages with more user and role mentions than this match.',
              ),
            ),
          ),
        ];
      case AutoModRuleKind.spam:
        return [
          TextField(
            key: const ValueKey('automod-message-limit'),
            controller: _messageLimit,
            keyboardType: TextInputType.number,
            inputFormatters: numbers,
            decoration: InputDecoration(labelText: tr('Messages allowed')),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('automod-window'),
            controller: _windowSeconds,
            keyboardType: TextInputType.number,
            inputFormatters: numbers,
            decoration: InputDecoration(
              labelText: tr('Within seconds'),
              helperText: tr(
                "Sending more messages than this across the circle's "
                'channels in that time matches.',
              ),
            ),
          ),
        ];
    }
  }
}
