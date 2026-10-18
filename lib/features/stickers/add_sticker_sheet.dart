import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/stickers/sticker_cutout.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/features/stickers/sticker_widgets.dart';
import 'package:wecord/features/stickers/user_sticker.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the "Add to stickers" sheet: a preview of the picture that [source]
/// gives, a switch to cut out its subject (where the device can), and the
/// button that saves it. Returns whether a sticker was added.
Future<bool> showAddStickerSheet(
  BuildContext context, {
  required Future<Uint8List> Function() source,
}) async {
  final added = await showWeCordSheet<bool>(
    context,
    title: tr('Add to stickers'),
    builder: (context, _) => AddStickerView(source: source),
  );
  return added == true;
}

/// The content of the "Add to stickers" sheet.
class AddStickerView extends ConsumerStatefulWidget {
  const AddStickerView({required this.source, super.key});

  /// Where the picture comes from (a download, a file the person picked).
  final Future<Uint8List> Function() source;

  @override
  ConsumerState<AddStickerView> createState() => _AddStickerViewState();
}

class _AddStickerViewState extends ConsumerState<AddStickerView> {
  PreparedSticker? _plain;
  PreparedSticker? _cutout;
  Uint8List? _original;
  var _cutOutOn = false;
  var _loading = true;
  var _cutting = false;
  var _saving = false;
  var _madeStill = false;
  String? _error;
  String? _cutoutError;

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
      final bytes = await widget.source();
      final prepared = await prepareSticker(bytes, stillIfTooLarge: true);
      final format = sniffStickerFormat(bytes);
      final wasMoving =
          format != null &&
          format != StickerFormat.png &&
          isAnimatedStickerBytes(bytes, format);
      if (!mounted) {
        return;
      }
      setState(() {
        _original = bytes;
        _plain = prepared;
        _madeStill = wasMoving && !prepared.animated;
        _loading = false;
      });
    } on UserStickerException catch (error) {
      _fail(error.message);
    } catch (_) {
      _fail(tr('Could not open the picture. Try again.'));
    }
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _setCutOut(bool on) async {
    if (!on) {
      setState(() {
        _cutOutOn = false;
        _cutoutError = null;
      });
      return;
    }
    if (_cutout != null) {
      setState(() {
        _cutOutOn = true;
        _cutoutError = null;
      });
      return;
    }
    final original = _original;
    if (original == null || _cutting) {
      return;
    }
    setState(() {
      _cutting = true;
      _cutoutError = null;
    });
    try {
      // The cut-out works on a larger picture than the sticker will be.
      final large = await prepareSticker(
        original,
        maxEdge: userStickerMaxEdge * 2,
        stillIfTooLarge: true,
      );
      final bytes = large.animated
          ? original
          : await ref.read(stickerCutoutProvider).cutOut(large.bytes);
      final result = await prepareSticker(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _cutout = result;
        _cutOutOn = true;
        _cutting = false;
      });
    } on StickerCutoutException catch (error) {
      _cutFailed(switch (error.failure) {
        StickerCutoutFailure.noSubject => tr(
          'No subject stood out in this picture.',
        ),
        StickerCutoutFailure.unavailable => tr(
          'Cutting out is not available here.',
        ),
        _ => tr('Could not cut out the subject. Try again.'),
      });
    } catch (_) {
      _cutFailed(tr('Could not cut out the subject. Try again.'));
    }
  }

  void _cutFailed(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _cutting = false;
      _cutOutOn = false;
      _cutoutError = message;
    });
  }

  Future<void> _save() async {
    final sticker = _cutOutOn ? _cutout : _plain;
    if (sticker == null || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userStickersRepositoryProvider).add(sticker);
      ref.invalidate(userStickersProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on UserStickerException catch (error) {
      _saveFailed(error.message);
    } catch (_) {
      _saveFailed(tr('Could not add the sticker. Try again.'));
    }
  }

  void _saveFailed(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final plain = _plain;
    final shown = _cutOutOn ? (_cutout ?? plain) : plain;
    final canCut =
        (ref.watch(stickerCutoutAvailableProvider).value ?? false) &&
        plain != null &&
        !plain.animated;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox.square(
                dimension: 200,
                child: StickerCheckerboard(
                  child: Center(child: _preview(shown)),
                ),
              ),
            ),
            if (_madeStill) ...[
              const SizedBox(height: 10),
              Text(
                tr(
                  'This animation is over 1 MB, so it is saved as a still picture.',
                ),
                key: const ValueKey('add-sticker-made-still'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
              ),
            ],
            if (canCut) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Cut out the subject'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr('Removes the background on this device.'),
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  if (_cutting)
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    WeCordSwitch(
                      key: const ValueKey('add-sticker-cutout-switch'),
                      value: _cutOutOn,
                      semanticLabel: tr('Cut out the subject'),
                      onChanged: (on) => unawaited(_setCutOut(on)),
                    ),
                ],
              ),
            ],
            if (_cutoutError != null) ...[
              const SizedBox(height: 8),
              Text(
                _cutoutError!,
                key: const ValueKey('add-sticker-cutout-error'),
                style: TextStyle(fontSize: 13, color: c.danger),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const ValueKey('add-sticker-error'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: c.danger),
              ),
            ],
            const SizedBox(height: 18),
            if (_error != null && plain == null)
              WeCordButton(
                key: const ValueKey('add-sticker-retry'),
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                onPressed: () => unawaited(_load()),
              )
            else
              WeCordButton(
                key: const ValueKey('add-sticker-save'),
                label: tr('Add to stickers'),
                loading: _saving,
                onPressed: plain == null || _saving || _cutting ? null : _save,
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview(PreparedSticker? sticker) {
    if (_loading || sticker == null) {
      return _error == null
          ? const CircularProgressIndicator(strokeWidth: 2.5)
          : Icon(
              Icons.broken_image_outlined,
              color: context.tokens.colors.faint,
            );
    }
    return MotionSafeImage(
      image: MemoryImage(sticker.bytes),
      animated: sticker.animated,
      width: 180,
      height: 180,
      fit: BoxFit.contain,
      playButton: false,
      gaplessPlayback: true,
      semanticLabel: tr('Sticker preview'),
    );
  }
}
