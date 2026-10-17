import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/image_text/image_text_cache.dart';
import 'package:wecord/features/image_text/image_text_models.dart';
import 'package:wecord/features/image_text/image_text_recognizer.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens "Copy text from picture" for [file]: reads the text in the picture
/// on the device and shows it with Copy, Select and (where AI is on)
/// Translate. [circleId] is the circle the picture was sent in, for its AI
/// switch.
Future<void> showImageTextSheet(
  BuildContext context, {
  required PreviewFile file,
  String? circleId,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Text from picture'),
    useRootNavigator: true,
    builder: (context, _) => ImageTextSheet(file: file, circleId: circleId),
  );
}

enum _Phase { loading, done, unavailable, noText, unreadable, failed }

enum _TranslatePhase { idle, loading, done, failed }

/// The body of the text-from-picture sheet.
class ImageTextSheet extends ConsumerStatefulWidget {
  const ImageTextSheet({required this.file, this.circleId, super.key});

  final PreviewFile file;
  final String? circleId;

  @override
  ConsumerState<ImageTextSheet> createState() => _ImageTextSheetState();
}

class _ImageTextSheetState extends ConsumerState<ImageTextSheet> {
  var _phase = _Phase.loading;
  String _text = '';
  var _generation = 0;

  final _field = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'image-text');

  var _copied = false;
  Timer? _copiedTimer;

  var _translatePhase = _TranslatePhase.idle;
  String? _translation;
  Object? _translateError;
  var _translationCopied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    _generation++;
    _copiedTimer?.cancel();
    _field.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _read() async {
    final generation = ++_generation;
    setState(() => _phase = _Phase.loading);
    final recognizer = ref.read(imageTextRecognizerProvider);
    if (!recognizer.isSupported) {
      // Nothing is downloaded or sent anywhere: pictures are read on the
      // device or not at all.
      setState(() => _phase = _Phase.unavailable);
      return;
    }
    final file = widget.file;
    final key = imageTextKey(
      messageId: file.messageId,
      storagePath: file.key,
    );
    try {
      final cache = ref.read(imageTextCacheProvider);
      CachedImageText? cached;
      try {
        cached = await cache.read(key);
      } on Object {
        cached = null;
      }
      if (!_current(generation)) {
        return;
      }
      if (cached != null) {
        _show(cached.text);
        return;
      }
      final path = await ref.read(imageTextFetcherProvider)(file);
      final result = await recognizer.recognize(path);
      if (!_current(generation)) {
        return;
      }
      unawaited(_remember(cache, key, result.text));
      _show(result.text);
    } on ImageTextException catch (error) {
      if (!_current(generation)) {
        return;
      }
      if (error.kind == ImageTextFailure.noText) {
        unawaited(_remember(ref.read(imageTextCacheProvider), key, ''));
      }
      setState(
        () => _phase = switch (error.kind) {
          ImageTextFailure.unavailable => _Phase.unavailable,
          ImageTextFailure.noText => _Phase.noText,
          ImageTextFailure.unreadable => _Phase.unreadable,
          ImageTextFailure.failed => _Phase.failed,
        },
      );
    } on Object {
      if (_current(generation)) {
        setState(() => _phase = _Phase.failed);
      }
    }
  }

  Future<void> _remember(ImageTextCache cache, String key, String text) async {
    try {
      await cache.write(
        key,
        CachedImageText(text: text, savedAt: DateTime.now().toUtc()),
      );
    } on Object {
      // Reading it again later is fine.
    }
  }

  void _show(String text) {
    setState(() {
      if (text.trim().isEmpty) {
        _phase = _Phase.noText;
        return;
      }
      _text = text;
      _field.text = text;
      _phase = _Phase.done;
    });
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: _text)));
    WeCordHaptics.light();
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _select() {
    _fieldFocus.requestFocus();
    _field.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _field.text.length,
    );
  }

  Future<void> _translate() async {
    final text = _text;
    setState(() {
      _translatePhase = _TranslatePhase.loading;
      _translationCopied = false;
    });
    try {
      final translated = await ref
          .read(aiRepositoryProvider)
          .translate(
            text: text,
            target: AiLanguage.appLanguage,
            conversationId: widget.file.conversationId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _translation = translated;
        _translatePhase = _TranslatePhase.done;
      });
    } on Object catch (error) {
      if (error is AiNotConfiguredException) {
        ref.invalidate(aiStatusProvider);
      }
      if (mounted) {
        setState(() {
          _translateError = error;
          _translatePhase = _TranslatePhase.failed;
        });
      }
    }
  }

  void _copyTranslation() {
    final translation = _translation;
    if (translation == null) {
      return;
    }
    unawaited(Clipboard.setData(ClipboardData(text: translation)));
    setState(() => _translationCopied = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: switch (_phase) {
            _Phase.loading => [_loading(c)],
            _Phase.done => _done(context),
            _Phase.unavailable => [
              _message(
                c,
                icon: Icons.phone_iphone_rounded,
                title: tr('Available in the iPhone and Mac apps'),
                body: tr(
                  'WeCord reads text in pictures on your device, so nothing is uploaded. Open this picture in the iPhone or Mac app to copy its text.',
                ),
                key: const ValueKey('image-text-unavailable'),
              ),
            ],
            _Phase.noText => [
              _message(
                c,
                icon: Icons.text_fields_rounded,
                title: tr('No text found in this picture'),
                body: tr('Try a sharper picture with larger writing.'),
                key: const ValueKey('image-text-none'),
              ),
            ],
            _Phase.unreadable => [
              _message(
                c,
                icon: Icons.image_not_supported_outlined,
                title: tr("Couldn't read this picture"),
                body: tr("This picture's format can't be read for text."),
                key: const ValueKey('image-text-unreadable'),
              ),
            ],
            _Phase.failed => [
              _message(
                c,
                icon: Icons.error_outline_rounded,
                title: tr("Couldn't read the text. Try again."),
                key: const ValueKey('image-text-failed'),
                action: WeCordButton(
                  key: const ValueKey('image-text-retry'),
                  label: tr('Try again'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: () => unawaited(_read()),
                ),
              ),
            ],
          },
        ),
      ),
    );
  }

  Widget _loading(WeCordPalette c) {
    return Semantics(
      liveRegion: true,
      label: tr('Reading the picture…'),
      child: Padding(
        key: const ValueKey('image-text-loading'),
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: c.ink),
            ),
            const SizedBox(width: 12),
            Text(
              tr('Reading the picture…'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(
    WeCordPalette c, {
    required IconData icon,
    required String title,
    String? body,
    Widget? action,
    Key? key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 28, color: c.muted),
          ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: c.ink,
              ),
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }

  List<Widget> _done(BuildContext context) {
    final c = context.tokens.colors;
    final aiAvailable = ref.watch(aiAvailableProvider(widget.circleId));
    return [
      Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Semantics(
          label: tr('Text from picture'),
          child: TextField(
            key: const ValueKey('image-text-field'),
            controller: _field,
            focusNode: _fieldFocus,
            readOnly: true,
            minLines: 1,
            maxLines: 12,
            style: TextStyle(fontSize: 16, height: 1.45, color: c.ink),
            decoration: const InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        tr('Read on your device. The picture was not uploaded.'),
        style: TextStyle(fontSize: 12.5, color: c.subtle),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          WeCordButton(
            key: const ValueKey('image-text-copy'),
            label: _copied ? tr('Copied') : tr('Copy'),
            icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
            variant: WeCordButtonVariant.primary,
            onPressed: _copy,
          ),
          WeCordButton(
            key: const ValueKey('image-text-select'),
            label: tr('Select'),
            icon: Icons.select_all_rounded,
            variant: WeCordButtonVariant.secondary,
            onPressed: _select,
          ),
          if (aiAvailable)
            WeCordButton(
              key: const ValueKey('image-text-translate'),
              label: tr('Translate'),
              icon: Icons.translate_rounded,
              variant: WeCordButtonVariant.secondary,
              loading: _translatePhase == _TranslatePhase.loading,
              onPressed: () => unawaited(_translate()),
            ),
        ],
      ),
      if (_translatePhase != _TranslatePhase.idle && aiAvailable) ...[
        const SizedBox(height: 18),
        _translationBlock(c),
      ],
    ];
  }

  Widget _translationBlock(WeCordPalette c) {
    switch (_translatePhase) {
      case _TranslatePhase.idle:
        return const SizedBox.shrink();
      case _TranslatePhase.loading:
        return Semantics(
          liveRegion: true,
          label: tr('Translating…'),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.muted,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                tr('Translating…'),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ],
          ),
        );
      case _TranslatePhase.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Translated to {language}', {
                'language': AiLanguage.appLanguage.label,
              }),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Semantics(
                liveRegion: true,
                child: SelectableText(
                  _translation ?? '',
                  key: const ValueKey('image-text-translation'),
                  style: TextStyle(fontSize: 16, height: 1.45, color: c.ink),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: WeCordButton(
                key: const ValueKey('image-text-copy-translation'),
                label: _translationCopied
                    ? tr('Copied')
                    : tr('Copy translation'),
                icon: _translationCopied
                    ? Icons.check_rounded
                    : Icons.copy_rounded,
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.secondary,
                onPressed: _copyTranslation,
              ),
            ),
          ],
        );
      case _TranslatePhase.failed:
        return Semantics(
          liveRegion: true,
          child: Text(
            aiErrorMessage(_translateError ?? const AiFailedException()),
            key: const ValueKey('image-text-translate-error'),
            style: TextStyle(fontSize: 14, height: 1.4, color: c.dangerText),
          ),
        );
    }
  }
}
