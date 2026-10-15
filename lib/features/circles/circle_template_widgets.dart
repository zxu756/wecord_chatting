import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/features/circles/circle_template_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

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
    final result = await showDialog<(String, String?)>(
      context: context,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Delete template')),
        content: Text(
          tr(
            'Delete "{name}"? Its code stops working. Circles already '
            'created from it stay as they are.',
            {'name': template.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('template-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
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
    final theme = Theme.of(context);
    final template = ref.watch(circleTemplateProvider(widget.circleId));
    final value = template.valueOrNull;
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
        if (template.isLoading && value == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (template.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(tr('Could not load the template.')),
          )
        else if (value == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: const ValueKey('template-create-button'),
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(tr('Create template')),
              ),
            ),
          )
        else ...[
          ListTile(
            key: const ValueKey('template-tile'),
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: Text(value.name),
            subtitle: Text(
              [
                if (value.description case final description?) description,
                tr('{channels} channels · {roles} roles · used {count} times', {
                  'channels': value.channelCount,
                  'roles': value.roleCount,
                  'count': value.usageCount,
                }),
              ].join('\n'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value.code,
                    key: const ValueKey('template-code'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('template-copy-code'),
                  tooltip: tr('Copy code'),
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: value.code)),
                    );
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(tr('Template code copied.'))),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('template-sync-button'),
                  onPressed: _busy ? null : () => _sync(value),
                  icon: const Icon(Icons.sync),
                  label: Text(tr('Sync template')),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('template-delete-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _busy ? null : () => _delete(value),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('Delete template')),
                ),
              ],
            ),
          ),
        ],
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
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Create template')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('template-name-field'),
            controller: _name,
            autofocus: true,
            maxLength: CircleTemplate.maxNameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Template name'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('template-description-field'),
            controller: _description,
            maxLength: CircleTemplate.maxDescriptionLength,
            maxLines: 2,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Description (optional)'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('template-details-submit'),
          onPressed: _submit,
          child: Text(tr('Create')),
        ),
      ],
    );
  }
}

/// Asks for a template code, previews the template and creates a circle
/// from it. Completes with the new circle's id, or null.
Future<String?> showUseCircleTemplateSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const UseCircleTemplateSheet(),
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
    final theme = Theme.of(context);
    final template = _template;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Create from a template'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (template == null) ...[
                TextField(
                  key: const ValueKey('template-code-field'),
                  controller: _code,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Template code'),
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _busy ? null : _preview(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const ValueKey('template-preview-button'),
                    onPressed: _busy ? null : _preview,
                    child: Text(tr('Continue')),
                  ),
                ),
              ] else ...[
                CircleTemplatePreview(template: template),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('template-circle-name-field'),
                  controller: _name,
                  maxLength: 80,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: tr('Circle name'),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _template = null;
                              _error = null;
                            }),
                      child: Text(tr('Back')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('template-create-circle-button'),
                      onPressed: _busy ? null : () => _create(template),
                      child: Text(tr('Create circle')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final categoryKeys = {for (final c in template.categories) c.key};
    Widget channelRow(CircleTemplateChannel channel) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
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
              color: muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('template-preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            template.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (template.description case final description?)
            Text(description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            tr('From {circle}', {'circle': template.circleName}),
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
          const Divider(height: 20),
          for (final channel in template.channels)
            if (channel.categoryKey == null ||
                !categoryKeys.contains(channel.categoryKey))
              channelRow(channel),
          for (final category in template.categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                category.name.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final channel in template.channels)
              if (channel.categoryKey == category.key) channelRow(channel),
          ],
          if (template.roles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final role in template.roles)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.circle,
                      size: 12,
                      color: role.color == null
                          ? muted
                          : Color(0xFF000000 | role.color!),
                    ),
                    label: Text(role.name),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
