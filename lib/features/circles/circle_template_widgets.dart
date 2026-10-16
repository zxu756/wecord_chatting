import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/features/circles/circle_template_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Circle settings → Template: saves the circle's layout under a code
/// others can start a circle from; syncs and deletes it.
class CircleTemplateSection extends ConsumerStatefulWidget {
  const CircleTemplateSection({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleTemplateSection> createState() =>
      _CircleTemplateSectionState();
}

class _CircleTemplateSectionState extends ConsumerState<CircleTemplateSection> {
  var _busy = false;

  Future<void> _run(
    Future<void> Function(CircleTemplateRepository repository) action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await action(ref.read(circleTemplateRepositoryProvider));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      ref.invalidate(circleTemplateProvider(widget.circleId));
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() async {
    final result = await showCircleDialog<(String, String?)>(
      context,
      builder: (context) => const _TemplateDetailsDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.createTemplate(
        circleId: widget.circleId,
        name: result.$1,
        description: result.$2,
      ),
      failure: tr('Could not create the template. Try again.'),
    );
  }

  Future<void> _sync(CircleTemplate template) async {
    await _run((repository) async {
      await repository.syncTemplate(template.id);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Template synced with the circle.'))),
        );
      }
    }, failure: tr('Could not sync the template. Try again.'));
  }

  Future<void> _delete(CircleTemplate template) async {
    final confirmed = await showCircleDialog<bool>(
      context,
      builder: (context) => CircleDialog(
        title: tr('Delete template'),
        message: tr(
          'Delete "{name}"? Its code stops working. Circles already '
          'created from it stay as they are.',
          {'name': template.name},
        ),
        actions: [
          CircleDialogAction(
            label: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CircleDialogAction.danger(
            key: const ValueKey('template-delete-confirm'),
            label: tr('Delete'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.deleteTemplate(template.id),
      failure: tr('Could not delete the template. Try again.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final template = ref.watch(circleTemplateProvider(widget.circleId));
    final value = template.valueOrNull;
    final List<Widget> rows;
    if (template.isLoading && value == null) {
      rows = [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (template.hasError) {
      rows = [
        SettingsRow(
          icon: Icons.error_outline,
          title: tr('Could not load the template.'),
        ),
      ];
    } else if (value == null) {
      rows = [
        SettingsRow(
          key: const ValueKey('template-create-button'),
          icon: Icons.copy_all_outlined,
          tone: SettingsTone.accent,
          title: tr('Create template'),
          onTap: _busy ? null : _create,
        ),
      ];
    } else {
      rows = [
        SettingsRow(
          key: const ValueKey('template-tile'),
          icon: Icons.dashboard_customize_outlined,
          tone: SettingsTone.accent,
          title: value.name,
          subtitle: [
            if (value.description case final description?) description,
            tr('{channels} channels · {roles} roles · used {count} times', {
              'channels': value.channelCount,
              'roles': value.roleCount,
              'count': value.usageCount,
            }),
          ].join('\n'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                  ),
                  child: SelectableText(
                    value.code,
                    key: const ValueKey('template-code'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              WeCordIconButton(
                key: const ValueKey('template-copy-code'),
                tooltip: tr('Copy code'),
                icon: Icons.copy_outlined,
                variant: WeCordButtonVariant.ghost,
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: value.code)));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(tr('Template code copied.'))),
                  );
                },
              ),
            ],
          ),
        ),
        SettingsRow(
          key: const ValueKey('template-sync-button'),
          icon: Icons.sync,
          title: tr('Sync template'),
          showChevron: false,
          onTap: _busy ? null : () => _sync(value),
        ),
        SettingsRow(
          key: const ValueKey('template-delete-button'),
          icon: Icons.delete_outline,
          title: tr('Delete template'),
          destructive: true,
          showChevron: false,
          onTap: _busy ? null : () => _delete(value),
        ),
      ];
    }
    return Column(
      key: const ValueKey('circle-template-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CircleSettingsHeader(
          tr('Template'),
          subtitle: tr(
            'Share the layout of this circle (channels, categories, roles '
            'and permissions, but no messages or members) as a code others '
            'can create a circle from.',
          ),
        ),
        SettingsGroup(children: rows),
      ],
    );
  }
}

class _TemplateDetailsDialog extends StatefulWidget {
  const _TemplateDetailsDialog();

  @override
  State<_TemplateDetailsDialog> createState() => _TemplateDetailsDialogState();
}

class _TemplateDetailsDialogState extends State<_TemplateDetailsDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('Template name is required.'));
      return;
    }
    final description = _description.text.trim();
    Navigator.of(context).pop((name, description.isEmpty ? null : description));
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Create template'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('template-name-field'),
            controller: _name,
            autofocus: true,
            maxLength: CircleTemplate.maxNameLength,
            label: tr('Template name'),
            errorText: _error,
          ),
          const SizedBox(height: 8),
          WeCordTextField(
            fieldKey: const ValueKey('template-description-field'),
            controller: _description,
            maxLength: CircleTemplate.maxDescriptionLength,
            maxLines: 2,
            label: tr('Description (optional)'),
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('template-details-submit'),
          label: tr('Create'),
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Asks for a template code, previews the template and creates a circle
/// from it. Completes with the new circle's id, or null.
Future<String?> showUseCircleTemplateSheet(BuildContext context) {
  return showWeCordSheet<String>(
    context,
    builder: (context, _) => const UseCircleTemplateSheet(),
  );
}

class UseCircleTemplateSheet extends ConsumerStatefulWidget {
  const UseCircleTemplateSheet({super.key});

  @override
  ConsumerState<UseCircleTemplateSheet> createState() =>
      _UseCircleTemplateSheetState();
}

class _UseCircleTemplateSheetState
    extends ConsumerState<UseCircleTemplateSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  CircleTemplate? _template;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final code = parseCircleTemplateCode(_code.text);
    if (code == null) {
      setState(() => _error = tr('Enter a template code.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final template = await ref
          .read(circleTemplateRepositoryProvider)
          .previewTemplate(code);
      if (!mounted) return;
      setState(() {
        _template = template;
        _name.text = template.name.length > 80
            ? template.name.substring(0, 80)
            : template.name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = tr('No template has this code.'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create(CircleTemplate template) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('Circle name is required.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final circleId = await ref
          .read(circleTemplateRepositoryProvider)
          .createCircleFromTemplate(code: template.code, name: name);
      if (mounted) {
        Navigator.of(context).pop(circleId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tr('Could not create the circle. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final template = _template;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        16 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              tr('Create from a template'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (template == null) ...[
            WeCordTextField(
              fieldKey: const ValueKey('template-code-field'),
              controller: _code,
              autofocus: true,
              label: tr('Template code'),
              errorText: _error,
              onSubmitted: (_) => _busy ? null : _preview(),
            ),
            const SizedBox(height: 16),
            WeCordButton(
              key: const ValueKey('template-preview-button'),
              label: tr('Continue'),
              size: WeCordButtonSize.large,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _preview,
            ),
          ] else ...[
            CircleTemplatePreview(template: template),
            const SizedBox(height: 16),
            WeCordTextField(
              fieldKey: const ValueKey('template-circle-name-field'),
              controller: _name,
              maxLength: 80,
              label: tr('Circle name'),
              errorText: _error,
            ),
            const SizedBox(height: 12),
            WeCordButton(
              key: const ValueKey('template-create-circle-button'),
              label: tr('Create circle'),
              size: WeCordButtonSize.large,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : () => _create(template),
            ),
            const SizedBox(height: 8),
            WeCordButton(
              label: tr('Back'),
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _template = null;
                      _error = null;
                    }),
            ),
          ],
        ],
      ),
    );
  }
}

/// A template's name, origin and outline: categories with their
/// channels, and roles.
class CircleTemplatePreview extends StatelessWidget {
  const CircleTemplatePreview({required this.template, super.key});

  final CircleTemplate template;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final categoryKeys = {
      for (final category in template.categories) category.key,
    };
    Widget channelRow(CircleTemplateChannel channel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              switch (channel.kind) {
                CircleChannelKind.voice => Icons.volume_up_outlined,
                CircleChannelKind.stage => Icons.podcasts,
                CircleChannelKind.forum => Icons.forum_outlined,
                CircleChannelKind.announcement => Icons.campaign_outlined,
                CircleChannelKind.text => Icons.tag,
              },
              size: 16,
              color: c.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: c.ink),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('template-preview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            template.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          if (template.description case final description?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                description,
                style: TextStyle(fontSize: 14, color: c.ink),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            tr('From {circle}', {'circle': template.circleName}),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(height: 1, color: c.lineSoft),
          ),
          for (final channel in template.channels)
            if (channel.categoryKey == null ||
                !categoryKeys.contains(channel.categoryKey))
              channelRow(channel),
          for (final category in template.categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                category.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.subtle,
                ),
              ),
            ),
            for (final channel in template.channels)
              if (channel.categoryKey == category.key) channelRow(channel),
          ],
          if (template.roles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final role in template.roles)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: c.raised,
                      borderRadius: BorderRadius.circular(WeCordRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: role.color == null
                                ? c.faint
                                : Color(0xFF000000 | role.color!),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          role.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
