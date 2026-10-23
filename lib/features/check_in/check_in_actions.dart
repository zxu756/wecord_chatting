import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_repository.dart';
import 'package:wecord/features/check_in/check_in_widgets.dart';
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void _snack(BuildContext context, String text) {
  // Replaces the one still showing, so the latest word is the one read.
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Words for what a check-in did: "Checked in. 7-day streak!".
String checkInDoneText(CheckInResult result) {
  if (result.updated) {
    return tr("Updated today's check-in.");
  }
  if (result.streak >= 2) {
    return tr('Checked in. {count}-day streak!', {'count': result.streak});
  }
  return tr('Checked in.');
}

/// Reads the card and the page again after a change.
void refreshCheckIn(WidgetRef ref, String checkInId) {
  ref
    ..invalidate(checkInProvider(checkInId))
    ..invalidate(checkInDetailProvider(checkInId));
}

/// Checks in for today in one tap, keeping today's note and picture when
/// there already are some. Tells the person how it went.
Future<void> quickCheckIn(
  BuildContext context,
  WidgetRef ref,
  CheckInSnapshot check,
) async {
  final repository = ref.read(checkInRepositoryProvider);
  try {
    final result = await repository.submit(
      check.id,
      note: check.myNote,
      photo: check.myPhoto,
    );
    refreshCheckIn(ref, check.id);
    if (context.mounted) {
      _snack(context, checkInDoneText(result));
    }
  } on CheckInException catch (error) {
    refreshCheckIn(ref, check.id);
    if (context.mounted) {
      _snack(context, error.message);
    }
  }
}

/// Takes today's check-in back.
Future<void> undoCheckIn(
  BuildContext context,
  WidgetRef ref,
  CheckInSnapshot check,
) async {
  try {
    await ref.read(checkInRepositoryProvider).undo(check.id);
    refreshCheckIn(ref, check.id);
    if (context.mounted) {
      _snack(context, tr("Today's check-in was taken back."));
    }
  } on CheckInException catch (error) {
    refreshCheckIn(ref, check.id);
    if (context.mounted) {
      _snack(context, error.message);
    }
  }
}

/// Closes or reopens a check-in (its maker and the people who moderate).
Future<void> setCheckInClosed(
  BuildContext context,
  WidgetRef ref,
  CheckInSnapshot check, {
  required bool closed,
}) async {
  try {
    await ref
        .read(checkInRepositoryProvider)
        .setClosed(check.id, closed: closed);
    refreshCheckIn(ref, check.id);
    if (context.mounted) {
      _snack(
        context,
        closed ? tr('Check-in closed.') : tr('Check-in reopened.'),
      );
    }
  } on CheckInException catch (error) {
    if (context.mounted) {
      _snack(context, error.message);
    }
  }
}

/// The sheet to check in with a note and a picture (or to change today's).
Future<bool?> showCheckInNoteSheet(
  BuildContext context, {
  required CheckInSnapshot check,
}) {
  return showWeCordSheet<bool>(
    context,
    title: check.myCheckedIn ? tr("Change today's check-in") : tr('Check in'),
    builder: (context, controller) =>
        CheckInNoteSheet(check: check, scrollController: controller),
  );
}

class CheckInNoteSheet extends ConsumerStatefulWidget {
  const CheckInNoteSheet({
    required this.check,
    this.scrollController,
    super.key,
  });

  final CheckInSnapshot check;
  final ScrollController? scrollController;

  @override
  ConsumerState<CheckInNoteSheet> createState() => _CheckInNoteSheetState();
}

class _CheckInNoteSheetState extends ConsumerState<CheckInNoteSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.check.myNote,
  );
  FormImageAnswer? _photo;
  Uint8List? _preview;
  var _uploading = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _photo = widget.check.myPhoto;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picker = ref.read(imagePickerServiceProvider);
    final repository = ref.read(checkInRepositoryProvider);
    try {
      final image = await picker.pickImage();
      if (image == null || !mounted) {
        return;
      }
      if (image.bytes.length > maxCheckInImageBytes) {
        setState(() => _error = tr('Pictures can be up to 10 MB.'));
        return;
      }
      setState(() {
        _uploading = true;
        _error = null;
      });
      final uploaded = await repository.uploadPhoto(
        conversationId: widget.check.conversationId,
        checkInId: widget.check.id,
        image: image,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _uploading = false;
        _photo = uploaded;
        _preview = image.bytes;
      });
    } on CheckInException catch (error) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = tr("The picture didn't upload. Try again.");
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(checkInRepositoryProvider)
          .submit(widget.check.id, note: _note.text, photo: _photo);
      refreshCheckIn(ref, widget.check.id);
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            result.noteHeld
                ? tr(
                    "Checked in. Your note is waiting for the circle's review.",
                  )
                : checkInDoneText(result),
          ),
        ),
      );
    } on CheckInException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr("That didn't work. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      controller: widget.scrollController,
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        WeCordTextField(
          fieldKey: const ValueKey('check-in-note-field'),
          controller: _note,
          label: tr('Note (optional)'),
          hint: tr('Read two chapters'),
          maxLength: 200,
          maxLines: 4,
          minLines: 2,
        ),
        const SizedBox(height: 12),
        if (_photo case final photo?)
          Row(
            children: [
              CheckInPhotoThumb(image: photo, bytes: _preview, size: 72),
              const SizedBox(width: 12),
              WeCordButton(
                key: const ValueKey('check-in-photo-remove'),
                label: tr('Remove'),
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _photo = null;
                        _preview = null;
                      }),
              ),
            ],
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: WeCordButton(
              key: const ValueKey('check-in-photo-add'),
              label: tr('Add a picture'),
              icon: Icons.add_photo_alternate_outlined,
              variant: WeCordButtonVariant.secondary,
              loading: _uploading,
              onPressed: _busy || _uploading ? null : () => unawaited(_pick()),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const ValueKey('check-in-note-error'),
              style: TextStyle(fontSize: 13.5, color: c.dangerText),
            ),
          ),
        const SizedBox(height: 16),
        WeCordButton(
          key: const ValueKey('check-in-save'),
          label: widget.check.myCheckedIn ? tr('Save') : tr('Check in'),
          variant: WeCordButtonVariant.accent,
          size: WeCordButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _busy || _uploading ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}
