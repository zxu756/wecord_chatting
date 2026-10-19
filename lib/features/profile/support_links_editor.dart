import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What an address looks like, shown faintly in the empty fields.
const _exampleUrl = 'https://ko-fi.com/you';
const _exampleCircleUrl = 'https://afdian.net/a/your-circle';

/// The names of the platforms support links may point to, for hints.
String supportPlatformNames() {
  final names = <String>[];
  for (final platform in supportPlatforms) {
    if (!names.contains(platform.name)) {
      names.add(platform.name);
    }
  }
  return [...names, 'GitHub Sponsors'].join(', ');
}

/// The "Support links" row of the profile settings. Not shown on iPhone
/// ([supportLinksAvailable]).
class SupportLinksSettingsRow extends ConsumerWidget {
  const SupportLinksSettingsRow({this.available, super.key});

  /// Overrides [supportLinksAvailable] (tests).
  final bool? available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(available ?? supportLinksAvailable())) {
      return const SizedBox.shrink();
    }
    final links = ref.watch(myProfileExtrasProvider).value?.links ?? const [];
    return SettingsRow(
      key: const ValueKey('settings-support-links'),
      icon: Icons.favorite_border_rounded,
      title: tr('Support links'),
      value: links.isEmpty ? tr('None') : '${links.length}',
      onTap: () async {
        final saved = await showSupportLinksEditor(context, current: links);
        if (saved == true) {
          ref.invalidate(myProfileExtrasProvider);
        }
      },
    );
  }
}

Future<bool?> showSupportLinksEditor(
  BuildContext context, {
  required List<SupportLink> current,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Support links'),
    builder: (context, _) => SupportLinksEditor(current: current),
  );
}

class SupportLinksEditor extends ConsumerStatefulWidget {
  const SupportLinksEditor({required this.current, super.key});

  final List<SupportLink> current;

  @override
  ConsumerState<SupportLinksEditor> createState() => _SupportLinksEditorState();
}

class _SupportLinksEditorState extends ConsumerState<SupportLinksEditor> {
  late final List<TextEditingController> _urls = [
    for (final link in widget.current) TextEditingController(text: link.url),
  ];
  late final List<TextEditingController> _labels = [
    for (final link in widget.current)
      TextEditingController(text: link.label ?? ''),
  ];
  var _saving = false;
  var _checked = false;
  String? _errorText;

  @override
  void dispose() {
    for (final controller in [..._urls, ..._labels]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _add() {
    setState(() {
      _urls.add(TextEditingController());
      _labels.add(TextEditingController());
    });
  }

  void _remove(int index) {
    setState(() {
      _urls.removeAt(index).dispose();
      _labels.removeAt(index).dispose();
    });
  }

  /// The address of row [index] when it is empty or allowed.
  bool _valid(int index) {
    final text = _urls[index].text.trim();
    return text.isEmpty || normalizeSupportUrl(text) != null;
  }

  Future<void> _save() async {
    setState(() => _checked = true);
    final links = <SupportLink>[];
    for (var i = 0; i < _urls.length; i++) {
      final text = _urls[i].text.trim();
      if (text.isEmpty) {
        continue;
      }
      final url = normalizeSupportUrl(text);
      if (url == null) {
        setState(
          () => _errorText = tr(
            'Only links to support pages such as {names} can be added.',
            {'names': supportPlatformNames()},
          ),
        );
        return;
      }
      final label = _labels[i].text.trim();
      links.add(SupportLink(url: url, label: label.isEmpty ? null : label));
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref.read(profileSocialRepositoryProvider).setMyLinks(links);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = tr('Could not save your links. Try again.');
        });
      }
    }
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
              Text(
                tr(
                  'Add up to {max} links to pages where people can support '
                  'you: {names}. WeCord does not handle the payment.',
                  {'max': maxSupportLinks, 'names': supportPlatformNames()},
                ),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < _urls.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WeCordTextField(
                            fieldKey: ValueKey('support-url-$i'),
                            controller: _urls[i],
                            enabled: !_saving,
                            maxLength: maxSupportUrlLength,
                            hint: _exampleUrl,
                            keyboardType: TextInputType.url,
                            errorText: _checked && !_valid(i)
                                ? tr("This isn't a supported support page.")
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 6),
                          WeCordTextField(
                            fieldKey: ValueKey('support-label-$i'),
                            controller: _labels[i],
                            enabled: !_saving,
                            maxLength: maxSupportLabelLength,
                            hint: tr('Label (optional)'),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('support-remove-$i'),
                      tooltip: tr('Remove link'),
                      icon: Icon(
                        Icons.remove_circle_outline_rounded,
                        color: c.muted,
                      ),
                      onPressed: _saving ? null : () => _remove(i),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (_urls.length < maxSupportLinks)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: WeCordButton(
                    key: const ValueKey('support-add'),
                    label: tr('Add a link'),
                    icon: Icons.add_rounded,
                    size: WeCordButtonSize.small,
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _saving ? null : _add,
                  ),
                ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ],
              const SizedBox(height: 18),
              WeCordButton(
                key: const ValueKey('support-save'),
                label: tr('Save'),
                expand: true,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The circle's support page in Circle settings: one field for a link to a
/// support platform; blank removes it. Not shown on iPhone.
class CircleSupportLinkSection extends ConsumerStatefulWidget {
  const CircleSupportLinkSection({
    required this.circleId,
    this.available,
    super.key,
  });

  final String circleId;

  /// Overrides [supportLinksAvailable] (tests).
  final bool? available;

  @override
  ConsumerState<CircleSupportLinkSection> createState() =>
      _CircleSupportLinkSectionState();
}

class _CircleSupportLinkSectionState
    extends ConsumerState<CircleSupportLinkSection> {
  final _controller = TextEditingController();
  String? _loadedFor;
  var _saving = false;
  String? _message;
  var _isError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isNotEmpty && normalizeSupportUrl(text) == null) {
      setState(() {
        _isError = true;
        _message = tr(
          'Only links to support pages such as {names} can be added.',
          {'names': supportPlatformNames()},
        );
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref
          .read(profileSocialRepositoryProvider)
          .setCircleSupportUrl(widget.circleId, text.isEmpty ? null : text);
      ref.invalidate(circleSupportUrlProvider(widget.circleId));
      if (mounted) {
        setState(() {
          _saving = false;
          _isError = false;
          _message = text.isEmpty ? tr('Link removed.') : tr('Link saved.');
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _isError = true;
          _message = tr('Could not save the link. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.available ?? supportLinksAvailable())) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final saved = ref.watch(circleSupportUrlProvider(widget.circleId));
    if (_loadedFor != widget.circleId && saved.hasValue) {
      _loadedFor = widget.circleId;
      _controller.text = saved.value ?? '';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SettingsGroup(
        header: tr('Support page'),
        footer: tr(
          'Members see a Support entry in the circle menu. WeCord does not '
          'handle the payment.',
        ),
        padding: const EdgeInsets.all(14),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordTextField(
                fieldKey: const ValueKey('circle-support-url'),
                controller: _controller,
                enabled: !_saving,
                maxLength: maxSupportUrlLength,
                hint: _exampleCircleUrl,
                keyboardType: TextInputType.url,
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  key: const ValueKey('circle-support-message'),
                  style: TextStyle(
                    fontSize: 13,
                    color: _isError ? c.dangerText : c.muted,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: WeCordButton(
                  key: const ValueKey('circle-support-save'),
                  label: tr('Save'),
                  size: WeCordButtonSize.small,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
