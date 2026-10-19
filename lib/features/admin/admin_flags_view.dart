import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_ops_models.dart';
import 'package:wecord/features/admin/admin_ops_repository.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The console's "Flags" tab (K4): the minimum version of each platform and
/// the feature flags. Everybody in the console can read it; only an owner
/// can change anything (the server checks too).
class AdminFlagsView extends ConsumerStatefulWidget {
  const AdminFlagsView({super.key});

  @override
  ConsumerState<AdminFlagsView> createState() => _AdminFlagsViewState();
}

class _AdminFlagsViewState extends ConsumerState<AdminFlagsView> {
  var _flags = <AdminFlag>[];
  var _minVersions = <String, String>{};
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(adminOpsRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.listFlags(),
        repository.minVersions(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _flags = results[0] as List<AdminFlag>;
        _minVersions = results[1] as Map<String, String>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editMinimum(String platform) async {
    final entered = await showCircleDialog<String>(
      context,
      builder: (context) => _MinimumDialog(
        platform: platform,
        current: _minVersions[platform] ?? '',
      ),
    );
    if (entered == null || !mounted) {
      return;
    }
    if (entered.isNotEmpty) {
      final sure = await confirmCircleAction(
        context,
        title: tr('Lock out older versions?'),
        message: tr(
          'People on a version older than {version} ({platform}) will only '
          'see the “Please update” page.',
          {'version': entered, 'platform': adminPlatformLabel(platform)},
        ),
        confirmLabel: tr('Set minimum'),
      );
      if (!sure || !mounted) {
        return;
      }
    }
    try {
      await ref
          .read(adminOpsRepositoryProvider)
          .setMinVersion(platform, entered);
      await _load();
    } catch (error) {
      if (mounted) {
        _say(adminErrorText(error));
      }
    }
  }

  Future<void> _editFlag(AdminFlag? flag) async {
    final result = await showCircleDialog<_FlagResult>(
      context,
      builder: (context) => _FlagDialog(flag: flag),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      final repository = ref.read(adminOpsRepositoryProvider);
      if (result.delete) {
        final sure = await confirmCircleAction(
          context,
          title: tr('Delete this flag?'),
          message: tr(
            'The app goes back to the default for “{key}” everywhere.',
            {'key': result.key},
          ),
          confirmLabel: tr('Delete flag'),
        );
        if (!sure) {
          return;
        }
        await repository.deleteFlag(result.key);
      } else {
        await repository.saveFlag(
          key: result.key,
          description: result.description,
          enabled: result.enabled,
          rolloutPercent: result.rolloutPercent,
          allowUsernames: result.allowUsernames,
          minVersion: result.minVersion,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        _say(adminErrorText(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final canEdit = ref.watch(adminRoleProvider).value == AdminRole.owner;
    if (_loading && _flags.isEmpty && _minVersions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _flags.isEmpty && _minVersions.isEmpty) {
      return CircleEmptyState(
        icon: Icons.error_outline_rounded,
        title: tr('Could not load the flags.'),
        message: adminErrorText(_error!),
        action: WeCordButton(
          label: tr('Retry'),
          variant: WeCordButtonVariant.onPaper,
          onPressed: _load,
        ),
      );
    }
    return ListView(
      key: const ValueKey('admin-flags-list'),
      padding: circlePagePadding(context),
      children: [
        _SectionTitle(
          title: tr('Minimum version'),
          caption: tr(
            'Apps older than this show a “Please update” page. Only an owner '
            'can change it.',
          ),
        ),
        SettingsGroup(
          children: [
            for (final platform in adminPlatforms)
              SettingsRow(
                key: ValueKey('admin-minver-$platform'),
                icon: Icons.system_update_alt_rounded,
                title: adminPlatformLabel(platform),
                value: (_minVersions[platform] ?? '').isEmpty
                    ? tr('No minimum')
                    : _minVersions[platform],
                onTap: canEdit ? () => unawaited(_editMinimum(platform)) : null,
                showChevron: canEdit,
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          title: tr('Feature flags'),
          caption: tr(
            'A flag decides what the app shows, never what is allowed.',
          ),
          trailing: canEdit
              ? WeCordButton(
                  key: const ValueKey('admin-flag-new'),
                  label: tr('New flag'),
                  size: WeCordButtonSize.small,
                  variant: WeCordButtonVariant.onPaper,
                  onPressed: () => unawaited(_editFlag(null)),
                )
              : null,
        ),
        if (_flags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              tr('No flags yet.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          )
        else
          for (final flag in _flags)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FlagTile(
                flag: flag,
                onTap: canEdit ? () => unawaited(_editFlag(flag)) : null,
              ),
            ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.caption, this.trailing});

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final caption = this.caption;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.flag, required this.onTap});

  final AdminFlag flag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tags = <Widget>[
      AdminStateTag(
        label: flag.enabled ? tr('On') : tr('Off'),
        tone: flag.enabled ? SettingsTone.success : SettingsTone.neutral,
      ),
      if (flag.enabled)
        AdminStateTag(
          label: tr('{percent}% of people', {'percent': flag.rolloutPercent}),
        ),
      if (flag.allowUsernames.isNotEmpty)
        AdminStateTag(
          label: tr('Allow list: {count}', {
            'count': flag.allowUsernames.length,
          }),
        ),
      if (flag.minVersion.isNotEmpty)
        AdminStateTag(
          label: tr('Needs {version}', {'version': flag.minVersion}),
        ),
    ];
    return WeCordPressable(
      key: ValueKey('admin-flag-${flag.key}'),
      onPressed: onTap,
      semanticLabel: flag.key,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flag.key,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (flag.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        flag.description,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: c.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: tags),
                  ],
                ),
              ),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: c.faint,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// What the flag dialog hands back.
class _FlagResult {
  const _FlagResult({
    required this.key,
    this.description = '',
    this.enabled = false,
    this.rolloutPercent = 0,
    this.allowUsernames = const [],
    this.minVersion = '',
    this.delete = false,
  });

  final String key;
  final String description;
  final bool enabled;
  final int rolloutPercent;
  final List<String> allowUsernames;
  final String minVersion;
  final bool delete;
}

class _FlagDialog extends StatefulWidget {
  const _FlagDialog({required this.flag});

  final AdminFlag? flag;

  @override
  State<_FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends State<_FlagDialog> {
  late final _key = TextEditingController(text: widget.flag?.key ?? '');
  late final _description = TextEditingController(
    text: widget.flag?.description ?? '',
  );
  late final _percent = TextEditingController(
    text: '${widget.flag?.rolloutPercent ?? 0}',
  );
  late final _allow = TextEditingController(
    text: widget.flag?.allowUsernames.join(' ') ?? '',
  );
  late final _version = TextEditingController(
    text: widget.flag?.minVersion ?? '',
  );
  late var _enabled = widget.flag?.enabled ?? false;

  @override
  void dispose() {
    _key.dispose();
    _description.dispose();
    _percent.dispose();
    _allow.dispose();
    _version.dispose();
    super.dispose();
  }

  int? get _percentValue {
    final value = int.tryParse(_percent.text.trim());
    return value != null && value >= 0 && value <= 100 ? value : null;
  }

  bool get _valid =>
      RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch(_key.text.trim()) &&
      _percentValue != null;

  void _save() {
    if (!_valid) {
      return;
    }
    Navigator.of(context).pop(
      _FlagResult(
        key: _key.text.trim(),
        description: _description.text,
        enabled: _enabled,
        rolloutPercent: _percentValue!,
        allowUsernames: [
          for (final name in _allow.text.split(RegExp(r'[\s,@]+')))
            if (name.isNotEmpty) name,
        ],
        minVersion: _version.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final editing = widget.flag != null;
    return CircleDialog(
      title: editing ? tr('Change flag') : tr('New flag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('admin-flag-key'),
            controller: _key,
            label: tr('Key'),
            helperText: tr('Lower-case letters, digits and underscores.'),
            enabled: !editing,
            maxLength: 40,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          WeCordTextField(
            fieldKey: const ValueKey('admin-flag-description'),
            controller: _description,
            label: tr('What it does'),
            maxLength: 200,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('On'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              WeCordSwitch(
                key: const ValueKey('admin-flag-enabled'),
                value: _enabled,
                semanticLabel: tr('On'),
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          WeCordTextField(
            fieldKey: const ValueKey('admin-flag-percent'),
            controller: _percent,
            label: tr('Share of people (0 to 100)'),
            helperText: tr(
              'The same people stay in as it goes up. 100 is everybody.',
            ),
            keyboardType: TextInputType.number,
            errorText: _percentValue == null
                ? tr('A number from 0 to 100.')
                : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          WeCordTextField(
            fieldKey: const ValueKey('admin-flag-allow'),
            controller: _allow,
            label: tr('Always on for (usernames)'),
            helperText: tr('Separated by spaces or commas.'),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          WeCordTextField(
            fieldKey: const ValueKey('admin-flag-version'),
            controller: _version,
            label: tr('Needs version (optional)'),
            hint: '1.2.0',
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          key: const ValueKey('admin-flag-cancel'),
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (editing)
          CircleDialogAction.danger(
            key: const ValueKey('admin-flag-delete'),
            label: tr('Delete'),
            onPressed: () => Navigator.of(
              context,
            ).pop(_FlagResult(key: widget.flag!.key, delete: true)),
          ),
        CircleDialogAction.primary(
          key: const ValueKey('admin-flag-save'),
          label: tr('Save'),
          onPressed: _valid ? _save : null,
        ),
      ],
    );
  }
}

class _MinimumDialog extends StatefulWidget {
  const _MinimumDialog({required this.platform, required this.current});

  final String platform;
  final String current;

  @override
  State<_MinimumDialog> createState() => _MinimumDialogState();
}

class _MinimumDialogState extends State<_MinimumDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final text = _controller.text.trim();
    return text.isEmpty ||
        RegExp(r'^[vV]?[0-9]{1,6}(\.[0-9]{1,6}){0,2}$').hasMatch(text);
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Minimum version: {platform}', {
        'platform': adminPlatformLabel(widget.platform),
      }),
      message: tr('Leave it empty for no minimum.'),
      content: WeCordTextField(
        fieldKey: const ValueKey('admin-minver-field'),
        controller: _controller,
        label: tr('Version'),
        hint: '1.2.0',
        autofocus: true,
        errorText: _valid ? null : tr('The version looks like 1.2.3.'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('admin-minver-save'),
          label: tr('Save'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
        ),
      ],
    );
  }
}
