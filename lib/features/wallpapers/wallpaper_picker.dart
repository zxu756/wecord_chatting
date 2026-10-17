import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/file_picker_service.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/wallpapers/wallpaper_backdrop.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_painter.dart';
import 'package:wecord/features/wallpapers/wallpaper_presets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the wallpaper is called: "None", the built-in's name or "Photo".
String wallpaperLabel(ChatWallpaper wallpaper) {
  if (wallpaper.isPreset) {
    return wallpaperPresetById(wallpaper.presetId)?.label() ?? tr('None');
  }
  if (wallpaper.isPhoto) {
    return tr('Photo');
  }
  return tr('None');
}

/// Opens the wallpaper picker: for [conversationId]'s chat alone, or, with
/// none, for the default every chat without its own wallpaper uses.
Future<void> showWallpaperPicker(
  BuildContext context, {
  String? conversationId,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Chat wallpaper'),
    detents: const [0.7, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) => WallpaperPicker(
      conversationId: conversationId,
      scrollController: scrollController,
    ),
  );
}

/// The path a photo that is chosen but not uploaded yet stands under.
const _pendingPath = '(new photo)';

class _PendingPhoto {
  const _PendingPhoto(this.photo);

  final WallpaperPhoto photo;
}

/// A grid of wallpapers with a live preview behind two sample bubbles, a
/// photo with a dim slider and a blur switch, and Apply / Cancel.
class WallpaperPicker extends ConsumerStatefulWidget {
  const WallpaperPicker({
    this.conversationId,
    this.scrollController,
    super.key,
  });

  /// The chat the wallpaper is for; null picks the default.
  final String? conversationId;
  final ScrollController? scrollController;

  @override
  ConsumerState<WallpaperPicker> createState() => _WallpaperPickerState();
}

class _WallpaperPickerState extends ConsumerState<WallpaperPicker> {
  late final ChatWallpaper _initial;
  late final bool _hasOwn;
  late ChatWallpaper _choice;
  _PendingPhoto? _pending;
  var _busy = false;
  var _preparing = false;
  String? _error;

  String? get _conversationId => widget.conversationId;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(wallpapersProvider).settings;
    final id = _conversationId;
    _hasOwn = id != null && settings.hasOwn(id);
    _initial = id == null
        ? (settings.defaultWallpaper ?? const ChatWallpaper.none())
        : settings.effective(id);
    _choice = _initial;
    // Pick up a change made on another device.
    unawaited(ref.read(wallpapersProvider.notifier).refresh());
  }

  bool get _changed => _choice != _initial;

  /// The photo the preview draws: the one just chosen, or the saved one.
  WallpaperPhoto? _previewPhoto() {
    if (!_choice.isPhoto) {
      return null;
    }
    if (_choice.photoPath == _pendingPath) {
      return _pending?.photo;
    }
    return ref.watch(wallpaperPhotoProvider(_choice.photoPath!)).value;
  }

  void _select(ChatWallpaper wallpaper) {
    setState(() {
      _choice = wallpaper;
      _error = null;
    });
  }

  void _selectPhoto() {
    final pending = _pending;
    if (pending != null) {
      _select(
        ChatWallpaper.photo(
          _pendingPath,
          dim: _choice.isPhoto ? _choice.dim : defaultPhotoDim,
          blur: _choice.isPhoto && _choice.blur,
          focusX: _choice.isPhoto ? _choice.focusX : 0,
          focusY: _choice.isPhoto ? _choice.focusY : 0,
        ),
      );
    } else if (_initial.isPhoto) {
      _select(_initial);
    } else {
      unawaited(_pickPhoto(files: false));
    }
  }

  Future<void> _pickPhoto({required bool files}) async {
    if (_preparing || _busy) {
      return;
    }
    setState(() => _error = null);
    try {
      Uint8List? bytes;
      var name = 'photo';
      if (files) {
        final file = await ref.read(chatFilePickerServiceProvider).pickFile();
        if (file != null) {
          if (!file.mimeType.startsWith('image/')) {
            throw const WallpaperPhotoException();
          }
          bytes = file.bytes;
          name = file.name;
        }
      } else {
        final image = await ref.read(imagePickerServiceProvider).pickImage();
        if (image != null) {
          bytes = image.bytes;
          name = image.fileName;
        }
      }
      if (bytes == null || !mounted) {
        return;
      }
      setState(() => _preparing = true);
      final prepared = await prepareWallpaperPhoto(bytes, fileName: name);
      final size = await readPhotoSize(prepared);
      if (!mounted) {
        return;
      }
      if (size == null) {
        throw const WallpaperPhotoException();
      }
      setState(() {
        _pending = _PendingPhoto(
          WallpaperPhoto(bytes: prepared, width: size.$1, height: size.$2),
        );
        _choice = ChatWallpaper.photo(
          _pendingPath,
          dim: _choice.isPhoto ? _choice.dim : defaultPhotoDim,
          blur: _choice.isPhoto && _choice.blur,
        );
      });
    } on Object {
      if (mounted) {
        setState(() => _error = tr('Could not use that picture. Try another.'));
      }
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
      }
    }
  }

  void _movePhoto(double dx, double dy) {
    if (!_choice.isPhoto) {
      return;
    }
    setState(() {
      _choice = _choice.copyWith(
        focusX: (_choice.focusX + dx).clamp(-1.0, 1.0),
        focusY: (_choice.focusY + dy).clamp(-1.0, 1.0),
      );
    });
  }

  Future<void> _apply() async {
    if (_busy) {
      return;
    }
    final controller = ref.read(wallpapersProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? uploaded;
    try {
      var wallpaper = _choice;
      if (wallpaper.isPhoto && wallpaper.photoPath == _pendingPath) {
        uploaded = await controller.uploadPhoto(_pending!.photo.bytes);
        wallpaper = ChatWallpaper.photo(
          uploaded,
          dim: wallpaper.dim,
          blur: wallpaper.blur,
          focusX: wallpaper.focusX,
          focusY: wallpaper.focusY,
        );
      }
      if (wallpaper.isNone && _conversationId == null) {
        await controller.reset(null);
      } else {
        await controller.set(_conversationId, wallpaper);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      if (uploaded != null) {
        unawaited(controller.discardPhoto(uploaded));
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr("Couldn't change the wallpaper. Try again.");
        });
      }
    }
  }

  Future<void> _useDefault() async {
    final id = _conversationId;
    if (id == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(wallpapersProvider.notifier).reset(id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr("Couldn't change the wallpaper. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final photo = _previewPhoto();
    final choosingPhoto = _choice.isPhoto;
    final touch = usesTouchInput(context);
    final allowed = wallpapersAllowed(context);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.subtle,
        ),
      ),
    );

    final list = ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                  child: Text(
                    _conversationId == null
                        ? tr(
                            'Used in every chat without its own wallpaper. '
                            'Only you see it.',
                          )
                        : tr('Only for this chat. Only you see it.'),
                    style: TextStyle(fontSize: 13.5, color: c.muted),
                  ),
                ),
                _WallpaperPreview(
                  wallpaper: _choice,
                  photo: photo,
                  loadingPhoto: choosingPhoto && photo == null,
                  preparing: _preparing,
                  onMove: _movePhoto,
                ),
                if (!allowed)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      tr(
                        'Wallpapers stay hidden while High contrast is on or '
                        'Glass effects are off.',
                      ),
                      key: const ValueKey('wallpaper-hidden-note'),
                      style: TextStyle(fontSize: 12.5, color: c.warningText),
                    ),
                  ),
                label(tr('Choose')),
                _WallpaperGrid(
                  choice: _choice,
                  hasPhoto: _pending != null || _initial.isPhoto,
                  photoThumb: photo,
                  onNone: () => _select(const ChatWallpaper.none()),
                  onPreset: (preset) =>
                      _select(ChatWallpaper.preset(preset.id)),
                  onPhoto: _selectPhoto,
                ),
                if (choosingPhoto) ...[
                  label(tr('Photo')),
                  _PhotoControls(
                    wallpaper: _choice,
                    touch: touch,
                    busy: _preparing || _busy,
                    onChanged: _select,
                    onPickPhotos: () => _pickPhoto(files: false),
                    onPickFiles: () => _pickPhoto(files: true),
                    onMove: _movePhoto,
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const ValueKey('wallpaper-error'),
                        style: TextStyle(fontSize: 13.5, color: c.dangerText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    final actions = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasOwn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WeCordButton(
                      key: const ValueKey('wallpaper-use-default'),
                      label: tr('Use default'),
                      icon: Icons.restart_alt_rounded,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: _busy ? null : _useDefault,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: WeCordButton(
                        key: const ValueKey('wallpaper-cancel'),
                        label: tr('Cancel'),
                        variant: WeCordButtonVariant.secondary,
                        size: WeCordButtonSize.large,
                        expand: true,
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WeCordButton(
                        key: const ValueKey('wallpaper-apply'),
                        label: tr('Apply'),
                        size: WeCordButtonSize.large,
                        expand: true,
                        loading: _busy,
                        onPressed: _busy || _preparing || !_changed
                            ? null
                            : _apply,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      children: [
        Expanded(child: list),
        actions,
      ],
    );
  }
}

/// The wallpaper behind two sample bubbles: what the chat will look like.
/// Drag it to position a photo.
class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({
    required this.wallpaper,
    required this.photo,
    required this.loadingPhoto,
    required this.preparing,
    required this.onMove,
  });

  final ChatWallpaper wallpaper;
  final WallpaperPhoto? photo;
  final bool loadingPhoto;
  final bool preparing;
  final void Function(double dx, double dy) onMove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final active =
        !wallpaper.isNone &&
        (wallpaper.isPreset
            ? wallpaperPresetById(wallpaper.presetId) != null
            : true);
    final bubbleText = TextStyle(fontSize: 15, height: 1.4);

    Widget bubble(String text, {required bool outgoing}) {
      return Align(
        alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: outgoing
                ? WallpaperSurfaces.outgoingBubble(tokens)
                : active
                ? WallpaperSurfaces.incomingBubble(tokens)
                : c.raised,
            borderRadius: chatBubbleRadius(
              outgoing: outgoing,
              joinsAbove: false,
              joinsBelow: false,
            ),
            boxShadow: active ? WallpaperSurfaces.bubbleShadow(tokens) : null,
          ),
          child: Text(
            text,
            style: bubbleText.copyWith(color: outgoing ? c.onInk : c.ink),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: tr('Preview'),
      customSemanticsActions: wallpaper.isPhoto
          ? {
              CustomSemanticsAction(label: tr('Move photo left')): () =>
                  onMove(-0.25, 0),
              CustomSemanticsAction(label: tr('Move photo right')): () =>
                  onMove(0.25, 0),
              CustomSemanticsAction(label: tr('Move photo up')): () =>
                  onMove(0, -0.25),
              CustomSemanticsAction(label: tr('Move photo down')): () =>
                  onMove(0, 0.25),
            }
          : null,
      child: GestureDetector(
        key: const ValueKey('wallpaper-preview'),
        onPanUpdate: wallpaper.isPhoto
            ? (details) {
                final size = context.size ?? const Size(300, 220);
                onMove(
                  -details.delta.dx / (size.width / 2),
                  -details.delta.dy / (size.height / 2),
                );
              }
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
            border: Border.all(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: ChatWallpaperScope(
            wallpaper: wallpaper,
            active: active,
            photo: photo,
            photoLoading: loadingPhoto,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ChatWallpaperBackdrop(
                    boundaryKey: ValueKey('wallpaper-preview-picture'),
                  ),
                ),
                // As tall as its content needs (large text grows it).
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 208),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: WallpaperPill(
                              child: Text(
                                tr('Today'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          bubble(
                            tr('Hey! Are we still on for Friday?'),
                            outgoing: false,
                          ),
                          const SizedBox(height: 6),
                          bubble(tr('Yes, see you there!'), outgoing: true),
                        ],
                      ),
                    ),
                  ),
                ),
                if (preparing)
                  Positioned.fill(
                    child: Container(
                      color: c.panel.withValues(alpha: 0.7),
                      alignment: Alignment.center,
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: c.muted,
                        ),
                      ),
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

class _WallpaperGrid extends StatelessWidget {
  const _WallpaperGrid({
    required this.choice,
    required this.hasPhoto,
    required this.photoThumb,
    required this.onNone,
    required this.onPreset,
    required this.onPhoto,
  });

  final ChatWallpaper choice;
  final bool hasPhoto;
  final WallpaperPhoto? photoThumb;
  final VoidCallback onNone;
  final ValueChanged<WallpaperPreset> onPreset;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final brightness = context.tokens.brightness;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480 ? 6 : 5;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        Widget tile({
          required Key key,
          required String name,
          required bool selected,
          required VoidCallback onPressed,
          required Widget face,
        }) {
          return SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WeCordPressable(
                  key: key,
                  onPressed: onPressed,
                  selected: selected,
                  semanticLabel: tr('{name} wallpaper', {'name': name}),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  ),
                  builder: (context, states) => AspectRatio(
                    aspectRatio: 0.78,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(WeCordRadii.lg),
                            border: Border.all(
                              color: selected ? c.accent : c.line,
                              width: selected ? 2.5 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(selected ? 3 : 1),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                WeCordRadii.lg - 3,
                              ),
                              child: face,
                            ),
                          ),
                        ),
                        if (selected)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: c.onAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.ink : c.muted,
                  ),
                ),
              ],
            ),
          );
        }

        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            tile(
              key: const ValueKey('wallpaper-none'),
              name: tr('None'),
              selected: choice.isNone,
              onPressed: onNone,
              face: ColoredBox(
                color: c.panel,
                child: Center(
                  child: Icon(
                    Icons.format_color_reset_outlined,
                    size: 22,
                    color: c.faint,
                  ),
                ),
              ),
            ),
            for (final preset in wallpaperPresets)
              tile(
                key: ValueKey('wallpaper-${preset.id}'),
                name: preset.label(),
                selected: choice.isPreset && choice.presetId == preset.id,
                onPressed: () => onPreset(preset),
                face: CustomPaint(
                  painter: WallpaperPainter(
                    preset: preset,
                    brightness: brightness,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            tile(
              key: const ValueKey('wallpaper-photo'),
              name: tr('Photo'),
              selected: choice.isPhoto,
              onPressed: onPhoto,
              face: photoThumb != null && choice.isPhoto
                  ? Image.memory(
                      photoThumb!.bytes,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      gaplessPlayback: true,
                    )
                  : ColoredBox(
                      color: c.raised,
                      child: Center(
                        child: Icon(
                          hasPhoto
                              ? Icons.image_rounded
                              : Icons.add_photo_alternate_outlined,
                          size: 24,
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

/// A photo's dim (dark theme), blur and where it sits, and choosing another.
class _PhotoControls extends StatelessWidget {
  const _PhotoControls({
    required this.wallpaper,
    required this.touch,
    required this.busy,
    required this.onChanged,
    required this.onPickPhotos,
    required this.onPickFiles,
    required this.onMove,
  });

  final ChatWallpaper wallpaper;
  final bool touch;
  final bool busy;
  final ValueChanged<ChatWallpaper> onChanged;
  final VoidCallback onPickPhotos;
  final VoidCallback onPickFiles;
  final void Function(double dx, double dy) onMove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final percent = (wallpaper.dim.clamp(minPhotoDim, maxPhotoDim) * 100)
        .round();
    return SettingsGroup(
      color: c.well,
      separatorIndent: 14,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Dim in dark mode'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Slider(
                key: const ValueKey('wallpaper-dim'),
                value: wallpaper.dim.clamp(minPhotoDim, maxPhotoDim),
                min: minPhotoDim,
                max: maxPhotoDim,
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()}%',
                onChanged: (value) => onChanged(wallpaper.copyWith(dim: value)),
              ),
            ],
          ),
        ),
        SettingsRow.toggle(
          key: const ValueKey('wallpaper-blur'),
          title: tr('Blur'),
          value: wallpaper.blur,
          onChanged: (value) => onChanged(wallpaper.copyWith(blur: value)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Drag the preview to position the photo.'),
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WeCordButton(
                    key: const ValueKey('wallpaper-choose-photo'),
                    label: touch
                        ? tr('From Photos')
                        : tr('Choose another photo'),
                    icon: Icons.photo_library_outlined,
                    variant: WeCordButtonVariant.secondary,
                    size: WeCordButtonSize.small,
                    onPressed: busy ? null : onPickPhotos,
                  ),
                  if (touch)
                    WeCordButton(
                      key: const ValueKey('wallpaper-choose-file'),
                      label: tr('From Files'),
                      icon: Icons.folder_open_rounded,
                      variant: WeCordButtonVariant.secondary,
                      size: WeCordButtonSize.small,
                      onPressed: busy ? null : onPickFiles,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
