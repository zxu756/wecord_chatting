import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/saved_note_image.dart';
import 'package:wecord/features/later/saved_organizer.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The longest side of a note's picture and its JPEG quality.
const savedPictureEdge = 1600;
const savedPictureQuality = 80;

/// Turns the picture a person chose into the JPEG that is uploaded: scaled
/// down, with its metadata (place, camera) left out. Null when it cannot be
/// read as a picture. Tests swap in their own.
typedef SavedPicturePreparer =
    Future<SavedNotePicture?> Function(Uint8List bytes, String fileName);

final savedPicturePreparerProvider = Provider<SavedPicturePreparer>(
  (ref) => (bytes, fileName) async {
    final prepared = await prepareJpegPhoto(
      bytes: bytes,
      fileName: fileName,
      maxEdge: savedPictureEdge,
      quality: savedPictureQuality,
    );
    if (prepared == null) {
      return null;
    }
    return SavedNotePicture(
      bytes: prepared.bytes,
      width: prepared.width,
      height: prepared.height,
    );
  },
);

void _refreshSaved(WidgetRef ref) {
  ref
    ..invalidate(savedMessagesProvider)
    ..invalidate(savedFoldersProvider);
}

/// "New note": a title and/or words and/or up to four pictures, kept only
/// for the person. True when it was saved.
Future<bool> showNewNoteSheet(BuildContext context) async {
  final saved = await showWeCordSheet<bool>(
    context,
    title: tr('New note'),
    detents: const [0.7, 0.95],
    builder: (sheetContext, scroll) => _NoteForm(scroll: scroll),
  );
  return saved ?? false;
}

class _NoteForm extends ConsumerStatefulWidget {
  const _NoteForm({required this.scroll});

  final ScrollController? scroll;

  @override
  ConsumerState<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends ConsumerState<_NoteForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _pictures = <SavedNotePicture>[];
  var _tags = <String>[];
  String? _folder;
  var _busy = false;
  var _picking = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _title.text.trim().isNotEmpty ||
      _body.text.trim().isNotEmpty ||
      _pictures.isNotEmpty;

  Future<void> _addPicture() async {
    if (_picking || _pictures.length >= maxSavedNotePictures) {
      return;
    }
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ref.read(imagePickerServiceProvider).pickImage();
      if (picked == null || !mounted) {
        return;
      }
      final prepared = await ref.read(savedPicturePreparerProvider)(
        picked.bytes,
        picked.fileName,
      );
      if (!mounted) {
        return;
      }
      if (prepared == null) {
        setState(
          () => _error = tr('That picture could not be read. Try another.'),
        );
        return;
      }
      setState(() => _pictures.add(prepared));
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorText(error));
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(savedMessagesRepositoryProvider)
          .createNote(
            title: _title.text,
            body: _body.text,
            pictures: _pictures,
            folderId: _folder,
            tags: _tags,
          );
      _refreshSaved(ref);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SavedSheetFrame(
      scroll: widget.scroll,
      actionKey: const ValueKey('saved-note-save'),
      actionLabel: tr('Save'),
      onAction: _save,
      busy: _busy,
      error: _error,
      actionEnabled: _hasContent,
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('saved-note-title'),
          controller: _title,
          label: tr('Title'),
          hint: tr('Optional'),
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        WeCordTextField(
          fieldKey: const ValueKey('saved-note-body'),
          controller: _body,
          label: tr('Note'),
          hint: tr('Write something to keep'),
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          inputFormatters: [LengthLimitingTextInputFormatter(20000)],
          onChanged: (_) => setState(() {}),
        ),
        SavedFormLabel(tr('Pictures')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, picture) in _pictures.indexed)
              _PictureTile(
                key: ValueKey('saved-note-picture-$index'),
                onRemove: () => setState(() => _pictures.removeAt(index)),
                child: Image.memory(
                  picture.bytes,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
            if (_pictures.length < maxSavedNotePictures)
              WeCordButton(
                key: const ValueKey('saved-note-add-picture'),
                label: _picking ? tr('Opening...') : tr('Add a picture'),
                icon: Icons.add_photo_alternate_outlined,
                size: WeCordButtonSize.small,
                variant: WeCordButtonVariant.secondary,
                onPressed: _picking ? null : () => unawaited(_addPicture()),
              ),
          ],
        ),
        SavedFormLabel(tr('Folder')),
        SavedFolderPicker(
          selected: _folder,
          onChanged: (id) => setState(() => _folder = id),
        ),
        SavedFormLabel(tr('Tags')),
        SavedTagsEditor(
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
      ],
    );
  }
}

/// A picture of a note with a remove button on it.
class _PictureTile extends StatelessWidget {
  const _PictureTile({required this.child, required this.onRemove, super.key});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.md),
            child: child,
          ),
          Positioned(
            top: 0,
            right: 0,
            child: WeCordIconButton(
              icon: Icons.close_rounded,
              tooltip: tr('Remove picture'),
              variant: WeCordButtonVariant.secondary,
              size: 32,
              iconSize: 16,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Save a link": an address and, if the person wants, a title.
/// True when it was saved.
Future<bool> showSaveLinkSheet(
  BuildContext context, {
  String initialUrl = '',
}) async {
  final saved = await showWeCordSheet<bool>(
    context,
    title: tr('Save a link'),
    detents: const [0.65, 0.95],
    builder: (sheetContext, scroll) =>
        _LinkForm(scroll: scroll, initialUrl: initialUrl),
  );
  return saved ?? false;
}

/// The web address the person typed, made whole ("example.com" becomes
/// "https://example.com"); null when it is not a web address.
String? normalizeSavedLink(String raw) {
  var text = raw.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) {
    return null;
  }
  if (!text.contains('://')) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.host.contains('.') ||
      text.length > 2000) {
    return null;
  }
  return text;
}

class _LinkForm extends ConsumerStatefulWidget {
  const _LinkForm({required this.scroll, required this.initialUrl});

  final ScrollController? scroll;
  final String initialUrl;

  @override
  ConsumerState<_LinkForm> createState() => _LinkFormState();
}

class _LinkFormState extends ConsumerState<_LinkForm> {
  late final _url = TextEditingController(text: widget.initialUrl);
  final _title = TextEditingController();
  var _tags = <String>[];
  String? _folder;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = normalizeSavedLink(_url.text);
    if (url == null) {
      setState(() => _error = tr('Enter a web link'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(savedMessagesRepositoryProvider)
          .saveLink(
            url: url,
            title: _title.text,
            folderId: _folder,
            tags: _tags,
          );
      _refreshSaved(ref);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SavedSheetFrame(
      scroll: widget.scroll,
      actionKey: const ValueKey('saved-link-save'),
      actionLabel: tr('Save'),
      onAction: _save,
      busy: _busy,
      error: _error,
      actionEnabled: _url.text.trim().isNotEmpty,
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('saved-link-url'),
          controller: _url,
          label: tr('Web address'),
          hint: 'https://',
          keyboardType: TextInputType.url,
          autofocus: widget.initialUrl.isEmpty,
          inputFormatters: [LengthLimitingTextInputFormatter(2000)],
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 12),
        WeCordTextField(
          fieldKey: const ValueKey('saved-link-title'),
          controller: _title,
          label: tr('Title'),
          hint: tr('Optional'),
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
        ),
        SavedFormLabel(tr('Folder')),
        SavedFolderPicker(
          selected: _folder,
          onChanged: (id) => setState(() => _folder = id),
        ),
        SavedFormLabel(tr('Tags')),
        SavedTagsEditor(
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
      ],
    );
  }
}

/// Edit an entry: its folder, tags and remark; a link's title; a note's
/// title, words and pictures. True when something was saved.
Future<bool> showSavedItemEditor(
  BuildContext context,
  SavedMessage item,
) async {
  final saved = await showWeCordSheet<bool>(
    context,
    title: tr('Edit'),
    detents: const [0.7, 0.95],
    builder: (sheetContext, scroll) => _EditForm(scroll: scroll, item: item),
  );
  return saved ?? false;
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.scroll, required this.item});

  final ScrollController? scroll;
  final SavedMessage item;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final _title = TextEditingController(text: widget.item.title ?? '');
  late final _body = TextEditingController(text: widget.item.body);
  late final _remark = TextEditingController(text: widget.item.note ?? '');
  late var _tags = [...widget.item.tags];
  late String? _folder = widget.item.folderId;
  late final _images = [...widget.item.images];
  var _busy = false;
  String? _error;

  SavedKind get _kind => widget.item.kind;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _remark.dispose();
    super.dispose();
  }

  Map<String, Object?> _patch() {
    final item = widget.item;
    final patch = <String, Object?>{};
    if (_folder != item.folderId) {
      patch['folder_id'] = _folder;
    }
    if (_tags.join('\u0000') != item.tags.join('\u0000')) {
      patch['tags'] = _tags;
    }
    if (_kind != SavedKind.note &&
        _kind != SavedKind.text &&
        _remark.text.trim() != (item.note ?? '')) {
      patch['note'] = _remark.text;
    }
    if ((_kind == SavedKind.note || _kind == SavedKind.link) &&
        _title.text.trim() != (item.title ?? '')) {
      patch['title'] = _title.text;
    }
    if ((_kind == SavedKind.note || _kind == SavedKind.text) &&
        _body.text.trim() != item.body.trim()) {
      patch['body'] = _body.text;
    }
    if (_kind == SavedKind.note && _images.length != item.images.length) {
      patch['images'] = [for (final image in _images) image.toJson()];
    }
    return patch;
  }

  bool get _valid {
    if (_kind == SavedKind.text) {
      return _body.text.trim().isNotEmpty;
    }
    if (_kind == SavedKind.note) {
      return _title.text.trim().isNotEmpty ||
          _body.text.trim().isNotEmpty ||
          _images.isNotEmpty;
    }
    return true;
  }

  Future<void> _save() async {
    final patch = _patch();
    if (patch.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(savedMessagesRepositoryProvider)
          .update(widget.item.id, patch);
      _refreshSaved(ref);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownText = _kind == SavedKind.note || _kind == SavedKind.text;
    return SavedSheetFrame(
      scroll: widget.scroll,
      actionKey: const ValueKey('saved-edit-save'),
      actionLabel: tr('Save'),
      onAction: _save,
      busy: _busy,
      error: _error,
      actionEnabled: _valid,
      children: [
        if (_kind == SavedKind.note || _kind == SavedKind.link) ...[
          WeCordTextField(
            fieldKey: const ValueKey('saved-edit-title'),
            controller: _title,
            label: tr('Title'),
            hint: tr('Optional'),
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
        if (ownText) ...[
          WeCordTextField(
            fieldKey: const ValueKey('saved-edit-body'),
            controller: _body,
            label: tr('Note'),
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            inputFormatters: [LengthLimitingTextInputFormatter(20000)],
            onChanged: (_) => setState(() {}),
          ),
          if (_images.isNotEmpty) ...[
            SavedFormLabel(tr('Pictures')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in _images)
                  _PictureTile(
                    key: ValueKey('saved-edit-picture-${image.path}'),
                    onRemove: () => setState(() => _images.remove(image)),
                    child: SavedNoteImage(path: image.path),
                  ),
              ],
            ),
          ],
        ],
        if (!ownText) ...[
          WeCordTextField(
            fieldKey: const ValueKey('saved-edit-remark'),
            controller: _remark,
            label: tr('Remark'),
            hint: tr('Why you kept this'),
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            inputFormatters: [LengthLimitingTextInputFormatter(1000)],
          ),
        ],
        SavedFormLabel(tr('Folder')),
        SavedFolderPicker(
          selected: _folder,
          onChanged: (id) => setState(() => _folder = id),
        ),
        SavedFormLabel(tr('Tags')),
        SavedTagsEditor(
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
      ],
    );
  }
}
