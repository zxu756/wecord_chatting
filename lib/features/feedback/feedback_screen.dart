import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/features/feedback/feedback_repository.dart';
import 'package:wecord/features/photo_editor/editor_model.dart'
    show EditorDocument;
import 'package:wecord/features/photo_editor/photo_editor_screen.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The longest side of a screenshot that is sent, and its JPEG quality:
/// enough to read a screen, small enough to upload anywhere.
const feedbackScreenshotEdge = 1600;
const feedbackScreenshotQuality = 80;

/// Turns the picture a person chose into the JPEG that is uploaded: scaled
/// down, and with its metadata (place, camera) left out. Null when it cannot
/// be read as a picture. Tests swap in their own.
typedef FeedbackScreenshotPreparer =
    Future<Uint8List?> Function(Uint8List bytes, String fileName);

final feedbackScreenshotPreparerProvider = Provider<FeedbackScreenshotPreparer>(
  (ref) => (bytes, fileName) async {
    final prepared = await prepareJpegPhoto(
      bytes: bytes,
      fileName: fileName,
      maxEdge: feedbackScreenshotEdge,
      quality: feedbackScreenshotQuality,
    );
    return prepared?.bytes;
  },
);

/// Settings, Feedback and help (K7): a message and, if the person wants, a
/// screenshot, which they see and can cover with the photo editor's mosaic
/// before it is sent. The app adds its version and platform and nothing else;
/// no chat is read or attached. At most a few messages an hour.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  static const messageKey = ValueKey('feedback-message');
  static const addScreenshotKey = ValueKey('feedback-add-screenshot');
  static const editScreenshotKey = ValueKey('feedback-edit-screenshot');
  static const removeScreenshotKey = ValueKey('feedback-remove-screenshot');
  static const sendKey = ValueKey('feedback-send');
  static const doneKey = ValueKey('feedback-done');

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _message = TextEditingController();

  /// The screenshot as prepared, before any edits.
  Uint8List? _source;

  /// What the mosaic and the other edits did, to carry on from.
  EditorDocument? _edits;

  /// The screenshot as it will be sent (the edited one, else the source).
  Uint8List? _shown;
  var _picking = false;
  var _sending = false;
  var _sent = false;
  String? _problem;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && !_picking && _message.text.trim().isNotEmpty;

  Future<void> _addScreenshot() async {
    if (_picking) {
      return;
    }
    setState(() {
      _picking = true;
      _problem = null;
    });
    try {
      final ChatImageUpload? picked = await ref
          .read(imagePickerServiceProvider)
          .pickImage();
      if (picked == null || !mounted) {
        return;
      }
      final prepared = await ref.read(feedbackScreenshotPreparerProvider)(
        picked.bytes,
        picked.fileName,
      );
      if (!mounted) {
        return;
      }
      if (prepared == null) {
        setState(
          () => _problem = tr('That picture could not be read. Try another.'),
        );
        return;
      }
      setState(() {
        _source = prepared;
        _shown = prepared;
        _edits = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _problem = errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _hidePrivateParts() async {
    final source = _source;
    if (source == null) {
      return;
    }
    final result = await Navigator.of(context, rootNavigator: true)
        .push<PhotoEditResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PhotoEditorScreen(
              sourceBytes: source,
              fileName: 'screenshot.jpg',
              initial: _edits,
              maxEdge: feedbackScreenshotEdge,
              quality: feedbackScreenshotQuality,
            ),
          ),
        );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _edits = result.document;
      // Nothing changed or everything was taken back: the picture as it was.
      _shown = result.photo?.bytes ?? source;
    });
  }

  void _removeScreenshot() {
    setState(() {
      _source = null;
      _shown = null;
      _edits = null;
    });
  }

  Future<void> _send() async {
    if (!_canSend) {
      return;
    }
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            message: _message.text,
            platform: ref.read(appPlatformProvider),
            version: ref.read(appVersionProvider),
            screenshot: _shown,
          );
      if (mounted) {
        setState(() => _sent = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _problem = errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (_sent) {
      return SettingsPage(
        key: const ValueKey('feedback-screen'),
        title: tr('Feedback and help'),
        children: [
          const SizedBox(height: 48),
          const Center(
            child: SettingsIconTile(
              icon: Icons.check_circle_outline_rounded,
              tone: SettingsTone.success,
              size: 64,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr('Thank you, we got it.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('If we reply, the answer shows up in Notifications.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.45),
          ),
          const SizedBox(height: 28),
          WeCordButton(
            key: FeedbackScreen.doneKey,
            label: tr('Done'),
            variant: WeCordButtonVariant.primary,
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }
    final shown = _shown;
    return SettingsPage(
      key: const ValueKey('feedback-screen'),
      title: tr('Feedback and help'),
      children: [
        const SizedBox(height: 8),
        Text(
          tr(
            'Tell us what went wrong, or what you would like. We read '
            'everything.',
          ),
          style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        WeCordTextField(
          fieldKey: FeedbackScreen.messageKey,
          controller: _message,
          label: tr('Your message'),
          hint: tr('What happened?'),
          onPaper: true,
          minLines: 5,
          maxLines: 10,
          maxLength: 2000,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (shown == null)
          Align(
            alignment: Alignment.centerLeft,
            child: WeCordButton(
              key: FeedbackScreen.addScreenshotKey,
              label: _picking ? tr('Opening...') : tr('Add a screenshot'),
              icon: Icons.add_photo_alternate_outlined,
              variant: WeCordButtonVariant.secondary,
              onPressed: _picking ? null : () => unawaited(_addScreenshot()),
            ),
          )
        else
          _ScreenshotPreview(
            bytes: shown,
            onHide: () => unawaited(_hidePrivateParts()),
            onRemove: _removeScreenshot,
          ),
        const SizedBox(height: 16),
        Text(
          tr(
            'We add your WeCord version ({version}) and your platform '
            '({platform}). Nothing from your chats is sent.',
            {
              'version': ref.watch(appVersionProvider),
              'platform': ref.watch(appPlatformProvider),
            },
          ),
          style: TextStyle(fontSize: 13, color: c.subtle, height: 1.45),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _problem!,
              key: const ValueKey('feedback-problem'),
              style: TextStyle(fontSize: 14, color: c.dangerText, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 20),
        WeCordButton(
          key: FeedbackScreen.sendKey,
          label: _sending ? tr('Sending...') : tr('Send feedback'),
          variant: WeCordButtonVariant.primary,
          expand: true,
          size: WeCordButtonSize.large,
          onPressed: _canSend ? () => unawaited(_send()) : null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The screenshot as it will go: a picture to look at, a button to cover
/// private parts (mosaic, blur, drawing) and one to take it away.
class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({
    required this.bytes,
    required this.onHide,
    required this.onRemove,
  });

  final Uint8List bytes;
  final VoidCallback onHide;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Image.memory(
                bytes,
                key: const ValueKey('feedback-screenshot-preview'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                semanticLabel: tr('Your screenshot'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr('Cover anything private before you send it.'),
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WeCordButton(
                key: FeedbackScreen.editScreenshotKey,
                label: tr('Hide private parts'),
                icon: Icons.blur_on_rounded,
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.secondary,
                onPressed: onHide,
              ),
              WeCordButton(
                key: FeedbackScreen.removeScreenshotKey,
                label: tr('Remove'),
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.ghost,
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
