import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/hashtags/hashtag_text.dart';
import 'package:wecord/features/moments/moment_audience_sheet.dart';
import 'package:wecord/features/moments/moment_mentions.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_video.dart';
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

/// New Moment: text, up to nine photos (each can be described), one video
/// (3 minutes, 50 MB) or a link, a place, who can see it and whom to remind
/// to read it. The post is sent with an id made here, so trying again after a
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
  MomentVideoDraft? _video;
  double? _uploadProgress;
  var _audience = MomentAudience.everyone;
  var _mentioned = <String>{};
  var _linkOpen = false;
  var _locationOpen = false;
  var _picking = false;
  var _posting = false;
  String? _error;

  /// Puts `#tag ` at the end of the text (a topic friends already use).
  void _addTopic(String tag) {
    final current = _text.text;
    final glue =
        current.isEmpty || current.endsWith(' ') || current.endsWith('\n')
        ? ''
        : ' ';
    final next = '$current$glue#$tag ';
    if (next.length > maxMomentTextLength) {
      return;
    }
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

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
      (_text.text.trim().isNotEmpty ||
          _photos.isNotEmpty ||
          _video != null ||
          _hasLink);

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

  Future<void> _addVideo() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ref.read(momentPhotoPickerProvider).pickVideo();
      if (!mounted) {
        return;
      }
      setState(() {
        _video = picked ?? _video;
        _picking = false;
      });
    } on MomentVideoException catch (problem) {
      if (mounted) {
        setState(() {
          _picking = false;
          _error = switch (problem.problem) {
            MomentVideoProblem.tooLong => tr(
              'That video is longer than 3 minutes. Choose a shorter one.',
            ),
            MomentVideoProblem.tooBig => tr(
              'That video is bigger than 50 MB. Choose a smaller one.',
            ),
            MomentVideoProblem.unsupported => tr(
              'Choose an MP4, MOV or WebM video.',
            ),
            MomentVideoProblem.unreadable => tr(
              'Could not read that video. Try another.',
            ),
          };
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _picking = false;
          _error = tr('Could not read that video. Try another.');
        });
      }
    }
  }

  Future<void> _chooseAudience() async {
    final picked = await showMomentAudienceSheet(context, current: _audience);
    if (picked != null && mounted) {
      final friends = ref.read(friendsProvider).value ?? const <Profile>[];
      final tags = ref.read(friendTagsProvider).value ?? const FriendTagsData();
      setState(() {
        _audience = picked;
        // Whoever cannot see it now cannot be reminded.
        _mentioned = keepMentionable(
          _mentioned,
          momentMentionCandidates(
            friends: friends,
            tags: tags,
            audience: picked,
          ),
        );
      });
    }
  }

  Future<void> _chooseMentions() async {
    final friends = ref.read(friendsProvider).value ?? const <Profile>[];
    final tags = ref.read(friendTagsProvider).value ?? const FriendTagsData();
    final picked = await showMomentMentionSheet(
      context,
      candidates: momentMentionCandidates(
        friends: friends,
        tags: tags,
        audience: _audience,
      ),
      selected: _mentioned,
    );
    if (picked != null && mounted) {
      setState(() => _mentioned = picked);
    }
  }

  /// Asks what the photos show, all of them or just [only].
  Future<void> _describe({MomentPhotoDraft? only}) async {
    final targets = only == null ? [..._photos] : [only];
    final result = await showImageAltSheet(
      context,
      pictures: [
        for (final draft in targets)
          AltPicture(id: draft.id, picture: draft.thumb, current: draft.alt),
      ],
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      for (final (index, draft) in _photos.indexed) {
        if (result.containsKey(draft.id)) {
          _photos[index] = draft.withAlt(result[draft.id]);
        }
      }
    });
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
            video: _video,
            onUploadProgress: (progress) {
              if (mounted) {
                setState(() => _uploadProgress = progress);
              }
            },
            linkUrl: _hasLink ? _link.text.trim() : null,
            linkTitle: _hasLink ? _linkTitle.text.trim() : null,
            location: _locationOpen ? _location.text.trim() : null,
            audience: _audience,
            mentionedIds: _mentioned.toList(),
          );
      await ref.read(momentsFeedProvider.notifier).addPosted(_id);
      if (mounted) {
        _close();
      }
    } on Object {
      if (mounted) {
        setState(() {
          _posting = false;
          _uploadProgress = null;
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
    final canRemind = _audience.visibility != MomentVisibility.private;
    final described = _photos.where((draft) => draft.alt != null).length;
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
                            _TopicSuggestions(
                              text: _text.text,
                              enabled: !_posting,
                              onPick: _addTopic,
                            ),
                            if (!_linkOpen) ...[
                              const SizedBox(height: 14),
                              if (_video case final video?)
                                _VideoDraftTile(
                                  video: video,
                                  locked: _posting,
                                  onRemove: () => setState(() => _video = null),
                                )
                              else
                                _PhotoStrip(
                                  photos: _photos,
                                  canAdd: room > 0,
                                  busy: _picking,
                                  onAdd: _addPhotos,
                                  onAddVideo: _photos.isEmpty
                                      ? _addVideo
                                      : null,
                                  onRemove: (draft) =>
                                      setState(() => _photos.remove(draft)),
                                  onDescribe: (draft) =>
                                      unawaited(_describe(only: draft)),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SettingsGroup(
                        separatorIndent: 58,
                        children: [
                          if (_photos.isEmpty && _video == null)
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
                          if (canRemind)
                            SettingsRow(
                              key: const ValueKey('moment-mention'),
                              icon: Icons.alternate_email_rounded,
                              tone: _mentioned.isEmpty
                                  ? SettingsTone.neutral
                                  : SettingsTone.accent,
                              title: tr('Remind who to read'),
                              subtitle: _mentioned.isEmpty
                                  ? null
                                  : momentMentionSummary(_mentioned, friends),
                              onTap: _chooseMentions,
                            ),
                          if (_photos.isNotEmpty)
                            SettingsRow(
                              key: const ValueKey('moment-describe'),
                              icon: Icons.short_text_rounded,
                              tone: described == _photos.length
                                  ? SettingsTone.accent
                                  : SettingsTone.neutral,
                              title: _photos.length == 1
                                  ? tr('Describe picture')
                                  : tr('Describe pictures'),
                              value: described == 0
                                  ? null
                                  : _photos.length == 1
                                  ? tr('Described')
                                  : tr('{done} of {total} described', {
                                      'done': described,
                                      'total': _photos.length,
                                    }),
                              onTap: () => unawaited(_describe()),
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
                      if (_posting && _video != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                          child: Text(
                            _uploadProgress == null
                                ? tr('Uploading video…')
                                : tr('Uploading video… {percent}%', {
                                    'percent': (_uploadProgress! * 100).round(),
                                  }),
                            key: const ValueKey('moment-upload-progress'),
                            style: TextStyle(fontSize: 13.5, color: c.muted),
                          ),
                        ),
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
                          '${tr('Photos are kept private and scaled down before they are sent.')} '
                          '${tr('Or add one video of up to 3 minutes and 50 MB.')}',
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
    required this.onDescribe,
    this.onAddVideo,
  });

  final List<MomentPhotoDraft> photos;
  final bool canAdd;
  final bool busy;
  final VoidCallback onAdd;

  /// Offered while there are no photos: a Moment has photos or a video.
  final VoidCallback? onAddVideo;
  final ValueChanged<MomentPhotoDraft> onRemove;

  /// Asks what the photo shows.
  final ValueChanged<MomentPhotoDraft> onDescribe;

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
                    WeCordPressable(
                      key: ValueKey('moment-draft-describe-$index'),
                      onPressed: () => onDescribe(draft),
                      pressedScale: 0.97,
                      semanticLabel: draft.alt == null
                          ? tr('Describe photo {number}', {'number': index + 1})
                          : tr('Photo {number} described: {description}', {
                              'number': index + 1,
                              'description': draft.alt,
                            }),
                      excludeSemantics: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(WeCordRadii.sm),
                      ),
                      builder: (context, states) => ClipRRect(
                        borderRadius: BorderRadius.circular(WeCordRadii.sm),
                        child: Image.memory(
                          draft.thumb,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: ImageAltBadge(
                        key: ValueKey('moment-draft-alt-$index'),
                        described: draft.alt != null,
                        compact: true,
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
            if (onAddVideo != null)
              SizedBox(
                width: side,
                height: side,
                child: WeCordPressable(
                  key: const ValueKey('moment-add-video'),
                  onPressed: busy ? null : onAddVideo,
                  pressedScale: 0.97,
                  semanticLabel: tr('Add a video'),
                  excludeSemantics: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  ),
                  builder: (context, states) => Container(
                    decoration: BoxDecoration(
                      color: c.raised,
                      borderRadius: BorderRadius.circular(WeCordRadii.sm),
                    ),
                    child: Icon(
                      Icons.videocam_outlined,
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

/// The video being posted: its poster frame, the length, and a remove button.
class _VideoDraftTile extends StatelessWidget {
  const _VideoDraftTile({
    required this.video,
    required this.locked,
    required this.onRemove,
  });

  final MomentVideoDraft video;
  final bool locked;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ratio = video.height == 0
        ? 16 / 9
        : (video.width / video.height).clamp(0.7, 1.8);
    final length = MomentVideo(
      path: '',
      poster: '',
      thumb: '',
      duration: video.duration,
    ).durationLabel;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        key: const ValueKey('moment-video-draft'),
        width: 240,
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  video.posterThumb,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  semanticLabel: tr('Video, {length}', {'length': length}),
                ),
                const Center(child: MomentPlayBadge()),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: MomentLengthChip(label: length),
                ),
                if (!locked)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: WeCordIconButton(
                      key: const ValueKey('moment-video-remove'),
                      icon: Icons.close_rounded,
                      tooltip: tr('Remove video'),
                      size: 28,
                      iconSize: 15,
                      variant: WeCordButtonVariant.primary,
                      onPressed: onRemove,
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

/// Under the text: the topics the text already has, and a few friends use
/// that one press adds.
class _TopicSuggestions extends ConsumerWidget {
  const _TopicSuggestions({
    required this.text,
    required this.enabled,
    required this.onPick,
  });

  final String text;
  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final written = extractHashtags(text);
    final used = ref.watch(momentsTopicsProvider).value ?? const [];
    final offered = [
      for (final topic in used)
        if (!written.contains(topic.tag)) topic.tag,
    ].take(5).toList();
    if (written.isEmpty && offered.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        key: const ValueKey('moment-topics'),
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tag in written)
            WeCordChip(
              label: '#$tag',
              height: 28,
              selected: true,
              semanticLabel: tr('Topic {tag}', {'tag': tag}),
            ),
          if (enabled)
            for (final tag in offered)
              WeCordChip(
                label: '#$tag',
                height: 28,
                semanticLabel: tr('Add topic {tag}', {'tag': tag}),
                onPressed: () => onPick(tag),
              ),
        ],
      ),
    );
  }
}
