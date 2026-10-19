import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/moments/moment_audience_sheet.dart';
import 'package:wecord/features/moments/moment_photos.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/features/moments/moments_video.dart';
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/features/stories/close_friends_sheet.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/features/stories/story_media_picker.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Starts a new daily: asks where the photo or video comes from, picks it,
/// opens the photo editor for a photo, and then the composer. Does nothing
/// when the person cancels at any step.
Future<void> openStoryComposer(BuildContext context, WidgetRef ref) async {
  final picker = ref.read(storyMediaPickerProvider);
  final choice = await showWeCordSheet<_Source>(
    context,
    title: tr('New daily'),
    useRootNavigator: true,
    builder: (sheetContext, _) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SettingsGroup(
        color: sheetContext.tokens.colors.well,
        children: [
          if (picker.hasCamera)
            SettingsRow(
              key: const ValueKey('story-source-camera-photo'),
              icon: Icons.photo_camera_outlined,
              tone: SettingsTone.accent,
              title: tr('Take a photo'),
              showChevron: false,
              onTap: () => Navigator.of(sheetContext).pop(_Source.cameraPhoto),
            ),
          if (picker.hasCamera)
            SettingsRow(
              key: const ValueKey('story-source-camera-video'),
              icon: Icons.videocam_outlined,
              tone: SettingsTone.accent,
              title: tr('Record a video'),
              subtitle: tr('Up to 15 seconds'),
              showChevron: false,
              onTap: () => Navigator.of(sheetContext).pop(_Source.cameraVideo),
            ),
          SettingsRow(
            key: const ValueKey('story-source-photo'),
            icon: Icons.photo_outlined,
            tone: SettingsTone.success,
            title: tr('Photo from library'),
            showChevron: false,
            onTap: () => Navigator.of(sheetContext).pop(_Source.photo),
          ),
          SettingsRow(
            key: const ValueKey('story-source-video'),
            icon: Icons.video_library_outlined,
            tone: SettingsTone.success,
            title: tr('Video from library'),
            subtitle: tr('Up to 15 seconds and 20 MB'),
            showChevron: false,
            onTap: () => Navigator.of(sheetContext).pop(_Source.video),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  try {
    switch (choice) {
      case _Source.photo || _Source.cameraPhoto:
        final photo = await picker.pickPhoto(
          camera: choice == _Source.cameraPhoto,
        );
        if (photo == null || !context.mounted) {
          return;
        }
        final edit = await Navigator.of(context, rootNavigator: true)
            .push<PhotoEditResult>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => PhotoEditorScreen(
                  sourceBytes: photo.bytes,
                  fileName: photo.fileName,
                  maxEdge: momentPhotoEdge,
                  quality: 82,
                ),
              ),
            );
        if (edit == null || !context.mounted) {
          return;
        }
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute(
            builder: (_) => StoryComposerScreen(photo: photo, edit: edit),
          ),
        );
      case _Source.video || _Source.cameraVideo:
        final video = await picker.pickVideo(
          camera: choice == _Source.cameraVideo,
        );
        if (video == null || !context.mounted) {
          return;
        }
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute(builder: (_) => StoryComposerScreen(video: video)),
        );
    }
  } on MomentVideoException catch (problem) {
    if (context.mounted) {
      _snack(context, _videoProblemText(problem.problem));
    }
  } on Object {
    if (context.mounted) {
      _snack(context, tr('Could not use that file. Try another.'));
    }
  }
}

enum _Source { cameraPhoto, cameraVideo, photo, video }

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String _videoProblemText(MomentVideoProblem problem) => switch (problem) {
  MomentVideoProblem.tooLong => tr(
    'That video is longer than 15 seconds. Choose a shorter one.',
  ),
  MomentVideoProblem.tooBig => tr(
    'That video is bigger than 20 MB. Choose a smaller one.',
  ),
  MomentVideoProblem.unsupported => tr('Choose an MP4, MOV or WebM video.'),
  MomentVideoProblem.unreadable => tr(
    'Could not read that video. Try another.',
  ),
};

/// New daily: the picture or video, a caption, who can see it and Post. It
/// is sent with an id made here, so trying again after a failure never posts
/// it twice.
class StoryComposerScreen extends ConsumerStatefulWidget {
  const StoryComposerScreen({this.photo, this.edit, this.video, super.key})
    : assert((photo == null) != (video == null), 'a photo or a video');

  final PickedStoryPhoto? photo;

  /// What the photo editor made of [photo] (null photo inside: unchanged).
  final PhotoEditResult? edit;
  final MomentVideoDraft? video;

  @override
  ConsumerState<StoryComposerScreen> createState() =>
      _StoryComposerScreenState();
}

class _StoryComposerScreenState extends ConsumerState<StoryComposerScreen> {
  final _caption = TextEditingController();
  final _id = newStoryId();
  PhotoEditResult? _edit;
  var _audience = MomentAudience.everyone;
  var _posting = false;
  double? _uploadProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _edit = widget.edit;
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  bool get _canPost => !_posting && _audience.isComplete;

  Uint8List? get _previewBytes {
    final photo = widget.photo;
    if (photo == null) {
      return widget.video?.posterThumb;
    }
    return _edit?.photo?.bytes ?? photo.bytes;
  }

  Future<void> _editPhoto() async {
    final photo = widget.photo;
    if (photo == null || _posting) {
      return;
    }
    final result = await Navigator.of(context, rootNavigator: true)
        .push<PhotoEditResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PhotoEditorScreen(
              sourceBytes: photo.bytes,
              fileName: photo.fileName,
              initial: _edit?.document,
              maxEdge: momentPhotoEdge,
              quality: 82,
            ),
          ),
        );
    if (result != null && mounted) {
      setState(() => _edit = result);
    }
  }

  Future<void> _editCloseFriends() async {
    await showCloseFriendsSheet(context);
  }

  Future<void> _chooseAudience() async {
    final picked = await showMomentAudienceSheet(
      context,
      current: _audience,
      onEditCloseFriends: _editCloseFriends,
    );
    if (picked != null && mounted) {
      setState(() => _audience = picked);
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      if (_audience.visibility == MomentVisibility.close &&
          (await ref.read(closeFriendsProvider.future)).isEmpty) {
        if (mounted) {
          setState(() {
            _posting = false;
            _error = tr('Choose your close friends first.');
          });
        }
        return;
      }
      MomentPhotoDraft? photoDraft;
      final picked = widget.photo;
      if (picked != null) {
        photoDraft = await prepareMomentPhoto(
          id: _id,
          bytes: _edit?.photo?.bytes ?? picked.bytes,
          fileName: picked.fileName,
        );
        if (photoDraft == null) {
          throw StateError('The picture could not be read');
        }
      }
      await ref
          .read(storiesRepositoryProvider)
          .create(
            id: _id,
            photo: photoDraft,
            video: widget.video,
            caption: _caption.text.trim(),
            audience: _audience,
            onUploadProgress: (progress) {
              if (mounted) {
                setState(() => _uploadProgress = progress);
              }
            },
          );
      ref
        ..invalidate(storiesTrayProvider)
        ..invalidate(authorStoriesProvider);
      if (mounted) {
        navigator.pop();
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tr('Your daily is up.'))));
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
    final video = widget.video;
    final preview = _previewBytes;
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
                  title: tr('New daily'),
                  actions: [
                    WeCordButton(
                      key: const ValueKey('story-post'),
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
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 260,
                            maxHeight: 420,
                          ),
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                WeCordRadii.xl,
                              ),
                              child: ColoredBox(
                                key: const ValueKey('story-preview'),
                                color: Colors.black,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (preview != null)
                                      Image.memory(
                                        preview,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                        semanticLabel: video != null
                                            ? tr('Video, {length}', {
                                                'length': MomentVideo(
                                                  path: '',
                                                  poster: '',
                                                  thumb: '',
                                                  duration: video.duration,
                                                ).durationLabel,
                                              })
                                            : tr('Your photo'),
                                      ),
                                    if (video != null)
                                      const Center(child: MomentPlayBadge()),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.photo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Center(
                            child: WeCordButton(
                              key: const ValueKey('story-edit-photo'),
                              label: tr('Edit photo'),
                              icon: Icons.tune_rounded,
                              size: WeCordButtonSize.small,
                              variant: WeCordButtonVariant.secondary,
                              onPressed: _posting ? null : _editPhoto,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Container(
                        // At least a tap target tall.
                        constraints: const BoxConstraints(minHeight: 52),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        decoration: BoxDecoration(
                          color: c.panel,
                          borderRadius: BorderRadius.circular(WeCordRadii.xl),
                        ),
                        child: TextField(
                          key: const ValueKey('story-caption-field'),
                          controller: _caption,
                          enabled: !_posting,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: maxStoryCaption,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(maxStoryCaption),
                          ],
                          buildCounter:
                              (
                                context, {
                                required currentLength,
                                required isFocused,
                                required maxLength,
                              }) => currentLength > maxStoryCaption * 0.8
                              ? Text(
                                  '$currentLength / $maxLength',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.subtle,
                                  ),
                                )
                              : null,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: c.ink,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: tr('Add a caption'),
                            hintStyle: TextStyle(fontSize: 16, color: c.subtle),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SettingsGroup(
                        separatorIndent: 58,
                        children: [
                          SettingsRow(
                            key: const ValueKey('story-audience'),
                            icon: Icons.visibility_outlined,
                            tone:
                                _audience.visibility == MomentVisibility.friends
                                ? SettingsTone.neutral
                                : SettingsTone.accent,
                            title: tr('Who can see this'),
                            subtitle: summary,
                            onTap: _posting ? null : _chooseAudience,
                          ),
                        ],
                      ),
                      if (_posting && video != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                          child: Text(
                            _uploadProgress == null
                                ? tr('Uploading video…')
                                : tr('Uploading video… {percent}%', {
                                    'percent': (_uploadProgress! * 100).round(),
                                  }),
                            key: const ValueKey('story-upload-progress'),
                            style: TextStyle(fontSize: 13.5, color: c.muted),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                          child: Text(
                            _error!,
                            key: const ValueKey('story-error'),
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
                            'A daily disappears after 24 hours. You can see who viewed it; nobody else can.',
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
