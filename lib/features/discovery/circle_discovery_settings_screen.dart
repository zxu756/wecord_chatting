import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/discovery/circle_discovery_repository.dart';
import 'package:wecord/features/discovery/discovery_widgets.dart';
import 'package:wecord/features/discovery/public_circle_link.dart';
import 'package:wecord/features/discovery/public_circle_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

void openCircleDiscoverySettings(BuildContext context, CircleDetail detail) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleDiscoverySettingsScreen(detail: detail),
    ),
  );
}

/// Circle settings → Discovery: whether the circle is public, and what
/// Explore shows about it (description, category, language, tags), with a
/// preview of its card.
class CircleDiscoverySettingsScreen extends ConsumerWidget {
  const CircleDiscoverySettingsScreen({required this.detail, super.key});

  final CircleDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      circleDiscoverySettingsProvider(detail.circle.id),
    );
    // The short name of the circle's web page. Without it (older server, no
    // permission) the rest of the page works and the section is left out.
    final slug = ref.watch(circleSlugProvider(detail.circle.id));
    if (settings.hasValue && slug.isLoading) {
      return CirclePageScaffold(
        title: tr('Discovery'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return settings.when(
      loading: () => CirclePageScaffold(
        title: tr('Discovery'),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => CirclePageScaffold(
        title: tr('Discovery'),
        body: CircleEmptyState(
          icon: Icons.explore_outlined,
          title: tr('Could not load discovery settings.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () => ref.invalidate(
              circleDiscoverySettingsProvider(detail.circle.id),
            ),
          ),
        ),
      ),
      data: (settings) => _DiscoveryEditor(
        detail: detail,
        initial: settings,
        slugAvailable: !slug.hasError,
        initialSlug: slug.value,
      ),
    );
  }
}

class _DiscoveryEditor extends ConsumerStatefulWidget {
  const _DiscoveryEditor({
    required this.detail,
    required this.initial,
    this.slugAvailable = false,
    this.initialSlug,
  });

  final CircleDetail detail;
  final CircleDiscoverySettings initial;

  /// Whether the short name can be edited here.
  final bool slugAvailable;
  final String? initialSlug;

  @override
  ConsumerState<_DiscoveryEditor> createState() => _DiscoveryEditorState();
}

class _DiscoveryEditorState extends ConsumerState<_DiscoveryEditor> {
  late var _public = widget.initial.isPublic;
  late var _category = widget.initial.category;
  late var _language = widget.initial.language;
  late final _tags = [...widget.initial.tags];
  late final _description = TextEditingController(
    text: widget.initial.description ?? '',
  );
  final _tag = TextEditingController();
  late final _slug = TextEditingController(text: widget.initialSlug ?? '');
  var _saving = false;
  String? _error;
  String? _tagError;
  String? _slugError;

  String get _circleId => widget.detail.circle.id;

  @override
  void dispose() {
    _description.dispose();
    _tag.dispose();
    _slug.dispose();
    super.dispose();
  }

  void _addTag() {
    final input = _tag.text;
    if (input.trim().isEmpty) {
      return;
    }
    final problem = discoveryTagProblem(input);
    final tag = normalizeDiscoveryTag(input);
    setState(() {
      if (_tags.length >= DiscoveryLimits.tags) {
        _tagError = tr('Up to 5 tags.');
      } else if (problem == 'length') {
        _tagError = tr('A tag is up to 24 characters.');
      } else if (problem == 'characters') {
        _tagError = tr('Tags cannot have commas or #.');
      } else if (problem == null) {
        if (!_tags.contains(tag)) {
          _tags.add(tag);
        }
        _tag.clear();
        _tagError = null;
      }
    });
  }

  /// The sentence for what is wrong with the short name, or null.
  String? _slugMessage(String input) => switch (circleSlugProblem(input)) {
    'length' ||
    'characters' ||
    'hyphens' => tr('A short name is 3 to 32 letters, digits and hyphens.'),
    'reserved' => tr('That short name is reserved.'),
    _ => null,
  };

  Future<void> _save() async {
    if (_public && _category == null) {
      setState(() => _error = tr('Pick a category to make the circle public.'));
      return;
    }
    final slugText = normalizeCircleSlug(_slug.text);
    final slugChanged =
        widget.slugAvailable && slugText != (widget.initialSlug ?? '');
    if (slugChanged) {
      final message = _slugMessage(slugText);
      if (message != null) {
        setState(() => _slugError = message);
        return;
      }
    }
    if (_tag.text.trim().isNotEmpty) {
      _addTag();
      if (_tagError != null) {
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(circleDiscoveryRepositoryProvider)
          .saveSettings(
            circleId: _circleId,
            isPublic: _public,
            description: _description.text,
            category: _category,
            language: _language,
            tags: _tags,
          );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save discovery settings. Try again.');
        });
      }
      return;
    }
    ref.invalidate(circleDiscoverySettingsProvider(_circleId));
    if (slugChanged) {
      try {
        await ref
            .read(publicCircleRepositoryProvider)
            .setSlug(_circleId, slugText);
      } on CircleSlugException catch (error) {
        ref.invalidate(circleSlugProvider(_circleId));
        if (mounted) {
          setState(() {
            _saving = false;
            _slugError = error.message;
          });
        }
        return;
      }
      ref.invalidate(circleSlugProvider(_circleId));
    }
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _public
                ? tr('Your circle is now listed in Explore.')
                : tr('Discovery settings saved.'),
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// The short link of the circle's page for people without the app.
  List<Widget> _webPage(BuildContext context) {
    final c = context.tokens.colors;
    final typed = normalizeCircleSlug(_slug.text);
    final saved = widget.initialSlug;
    final showsLink = typed.isNotEmpty && circleSlugProblem(typed) == null;
    return [
      SettingsSectionHeader(tr('Web page')),
      CircleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WeCordTextField(
              fieldKey: const ValueKey('discovery-slug-field'),
              controller: _slug,
              hint: tr('Short name, e.g. pixel-painters'),
              errorText: _slugError,
              prefixIcon: Icons.link_rounded,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(CircleSlugLimits.maxLength),
              ],
              onChanged: (_) => setState(() => _slugError = null),
            ),
            if (showsLink) ...[
              const SizedBox(height: 12),
              SelectableText(
                publicCircleUrl(typed),
                key: const ValueKey('discovery-slug-link'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.accentText,
                ),
              ),
              if (saved == typed) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WeCordButton(
                    key: const ValueKey('discovery-slug-copy'),
                    label: tr('Copy link'),
                    icon: Icons.copy_rounded,
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.medium,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: publicCircleUrl(typed)),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text(tr('Link copied'))),
                        );
                      }
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
        child: Text(
          tr(
            'While the circle is public, anyone with this link can see its '
            'name, picture, description, tags and a rounded member count on a '
            'web page, without an account, and link previews show the same. '
            'Never the members.',
          ),
          style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final circle = widget.detail.circle;
    final description = _description.text.trim();
    return CirclePageScaffold(
      title: tr('Discovery'),
      subtitle: circle.name,
      actions: [
        WeCordButton(
          key: const ValueKey('discovery-settings-save'),
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
                key: const ValueKey('discovery-settings-error'),
                style: TextStyle(
                  color: c.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SettingsGroup(
            children: [
              SettingsRow.toggle(
                key: const ValueKey('discovery-public'),
                icon: Icons.public_rounded,
                tone: SettingsTone.accent,
                title: tr('Public circle'),
                subtitle: tr(
                  'Listed in Explore, and anyone signed in can join. Bans, '
                  'rules and AutoMod still apply. Off: invite only.',
                ),
                value: _public,
                onChanged: (value) => setState(() {
                  _public = value;
                  _error = null;
                }),
              ),
            ],
          ),
          SettingsSectionHeader(tr('Description')),
          CircleCard(
            child: WeCordTextField(
              fieldKey: const ValueKey('discovery-description'),
              controller: _description,
              maxLength: DiscoveryLimits.descriptionLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  DiscoveryLimits.descriptionLength,
                ),
              ],
              minLines: 3,
              maxLines: 6,
              hint: tr('What is this circle about? Who is it for?'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SettingsSectionHeader(tr('Category')),
          CircleCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in DiscoveryCategory.values)
                  WeCordChip(
                    key: ValueKey('discovery-settings-${category.value}'),
                    label: category.label,
                    icon: category.icon,
                    selected: _category == category,
                    onPressed: () => setState(() {
                      _category = _category == category ? null : category;
                      _error = null;
                    }),
                  ),
              ],
            ),
          ),
          SettingsSectionHeader(tr('Language')),
          CircleCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WeCordChip(
                  key: const ValueKey('discovery-language-none'),
                  label: tr('Not set'),
                  selected: _language == null,
                  onPressed: () => setState(() => _language = null),
                ),
                for (final MapEntry(key: code, value: name)
                    in DiscoveryLanguages.names.entries)
                  WeCordChip(
                    key: ValueKey('discovery-language-$code'),
                    label: name,
                    selected: _language == code,
                    onPressed: () => setState(() => _language = code),
                  ),
              ],
            ),
          ),
          SettingsSectionHeader(tr('Tags')),
          CircleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: WeCordTextField(
                        fieldKey: const ValueKey('discovery-tag-field'),
                        controller: _tag,
                        enabled: _tags.length < DiscoveryLimits.tags,
                        hint: _tags.length < DiscoveryLimits.tags
                            ? tr('Add a tag, e.g. pixel art')
                            : tr('Up to 5 tags.'),
                        errorText: _tagError,
                        prefixIcon: Icons.tag_rounded,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [LengthLimitingTextInputFormatter(26)],
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: WeCordButton(
                        key: const ValueKey('discovery-tag-add'),
                        label: tr('Add'),
                        variant: WeCordButtonVariant.secondary,
                        onPressed: _tags.length < DiscoveryLimits.tags
                            ? _addTag
                            : null,
                      ),
                    ),
                  ],
                ),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in _tags)
                        WeCordChip(
                          key: ValueKey('discovery-tag-$tag'),
                          label: '#$tag',
                          icon: Icons.close_rounded,
                          onPressed: () => setState(() {
                            _tags.remove(tag);
                            _tagError = null;
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (widget.slugAvailable) ..._webPage(context),
          SettingsSectionHeader(tr('Preview')),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 320,
                height: DiscoveryCircleCard.heightOf(context),
                child: DiscoveryCircleCard(
                  circle: DiscoverableCircle(
                    id: circle.id,
                    name: circle.name,
                    avatarUrl: circle.avatarUrl,
                    description: description.isEmpty ? null : description,
                    category: _category,
                    language: _language,
                    tags: _tags,
                    memberCount: widget.detail.members.length,
                  ),
                  onOpen: () {},
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
            child: Text(
              tr(
                'Explore also shows how many members are online, and your '
                'channel names and rules to people deciding whether to join.',
              ),
              style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
