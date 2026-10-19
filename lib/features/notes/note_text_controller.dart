import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/notes/note_merge.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The text of one note block with its inline formatting. It draws the
/// marks (bold, italic, strike, code, links, mentions) in the text field
/// that edits it and keeps them in step with what is typed: new characters
/// continue the formatting before them, deleted ones take theirs along.
class NoteTextController extends TextEditingController {
  NoteTextController({super.text, List<NoteMark> marks = const []})
    : _marks = normalizeMarks(marks, text?.length ?? 0);

  List<NoteMark> _marks;
  final _pendingOn = <String>{};
  final _pendingOff = <String>{};
  var _applyingRemote = false;

  /// Called when the person changes the text or its formatting (not for
  /// changes made through [applyRemote]).
  void Function(String text, List<NoteMark> marks)? onUserChange;

  List<NoteMark> get marks => _marks;

  /// Stretches drawn highlighted without being part of the text's
  /// formatting (the words open comments are about). Never stored or sent.
  List<NoteMark> get highlights => _highlights;
  var _highlights = const <NoteMark>[];

  set highlights(List<NoteMark> value) {
    if (value.length == _highlights.length) {
      var same = true;
      for (var i = 0; i < value.length; i++) {
        if (value[i] != _highlights[i]) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    _highlights = value;
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    final before = text;
    if (!_applyingRemote && newValue.text != before) {
      final edit = diffText(before, newValue.text);
      var inherit = edit.inserted.isEmpty
          ? <String>{}
          : inheritedMarksAt(before, _marks, edit.start);
      inherit = {...inherit, ..._pendingOn}..removeAll(_pendingOff);
      _marks = applyEditToMarks(_marks, before.length, edit, inherit: inherit);
      _pendingOn.clear();
      _pendingOff.clear();
      super.value = newValue;
      onUserChange?.call(newValue.text, _marks);
      return;
    }
    if (newValue.selection != selection) {
      // Moving the caret drops a half-made choice of style.
      _pendingOn.clear();
      _pendingOff.clear();
    }
    super.value = newValue;
  }

  /// Takes text and formatting that came from elsewhere (somebody else's
  /// edit, a merge), keeping the caret with the words around it.
  void applyRemote(String newText, List<NoteMark> newMarks) {
    final normalized = normalizeMarks(newMarks, newText.length);
    if (newText == text && _sameMarks(normalized, _marks)) {
      return;
    }
    final edit = diffText(text, newText);
    final old = value;
    _applyingRemote = true;
    try {
      _marks = normalized;
      final base = old.selection.baseOffset;
      final extent = old.selection.extentOffset;
      super.value = TextEditingValue(
        text: newText,
        selection: old.selection.isValid
            ? TextSelection(
                baseOffset: transformOffset(
                  base,
                  edit,
                ).clamp(0, newText.length),
                extentOffset: transformOffset(
                  extent,
                  edit,
                ).clamp(0, newText.length),
              )
            : const TextSelection.collapsed(offset: -1),
        composing: TextRange.empty,
      );
    } finally {
      _applyingRemote = false;
    }
  }

  static bool _sameMarks(List<NoteMark> a, List<NoteMark> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  // ------------------------------------------------------------ formatting --

  TextRange get _range {
    final selection = value.selection;
    if (!selection.isValid) {
      return TextRange.collapsed(text.length);
    }
    return TextRange(
      start: selection.start.clamp(0, text.length),
      end: selection.end.clamp(0, text.length),
    );
  }

  /// Whether [type] applies at the caret, or to the whole selection.
  bool isActive(String type) {
    final range = _range;
    if (range.isCollapsed) {
      final inherited = inheritedMarksAt(text, _marks, range.start);
      return (inherited.contains(type) || _pendingOn.contains(type)) &&
          !_pendingOff.contains(type);
    }
    final sets = marksToCharSets(text.length, _marks);
    for (var i = range.start; i < range.end; i++) {
      if (!sets[i].contains(type)) {
        return false;
      }
    }
    return true;
  }

  /// Turns [type] on for the selection (off when it is all on already). At
  /// a caret it chooses the style of what is typed next.
  void toggle(String type) {
    final range = _range;
    if (range.isCollapsed) {
      final active = isActive(type);
      if (active) {
        _pendingOn.remove(type);
        _pendingOff.add(type);
      } else {
        _pendingOff.remove(type);
        _pendingOn.add(type);
      }
      notifyListeners();
      return;
    }
    final sets = marksToCharSets(text.length, _marks);
    final on = !isActive(type);
    for (var i = range.start; i < range.end; i++) {
      if (on) {
        sets[i].add(type);
      } else {
        sets[i].remove(type);
      }
    }
    _setMarks(charSetsToMarks(sets));
  }

  /// The link around the caret or selection, or null.
  NoteMark? get linkAtSelection {
    final range = _range;
    for (final mark in _marks) {
      if (mark.isLink &&
          mark.start <= range.start &&
          mark.end >= (range.isCollapsed ? range.start + 1 : range.end)) {
        return mark;
      }
    }
    return null;
  }

  /// Links the selection to [url]; an empty [url] removes the link.
  void setLink(String url) {
    var range = _range;
    final existing = linkAtSelection;
    if (range.isCollapsed) {
      if (existing == null) {
        return;
      }
      range = TextRange(start: existing.start, end: existing.end);
    }
    final sets = marksToCharSets(text.length, _marks);
    for (var i = range.start; i < range.end; i++) {
      sets[i].removeWhere((type) => type.startsWith(NoteMark.linkPrefix));
      if (url.isNotEmpty) {
        sets[i].add('${NoteMark.linkPrefix}$url');
      }
    }
    _setMarks(charSetsToMarks(sets));
  }

  /// Replaces the characters [start, end) with a mention of [userId] shown
  /// as [label], and puts the caret after it.
  void insertMention({
    required int start,
    required int end,
    required String userId,
    required String label,
  }) {
    final replacement = '$label ';
    final newText = text.replaceRange(start, end, replacement);
    final sets = marksToCharSets(text.length, _marks);
    final next = <Set<String>>[
      ...sets.sublist(0, start),
      for (var i = 0; i < label.length; i++)
        {'${NoteMark.mentionPrefix}$userId'},
      <String>{},
      ...sets.sublist(end),
    ];
    _marks = charSetsToMarks(next);
    super.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    onUserChange?.call(newText, _marks);
  }

  void _setMarks(List<NoteMark> marks) {
    _marks = marks;
    notifyListeners();
    onUserChange?.call(text, _marks);
  }

  // --------------------------------------------------------------- drawing --

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing = withComposing && value.composing.isValid
        ? value.composing
        : TextRange.empty;
    return buildNoteSpan(
      context,
      text,
      _highlights.isEmpty ? _marks : [..._marks, ..._highlights],
      style,
      composing: composing,
    );
  }
}

/// [text] with its [marks] drawn: bold, italic, strike, code, links and
/// mentions. [composing] is underlined (an input method's pending text).
///
/// [recognizerFor] makes links tappable: it is asked for the address of each
/// stretch of link and answers what listens to the tap (the caller disposes
/// of them).
TextSpan buildNoteSpan(
  BuildContext context,
  String text,
  List<NoteMark> marks,
  TextStyle? style, {
  TextRange composing = TextRange.empty,
  GestureRecognizer? Function(String url)? recognizerFor,
}) {
  final c = context.tokens.colors;
  if (text.isEmpty) {
    return TextSpan(style: style, text: text);
  }
  final cuts = <int>{0, text.length};
  for (final mark in marks) {
    cuts
      ..add(mark.start.clamp(0, text.length))
      ..add(mark.end.clamp(0, text.length));
  }
  if (!composing.isCollapsed) {
    cuts
      ..add(composing.start.clamp(0, text.length))
      ..add(composing.end.clamp(0, text.length));
  }
  final points = cuts.toList()..sort();
  final sets = marksToCharSets(text.length, marks);
  final spans = <InlineSpan>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final from = points[i];
    final to = points[i + 1];
    if (from == to) {
      continue;
    }
    final types = sets[from];
    var segmentStyle = const TextStyle();
    final decorations = <TextDecoration>[];
    Color? background;
    GestureRecognizer? recognizer;
    for (final type in types) {
      if (type == NoteMark.bold) {
        segmentStyle = segmentStyle.copyWith(fontWeight: FontWeight.w800);
      } else if (type == NoteMark.italic) {
        segmentStyle = segmentStyle.copyWith(fontStyle: FontStyle.italic);
      } else if (type == NoteMark.strike) {
        decorations.add(TextDecoration.lineThrough);
      } else if (type == NoteMark.code) {
        segmentStyle = segmentStyle.copyWith(
          fontFamily: 'JetBrains Mono',
          fontSize: (style?.fontSize ?? 16) * 0.9,
        );
        background = c.raised;
      } else if (type.startsWith(NoteMark.linkPrefix)) {
        segmentStyle = segmentStyle.copyWith(color: c.accentText);
        decorations.add(TextDecoration.underline);
        recognizer ??= recognizerFor?.call(
          type.substring(NoteMark.linkPrefix.length),
        );
      } else if (type.startsWith(NoteMark.mentionPrefix)) {
        segmentStyle = segmentStyle.copyWith(
          color: c.accentText,
          fontWeight: FontWeight.w700,
        );
        background = c.accentSoft;
      } else if (type == NoteMark.highlight) {
        // Comments are quiet: a yellow wash, not an alarm.
        background ??= c.warningSoft;
      }
    }
    if (!composing.isCollapsed &&
        composing.start <= from &&
        composing.end >= to) {
      decorations.add(TextDecoration.underline);
    }
    if (decorations.isNotEmpty) {
      segmentStyle = segmentStyle.copyWith(
        decoration: TextDecoration.combine(decorations),
      );
    }
    if (background != null) {
      segmentStyle = segmentStyle.copyWith(backgroundColor: background);
    }
    spans.add(
      TextSpan(
        text: text.substring(from, to),
        style: segmentStyle,
        recognizer: recognizer,
      ),
    );
  }
  return TextSpan(style: style, children: spans);
}

/// Read-only formatted text whose links open when tapped ([onOpenLink]; with
/// none they are only drawn).
class NoteLinkedText extends StatefulWidget {
  const NoteLinkedText({
    required this.text,
    required this.marks,
    required this.style,
    this.onOpenLink,
    super.key,
  });

  final String text;
  final List<NoteMark> marks;
  final TextStyle style;
  final void Function(String url)? onOpenLink;

  @override
  State<NoteLinkedText> createState() => _NoteLinkedTextState();
}

class _NoteLinkedTextState extends State<NoteLinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final open = widget.onOpenLink;
    return Text.rich(
      buildNoteSpan(
        context,
        widget.text,
        widget.marks,
        widget.style,
        recognizerFor: open == null
            ? null
            : (url) {
                final recognizer = TapGestureRecognizer()
                  ..onTap = () => open(url);
                _recognizers.add(recognizer);
                return recognizer;
              },
      ),
    );
  }
}
