import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What the AI in the notes editor can do.
enum NoteAssistMode {
  continueWriting('continue'),
  summarize('summarize'),
  outline('outline'),
  tone('tone'),
  translate('translate'),
  extractTasks('extract_tasks');

  const NoteAssistMode(this.code);

  /// What the `ai` function's `note_assist` takes.
  final String code;

  String get label => switch (this) {
    NoteAssistMode.continueWriting => tr('Continue writing'),
    NoteAssistMode.summarize => tr('Summarize'),
    NoteAssistMode.outline => tr('Make an outline'),
    NoteAssistMode.tone => tr('Change the tone'),
    NoteAssistMode.translate => tr('Translate'),
    NoteAssistMode.extractTasks => tr('Pull out the to-dos'),
  };

  String get hint => switch (this) {
    NoteAssistMode.continueWriting => tr('Adds a few sentences after the text'),
    NoteAssistMode.summarize => tr('A few bullet points'),
    NoteAssistMode.outline => tr('Headings and points to cover'),
    NoteAssistMode.tone => tr('Politer, more formal, relaxed, shorter…'),
    NoteAssistMode.translate => tr('Into another language'),
    NoteAssistMode.extractTasks => tr('Things somebody has to do, as to-dos'),
  };

  IconData get icon => switch (this) {
    NoteAssistMode.continueWriting => Icons.edit_note_rounded,
    NoteAssistMode.summarize => Icons.short_text_rounded,
    NoteAssistMode.outline => Icons.format_list_bulleted_rounded,
    NoteAssistMode.tone => Icons.record_voice_over_outlined,
    NoteAssistMode.translate => Icons.translate_rounded,
    NoteAssistMode.extractTasks => Icons.checklist_rounded,
  };

  /// Whether the answer takes the place of the selected words (the others
  /// are put under the text).
  bool get canReplaceSelection =>
      this == NoteAssistMode.tone || this == NoteAssistMode.translate;
}

/// The tones the AI can change a text to.
enum NoteAssistTone {
  polite('polite'),
  formal('formal'),
  casual('casual'),
  concise('concise'),
  fix('fix');

  const NoteAssistTone(this.code);

  final String code;

  String get label => switch (this) {
    NoteAssistTone.polite => tr('More polite and friendly'),
    NoteAssistTone.formal => tr('More formal'),
    NoteAssistTone.casual => tr('More relaxed'),
    NoteAssistTone.concise => tr('Shorter and clearer'),
    NoteAssistTone.fix => tr('Fix spelling & grammar'),
  };
}

/// A block of the AI's answer.
@immutable
class NoteAssistBlock {
  const NoteAssistBlock({
    required this.kind,
    required this.text,
    this.checked = false,
  });

  static NoteAssistBlock? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = json['text'];
    if (text is! String || text.trim().isEmpty) {
      return null;
    }
    final kind = NoteBlockKind.fromValue(json['kind']);
    // An answer is text: no pictures, dividers, code or tables.
    const allowed = {
      NoteBlockKind.paragraph,
      NoteBlockKind.heading1,
      NoteBlockKind.heading2,
      NoteBlockKind.heading3,
      NoteBlockKind.bullet,
      NoteBlockKind.numbered,
      NoteBlockKind.todo,
      NoteBlockKind.quote,
    };
    return NoteAssistBlock(
      kind: allowed.contains(kind) ? kind : NoteBlockKind.paragraph,
      text: text,
      checked: json['checked'] == true,
    );
  }

  final NoteBlockKind kind;
  final String text;
  final bool checked;

  /// The block as the editor takes it.
  ({NoteBlockKind kind, String text, Map<String, Object?> props}) toInsert() =>
      (
        kind: kind,
        text: text,
        props: kind == NoteBlockKind.todo ? {'checked': checked} : const {},
      );
}

/// The AI's answer for a note.
@immutable
class NoteAssistResult {
  const NoteAssistResult({
    required this.blocks,
    required this.text,
    this.truncated = false,
  });

  final List<NoteAssistBlock> blocks;

  /// The same as plain text, one line per block.
  final String text;

  /// The note was longer than the AI reads; this is about the part it read.
  final bool truncated;

  bool get isEmpty => blocks.isEmpty;
}

/// Asks the `ai` function's `note_assist`. Throws an [AiException] when the
/// server cannot answer.
abstract interface class NoteAssistRepository {
  Future<NoteAssistResult> assist({
    required String noteId,
    required NoteAssistMode mode,
    String? text,
    NoteAssistTone? tone,
    AiLanguage? target,
    AiLanguage? language,
  });
}
