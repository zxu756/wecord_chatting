import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/file_preview/code_highlight.dart'
    deferred as highlighter;
import 'package:wecord/features/file_preview/code_highlight_limits.dart';
import 'package:wecord/features/file_preview/csv_table.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart' show formatFileSize;
import 'package:wecord/shared/ui/ui.dart';

/// Monospace for code and plain text: the bundled JetBrains Mono, with
/// the platform's Chinese font for characters it lacks.
const _monoFamily = 'JetBrains Mono';
const _monoFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans SC',
];

TextStyle monoStyle(Color color, {double size = 13}) => TextStyle(
  fontFamily: _monoFamily,
  fontFamilyFallback: _monoFallback,
  fontSize: size,
  height: 1.55,
  color: color,
  // Code shows the characters typed, not ligatures (≠ for !=).
  fontFeatures: const [
    FontFeature.disable('calt'),
    FontFeature.disable('liga'),
  ],
);

/// Text files: Markdown rendered, code highlighted (with line numbers),
/// JSON pretty-printed, CSV/TSV as a table with a sticky header, anything
/// else as plain text. Shows at most [maxTextPreviewBytes].
class TextPreview extends ConsumerStatefulWidget {
  const TextPreview({required this.file, this.onDownload, super.key});

  final PreviewFile file;
  final VoidCallback? onDownload;

  @override
  ConsumerState<TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends ConsumerState<TextPreview> {
  FileBytes? _bytes;
  String? _text;
  Object? _error;
  var _received = 0;
  int? _total;
  FetchCancel? _cancel;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final cancel = _cancel = FetchCancel();
    setState(() {
      _error = null;
      _bytes = null;
      _received = 0;
    });
    try {
      final bytes = await ref
          .read(fileFetcherProvider)
          .readBytes(
            widget.file,
            url: () =>
                ref.read(filePreviewServiceProvider).fileUrl(widget.file),
            maxBytes: maxTextPreviewBytes,
            cancel: cancel,
            onProgress: (received, total) {
              if (mounted) {
                setState(() {
                  _received = received;
                  _total = total;
                });
              }
            },
          );
      var text = utf8.decode(bytes.bytes, allowMalformed: true);
      if (text.startsWith('﻿')) {
        text = text.substring(1);
      }
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _text = text;
        });
      }
    } on FetchCancelledException {
      // Closed.
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (_error != null) {
      return PreviewErrorView(
        file: file,
        onRetry: _load,
        onDownload: widget.onDownload,
      );
    }
    final bytes = _bytes;
    final text = _text;
    if (bytes == null || text == null) {
      return _received == 0
          ? const PreviewSpinner()
          : PreviewProgressView(file: file, received: _received, total: _total);
    }
    final body = switch (file.kind) {
      PreviewKind.markdown => MarkdownDocument(text: text),
      PreviewKind.table => CsvTableView(
        table: DelimitedTable.parse(text, extension: file.extension),
      ),
      PreviewKind.json => CodeView(
        text: prettyJson(text, truncated: bytes.truncated),
        language: 'json',
      ),
      PreviewKind.code => CodeView(text: text, language: file.codeLanguage),
      _ => CodeView(text: text, language: null, wrap: true),
    };
    return Column(
      key: ValueKey('text-preview-${file.kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bytes.truncated)
          _TruncatedBanner(
            shown: bytes.bytes.length,
            onDownload: widget.onDownload,
          ),
        Expanded(child: body),
      ],
    );
  }
}

/// Indents [text] when it parses as JSON; otherwise (broken, or cut off)
/// leaves it as it is.
String prettyJson(String text, {bool truncated = false}) {
  if (truncated) {
    return text;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
  } on FormatException {
    return text;
  }
}

class _TruncatedBanner extends StatelessWidget {
  const _TruncatedBanner({required this.shown, required this.onDownload});

  final int shown;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('text-preview-truncated'),
      width: double.infinity,
      color: c.warningSoft,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Showing the first {size}. Download to view the rest.', {
                'size': formatFileSize(shown),
              }),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.warningText,
              ),
            ),
          ),
          if (onDownload != null)
            WeCordButton(
              label: tr('Download'),
              size: WeCordButtonSize.small,
              variant: WeCordButtonVariant.secondary,
              icon: Icons.download_rounded,
              onPressed: onDownload,
            ),
        ],
      ),
    );
  }
}

/// Markdown in the app's type, links open in the browser.
class MarkdownDocument extends StatelessWidget {
  const MarkdownDocument({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final theme = Theme.of(context);
    final body = TextStyle(fontSize: 16, height: 1.6, color: c.ink);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      a: body.copyWith(color: c.accentText, fontWeight: FontWeight.w600),
      h1: TextStyle(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: c.ink,
      ),
      h2: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: c.ink,
      ),
      h3: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.ink),
      h4: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
      listBullet: body,
      code: monoStyle(c.ink, size: 14).copyWith(backgroundColor: c.raised),
      codeblockDecoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
        border: Border.all(color: c.lineSoft),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      blockquote: body.copyWith(color: c.muted),
      blockquoteDecoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
        border: Border(left: BorderSide(color: c.track, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      tableHead: body.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      tableBody: body.copyWith(fontSize: 14),
      tableBorder: TableBorder.all(color: c.line),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
    );
    return Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('markdown-preview'),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: sheet,
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null &&
                    (uri.scheme == 'https' || uri.scheme == 'http')) {
                  unawaited(
                    launchUrl(uri, mode: LaunchMode.externalApplication),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Code (or plain text) with line numbers, selectable, highlighted when
/// [language] is known. Long lines scroll sideways unless [wrap].
///
/// The highlighter (the grammars of 40 languages, most of a megabyte of
/// the web app) is loaded the first time a code file opens; the text shows
/// plain until it has.
class CodeView extends StatefulWidget {
  static const _chunk = 2000;

  const CodeView({
    required this.text,
    required this.language,
    this.wrap = false,
    super.key,
  });

  final String text;
  final String? language;
  final bool wrap;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  var _highlighterLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHighlighter());
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_loadHighlighter());
  }

  Future<void> _loadHighlighter() async {
    if (_highlighterLoaded ||
        widget.language == null ||
        widget.text.length > maxHighlightedChars) {
      return;
    }
    await highlighter.loadLibrary();
    if (mounted) {
      setState(() => _highlighterLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final language = widget.language;
    final wrap = widget.wrap;
    final c = context.tokens.colors;
    final base = monoStyle(c.ink);
    final lineCount = '\n'.allMatches(text).length + 1;
    final numbers = monoStyle(c.faint);
    final span =
        (_highlighterLoaded
            ? highlighter.highlightCode(
                text,
                language: language,
                base: base,
                colors: c,
              )
            : null) ??
        TextSpan(text: text, style: base);
    final gutterWidth = (lineCount.toString().length * 8.2) + 24;

    // Large files (past what highlighting takes): one wrapped row per line,
    // built as it scrolls in; very long lines are cut into pieces so no
    // single paragraph gets huge.
    if (text.length > maxHighlightedChars || lineCount > 20000) {
      final rows = <({int? number, String text})>[];
      var number = 0;
      for (final line in text.split('\n')) {
        number++;
        if (line.length <= CodeView._chunk) {
          rows.add((number: number, text: line));
          continue;
        }
        for (var at = 0; at < line.length; at += CodeView._chunk) {
          final end = at + CodeView._chunk < line.length
              ? at + CodeView._chunk
              : line.length;
          rows.add((
            number: at == 0 ? number : null,
            text: line.substring(at, end),
          ));
        }
      }
      return ColoredBox(
        color: c.panel,
        child: SelectionArea(
          child: ListView.builder(
            key: const ValueKey('code-preview'),
            padding: const EdgeInsets.fromLTRB(8, 12, 24, 48),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionContainer.disabled(
                    child: SizedBox(
                      width: gutterWidth,
                      child: Text(
                        row.number?.toString() ?? '',
                        textAlign: TextAlign.right,
                        style: numbers,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(row.text, style: base)),
                ],
              );
            },
          ),
        ),
      );
    }

    final gutter = SelectionContainer.disabled(
      child: Text(
        [for (var i = 1; i <= lineCount; i++) '$i'].join('\n'),
        textAlign: TextAlign.right,
        style: numbers,
      ),
    );
    final code = Text.rich(span, softWrap: wrap);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wrap) ...[
          SizedBox(width: gutterWidth, child: gutter),
          const SizedBox(width: 14),
        ],
        if (wrap) Expanded(child: code) else code,
      ],
    );
    return Container(
      color: c.panel,
      child: Scrollbar(
        child: SingleChildScrollView(
          key: const ValueKey('code-preview'),
          padding: const EdgeInsets.fromLTRB(8, 16, 24, 48),
          child: SelectionArea(
            child: wrap
                ? Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: content,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A CSV/TSV as a table: row numbers, a header that stays put while the
/// body scrolls, columns sized to their content; wide tables scroll
/// sideways together with the header.
class CsvTableView extends StatefulWidget {
  const CsvTableView({required this.table, super.key});

  final DelimitedTable table;

  @override
  State<CsvTableView> createState() => _CsvTableViewState();
}

class _CsvTableViewState extends State<CsvTableView> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  late List<double> _widths = widget.table.columnWidths();

  static const _rowHeight = 36.0;

  @override
  void didUpdateWidget(covariant CsvTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table) {
      _widths = widget.table.columnWidths();
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final table = widget.table;
    if (table.columnCount == 0) {
      return PreviewStateLayout(
        leading: Icon(Icons.table_chart_outlined, size: 40, color: c.faint),
        title: tr('This table is empty'),
      );
    }
    final numberWidth = (table.rows.length.toString().length * 8.0) + 28;
    final totalWidth = numberWidth + _widths.fold<double>(0, (a, b) => a + b);
    final cellStyle = TextStyle(fontSize: 13, height: 1.3, color: c.ink);
    final headStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    final numberStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: c.subtle,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget cell(
      String value,
      double width,
      TextStyle style, {
      bool head = false,
    }) {
      final number = !head && num.tryParse(value.trim()) != null;
      return Container(
        width: width,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: number ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: c.lineSoft)),
        ),
        child: Text(
          value.replaceAll('\n', ' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: number
              ? style.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                )
              : style,
        ),
      );
    }

    final header = Container(
      key: const ValueKey('csv-header'),
      height: _rowHeight,
      decoration: BoxDecoration(
        color: c.raised,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: numberWidth),
          for (var i = 0; i < table.columnCount; i++)
            cell(table.header[i], _widths[i], headStyle, head: true),
        ],
      ),
    );

    final body = Scrollbar(
      controller: _vertical,
      child: ListView.builder(
        key: const ValueKey('csv-body'),
        controller: _vertical,
        itemExtent: _rowHeight,
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: table.rows.length,
        itemBuilder: (context, index) {
          final row = table.rows[index];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: index.isOdd ? c.well : c.panel,
              border: Border(bottom: BorderSide(color: c.lineSoft)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: numberWidth,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: numberStyle,
                  ),
                ),
                for (var i = 0; i < table.columnCount; i++)
                  cell(row[i], _widths[i], cellStyle),
              ],
            ),
          );
        },
      ),
    );

    return ColoredBox(
      color: c.panel,
      child: SelectionArea(
        child: Scrollbar(
          controller: _horizontal,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                children: [
                  header,
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
