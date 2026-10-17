import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/moments/moment_audience_sheet.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether [text] is a link a Moment can share.
bool isMomentLink(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// New Moment: text, up to nine photos or a link, a place, and who can see
/// it. The post is sent with an id made here, so trying again after a
/// failure never posts it twice.
class MomentComposerScreen extends ConsumerStatefulWidget {
  const MomentComposerScreen({super.key});

  static const path = '/moments/compose';

  @override
  ConsumerState<MomentComposerScreen> createState() =>
      _MomentComposerScreenState();
}

class _MomentComposerScreenState extends ConsumerState<MomentComposerScreen> {
  final _text = TextEditingController();
  final _link = TextEditingController();
  final _linkTitle = TextEditingController();
  final _location = TextEditingController();
  final _id = newMomentId();
  final _photos = <MomentPhotoDraft>[];
  var _audience = MomentAudience.everyone;
  var _linkOpen = false;
  var _locationOpen = false;
  var _picking = false;
  var _posting = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    _linkTitle.dispose();
    _location.dispose();
    super.dispose();
  }

  bool get _hasLink => _linkOpen && _link.text.trim().isNotEmpty;

  bool get _linkValid => !_hasLink || isMomentLink(_link.text);

  bool get _canPost =>
      !_posting &&
      !_picking &&
      _audience.isComplete &&
      _linkValid &&
      (_text.text.trim().isNotEmpty || _photos.isNotEmpty || _hasLink);

  Future<void> _addPhotos() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ref
          .read(momentPhotoPickerProvider)
          .pickPhotos(limit: momentPhotoRoom(_photos.length));
      if (!mounted) {
        return;
      }
      setState(() {
        _photos.addAll(picked.take(momentPhotoRoom(_photos.length)));
        _picking = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _picking = false;
          _error = tr('Could not use those pictures. Try others.');
        });
      }
    }
  }

  Future<void> _chooseAudience() async {
    final picked = await showMomentAudienceSheet(context, current: _audience);
    if (picked != null && mounted) {
      setState(() => _audience = picked);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(MomentsScreen.path);
    }
  }

  Future<void> _post() async {
    if (!_canPost) {
      return;
    }
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await ref
          .read(momentsRepositoryProvider)
          .create(
            id: _id,
            body: _text.text.trim(),
            photos: _photos,
            linkUrl: _hasLink ? _link.text.trim() : null,
            linkTitle: _hasLink ? _linkTitle.text.trim() : null,
            location: _locationOpen ? _location.text.trim() : null,
            audience: _audience,
          );
      await ref.read(momentsFeedProvider.notifier).addPosted(_id);
      if (mounted) {
        _close();
      }
    } on Object {
      if (mounted) {
        setState(() {
          _posting = false;
          _error = tr('Could not post. Check your connection and try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final friends = ref.watch(friendsProvider).value ?? const <Profile>[];
    final tags = ref.watch(friendTagsProvider).value ?? const FriendTagsData();
    final summary = audienceSummary(_audience, tags: tags, friends: friends);
    final room = momentPhotoRoom(_photos.length);
    return Scaffold(
      backgroundColor: c.paper,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('New Moment'),
                  actions: [
                    WeCordButton(
                      key: const ValueKey('moment-post'),
                      label: tr('Post'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.accent,
                      loading: _posting,
                      onPressed: _canPost ? _post : null,
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: c.panel,
                          borderRadius: BorderRadius.circular(WeCordRadii.xl),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              key: const ValueKey('moment-text'),
                              controller: _text,
                              minLines: 4,
                              maxLines: 10,
                              maxLength: maxMomentTextLength,
                              buildCounter:
                                  (
                                    context, {
                                    required currentLength,
                                    required isFocused,
                                    required maxLength,
                                  }) =>
                                      currentLength > maxMomentTextLength * 0.85
                                      ? Text(
                                          '$currentLength / $maxLength',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.subtle,
                                          ),
                                        )
                                      : null,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                fontSize: 16.5,
                                height: 1.45,
                                color: c.ink,
                              ),
                              decoration: InputDecoration.collapsed(
                                hintText: tr("What's on your mind?"),
                                hintStyle: TextStyle(
                                  fontSize: 16.5,
                                  color: c.subtle,
                                ),
                              ),
                            ),
                            if (!_linkOpen) ...[
                              const SizedBox(height: 14),
                              _PhotoStrip(
                                photos: _photos,
                                canAdd: room > 0,
                                busy: _picking,
                                onAdd: _addPhotos,
                                onRemove: (draft) =>
                                    setState(() => _photos.remove(draft)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SettingsGroup(
                        separatorIndent: 58,
                        children: [
                          if (_photos.isEmpty)
                            SettingsRow(
                              key: const ValueKey('moment-add-link'),
                              icon: Icons.link_rounded,
                              title: tr('Add a link'),
                              value: _linkOpen ? tr('Added') : null,
                              onTap: () => setState(() {
                                _linkOpen = !_linkOpen;
                                if (!_linkOpen) {
                                  _link.clear();
                                  _linkTitle.clear();
                                }
                              }),
                            ),
                          SettingsRow(
                            key: const ValueKey('moment-add-location'),
                            icon: Icons.place_outlined,
                            title: tr('Location'),
                            value: _locationOpen ? tr('Added') : null,
                            onTap: () => setState(() {
                              _locationOpen = !_locationOpen;
                              if (!_locationOpen) {
                                _location.clear();
                              }
                            }),
                          ),
                          SettingsRow(
                            key: const ValueKey('moment-audience'),
                            icon: Icons.visibility_outlined,
                            tone:
                                _audience.visibility == MomentVisibility.friends
                                ? SettingsTone.neutral
                                : SettingsTone.accent,
                            title: tr('Who can see this'),
                            subtitle: summary,
                            onTap: _chooseAudience,
                          ),
                        ],
                      ),
                      if (_linkOpen) ...[
                        const SizedBox(height: 12),
                        WeCordTextField(
                          fieldKey: const ValueKey('moment-link-field'),
                          controller: _link,
                          onPaper: true,
                          label: tr('Link'),
                          hint: 'https://',
                          keyboardType: TextInputType.url,
                          prefixIcon: Icons.link_rounded,
                          errorText: _linkValid
                              ? null
                              : tr(
                                  'Enter a web address starting with https://',
                                ),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(2000),
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        WeCordTextField(
                          fieldKey: const ValueKey('moment-link-title-field'),
                          controller: _linkTitle,
                          onPaper: true,
                          label: tr('Title (optional)'),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(200),
                          ],
                        ),
                      ],
                      if (_locationOpen) ...[
                        const SizedBox(height: 12),
                        WeCordTextField(
                          fieldKey: const ValueKey('moment-location-field'),
                          controller: _location,
                          onPaper: true,
                          label: tr('Where are you?'),
                          prefixIcon: Icons.place_outlined,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(80),
                          ],
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                          child: Text(
                            _error!,
                            key: const ValueKey('moment-error'),
                            style: TextStyle(
                              fontSize: 13.5,
                              color: c.dangerText,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                        child: Text(
                          tr(
                            'Photos are kept private and scaled down before they are sent.',
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: c.subtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The thumbnails being posted, each with a remove button, then a tile to
/// add more.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.canAdd,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  final List<MomentPhotoDraft> photos;
  final bool canAdd;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<MomentPhotoDraft> onRemove;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - _gap * 2) / 3).floorToDouble();
        return Wrap(
          key: const ValueKey('moment-photo-strip'),
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final (index, draft) in photos.indexed)
              SizedBox(
                key: ValueKey('moment-draft-$index'),
                width: side,
                height: side,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(WeCordRadii.sm),
                      child: Image.memory(
                        draft.thumb,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: WeCordIconButton(
                        key: ValueKey('moment-draft-remove-$index'),
                        icon: Icons.close_rounded,
                        tooltip: tr('Remove photo {number}', {
                          'number': index + 1,
                        }),
                        size: 28,
                        iconSize: 15,
                        variant: WeCordButtonVariant.primary,
                        onPressed: () => onRemove(draft),
                      ),
                    ),
                  ],
                ),
              ),
            if (canAdd)
              SizedBox(
                width: side,
                height: side,
                child: WeCordPressable(
                  key: const ValueKey('moment-add-photos'),
                  onPressed: busy ? null : onAdd,
                  pressedScale: 0.97,
                  semanticLabel: tr('Add photos'),
                  excludeSemantics: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  ),
                  builder: (context, states) => Container(
                    decoration: BoxDecoration(
                      color: c.raised,
                      borderRadius: BorderRadius.circular(WeCordRadii.sm),
                    ),
                    child: busy
                        ? const Center(
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 28,
                            color: c.muted,
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
