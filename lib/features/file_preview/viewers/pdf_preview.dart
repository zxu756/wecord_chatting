import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Where a PDF comes from: a downloaded file (iOS, macOS) or a link the
/// viewer streams itself (the web, converted Office files).
sealed class PdfSource {
  const PdfSource();
}

class PdfFileSource extends PdfSource {
  const PdfFileSource(this.path);

  final String path;
}

class PdfUriSource extends PdfSource {
  const PdfUriSource(this.uri);

  final Uri uri;
}

/// Finds the PDF, reporting download progress on the way.
typedef PdfSourceResolver =
    Future<PdfSource> Function(DownloadProgress onProgress, FetchCancel cancel);

/// Builds the PDF viewer itself; tests swap in a stand-in since PDFium
/// isn't available there.
typedef PdfViewerBuilder =
    Widget Function(
      BuildContext context,
      PdfSource source,
      PdfViewerController controller,
      PdfViewerParams params,
    );

Widget defaultPdfViewerBuilder(
  BuildContext context,
  PdfSource source,
  PdfViewerController controller,
  PdfViewerParams params,
) {
  return switch (source) {
    PdfFileSource(:final path) => PdfViewer.file(
      path,
      controller: controller,
      params: params,
    ),
    PdfUriSource(:final uri) => PdfViewer.uri(
      uri,
      controller: controller,
      params: params,
    ),
  };
}

/// A PDF rendered in the app (pdfrx: PDFium natively, PDFium WASM on the
/// web): continuous pages with zoom, a toolbar for pages, zoom and text
/// search, selectable text, and a page thumbnail strip on desktop.
class PdfPreview extends StatefulWidget {
  const PdfPreview({
    required this.file,
    required this.resolve,
    required this.desktop,
    this.onDownload,
    this.viewerBuilder = defaultPdfViewerBuilder,
    this.loadingLabel,
    super.key,
  });

  final PreviewFile file;
  final PdfSourceResolver resolve;
  final bool desktop;
  final VoidCallback? onDownload;
  final PdfViewerBuilder viewerBuilder;

  /// Shown while the source is prepared ("Converting for preview…").
  final String? loadingLabel;

  @override
  State<PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> {
  final _controller = PdfViewerController();

  /// Made once the viewer has its document (it needs one).
  PdfTextSearcher? _searcher;
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  PdfSource? _source;
  Object? _error;
  var _received = 0;
  int? _total;
  FetchCancel? _cancel;
  var _resolving = false;

  PdfDocument? _document;
  int? _page;
  var _searching = false;
  var _thumbnails = true;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _searcher
      ?..removeListener(_onSearch)
      ..dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _resolve() async {
    final cancel = _cancel = FetchCancel();
    setState(() {
      _error = null;
      _source = null;
      _resolving = true;
      _received = 0;
      _total = null;
    });
    try {
      final source = await widget.resolve((received, total) {
        if (mounted) {
          setState(() {
            _received = received;
            _total = total;
          });
        }
      }, cancel);
      if (mounted) {
        setState(() => _source = source);
      }
    } on FetchCancelledException {
      // Closed.
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() => _resolving = false);
      }
    }
  }

  PdfViewerParams _params(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    return PdfViewerParams(
      backgroundColor: tokens.isDark ? c.paper : c.raised,
      margin: widget.desktop ? 20 : 10,
      pageDropShadow: BoxShadow(
        color: c.ink.withValues(alpha: tokens.isDark ? 0.4 : 0.12),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
      matchTextColor: c.warning.withValues(alpha: 0.35),
      activeMatchTextColor: c.accent.withValues(alpha: 0.45),
      textSelectionParams: const PdfTextSelectionParams(enabled: true),
      pagePaintCallbacks: [
        (canvas, rect, page) =>
            _searcher?.pageTextMatchPaintCallback(canvas, rect, page),
      ],
      onViewerReady: (document, controller) {
        _searcher ??= PdfTextSearcher(controller)..addListener(_onSearch);
        if (mounted) {
          setState(() {
            _document = document;
            _page = controller.pageNumber ?? 1;
          });
        }
      },
      onPageChanged: (page) {
        if (mounted && page != null && page != _page) {
          setState(() => _page = page);
        }
      },
      loadingBannerBuilder: (context, received, total) => PreviewProgressView(
        file: widget.file,
        received: received,
        total: total,
      ),
      errorBannerBuilder: (context, error, stackTrace, ref) => ColoredBox(
        color: c.paper,
        child: PreviewErrorView(
          file: widget.file,
          title: tr("This PDF can't be shown"),
          message: tr('It may be damaged or protected with a password.'),
          onRetry: _resolve,
          onDownload: widget.onDownload,
        ),
      ),
    );
  }

  int get _pageCount => _document?.pages.length ?? 0;

  void _goTo(int page) {
    if (_pageCount == 0) {
      return;
    }
    final target = page.clamp(1, _pageCount);
    unawaited(_controller.goToPage(pageNumber: target));
    setState(() => _page = target);
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchField.clear();
      _searcher?.resetTextSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (_error != null) {
      return PreviewErrorView(
        file: file,
        onRetry: _resolve,
        onDownload: widget.onDownload,
      );
    }
    final source = _source;
    if (source == null) {
      return _resolving && _received == 0
          ? PreviewStateLayout(
              key: const ValueKey('file-preview-loading'),
              leading: FileTypeTile(file: file, size: 72),
              title: file.name,
              message: widget.loadingLabel ?? tr('Loading preview…'),
              below: const PreviewSpinner(),
            )
          : PreviewProgressView(
              file: file,
              received: _received,
              total: _total,
              label: widget.loadingLabel,
            );
    }
    final viewer = widget.viewerBuilder(
      context,
      source,
      _controller,
      _params(context),
    );
    final c = context.tokens.colors;
    return Column(
      key: const ValueKey('pdf-preview'),
      children: [
        _toolbar(context),
        Container(height: 1, color: c.lineSoft),
        Expanded(
          child: Row(
            children: [
              if (widget.desktop && _thumbnails && _document != null)
                _ThumbnailStrip(
                  document: _document!,
                  current: _page ?? 1,
                  onSelect: _goTo,
                ),
              Expanded(child: ClipRect(child: viewer)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final c = context.tokens.colors;
    final count = _pageCount;
    final page = _page ?? 1;
    final searcher = _searcher;
    final matches = searcher?.matches.length ?? 0;
    final current = searcher?.currentIndex;
    final searchField = Container(
      height: 36,
      decoration: ShapeDecoration(
        color: c.raised,
        shape: const StadiumBorder(),
      ),
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: c.subtle),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const ValueKey('pdf-search-field'),
              controller: _searchField,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 14, color: c.ink),
              decoration: InputDecoration.collapsed(
                hintText: tr('Find in document'),
                hintStyle: TextStyle(fontSize: 14, color: c.subtle),
              ),
              onChanged: (value) {
                setState(() {});
                searcher?.startTextSearch(value, caseInsensitive: true);
              },
              onSubmitted: (_) {
                if (searcher != null) {
                  unawaited(searcher.goToNextMatch());
                }
                _searchFocus.requestFocus();
              },
            ),
          ),
          if (_searchField.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                (searcher?.isSearching ?? false) && matches == 0
                    ? '…'
                    : tr('{current} of {count}', {
                        'current': current == null ? 0 : current + 1,
                        'count': matches,
                      }),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          WeCordIconButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: tr('Previous match'),
            variant: WeCordButtonVariant.ghost,
            size: 30,
            onPressed: matches == 0
                ? null
                : () => unawaited(searcher!.goToPrevMatch()),
          ),
          WeCordIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: tr('Next match'),
            variant: WeCordButtonVariant.ghost,
            size: 30,
            onPressed: matches == 0
                ? null
                : () => unawaited(searcher!.goToNextMatch()),
          ),
        ],
      ),
    );

    final pageControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WeCordIconButton(
          key: const ValueKey('pdf-previous-page'),
          icon: Icons.chevron_left_rounded,
          tooltip: tr('Previous page'),
          variant: WeCordButtonVariant.ghost,
          size: 34,
          onPressed: count == 0 || page <= 1 ? null : () => _goTo(page - 1),
        ),
        Text(
          count == 0
              ? '–'
              : tr('Page {page} of {count}', {'page': page, 'count': count}),
          key: const ValueKey('pdf-page-label'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        WeCordIconButton(
          key: const ValueKey('pdf-next-page'),
          icon: Icons.chevron_right_rounded,
          tooltip: tr('Next page'),
          variant: WeCordButtonVariant.ghost,
          size: 34,
          onPressed: count == 0 || page >= count ? null : () => _goTo(page + 1),
        ),
      ],
    );

    final zoomControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WeCordIconButton(
          icon: Icons.remove_rounded,
          tooltip: tr('Zoom out'),
          variant: WeCordButtonVariant.ghost,
          size: 34,
          onPressed: count == 0
              ? null
              : () => unawaited(_controller.zoomDown()),
        ),
        WeCordIconButton(
          icon: Icons.add_rounded,
          tooltip: tr('Zoom in'),
          variant: WeCordButtonVariant.ghost,
          size: 34,
          onPressed: count == 0 ? null : () => unawaited(_controller.zoomUp()),
        ),
      ],
    );

    final narrow = !widget.desktop;
    return Container(
      color: c.panel,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: narrow && _searching
          ? Row(
              children: [
                Expanded(child: searchField),
                WeCordIconButton(
                  icon: Icons.close_rounded,
                  tooltip: tr('Close search'),
                  variant: WeCordButtonVariant.ghost,
                  size: 34,
                  onPressed: _toggleSearch,
                ),
              ],
            )
          : Row(
              children: [
                if (widget.desktop)
                  WeCordIconButton(
                    key: const ValueKey('pdf-thumbnails-toggle'),
                    icon: Icons.view_sidebar_outlined,
                    tooltip: tr('Page thumbnails'),
                    variant: WeCordButtonVariant.ghost,
                    selected: _thumbnails,
                    size: 34,
                    onPressed: () => setState(() => _thumbnails = !_thumbnails),
                  ),
                pageControls,
                const Spacer(),
                if (widget.desktop) ...[
                  zoomControls,
                  const SizedBox(width: 8),
                  SizedBox(width: 280, child: searchField),
                ] else ...[
                  zoomControls,
                  WeCordIconButton(
                    key: const ValueKey('pdf-search-toggle'),
                    icon: Icons.search_rounded,
                    tooltip: tr('Find in document'),
                    variant: WeCordButtonVariant.ghost,
                    size: 34,
                    onPressed: _toggleSearch,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ThumbnailStrip extends StatefulWidget {
  const _ThumbnailStrip({
    required this.document,
    required this.current,
    required this.onSelect,
  });

  final PdfDocument document;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  State<_ThumbnailStrip> createState() => _ThumbnailStripState();
}

class _ThumbnailStripState extends State<_ThumbnailStrip> {
  final _scroll = ScrollController();
  static const _itemExtent = 168.0;

  @override
  void didUpdateWidget(covariant _ThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current && _scroll.hasClients) {
      final target = (widget.current - 1) * _itemExtent;
      final view = _scroll.position.viewportDimension;
      final offset = _scroll.offset;
      if (target < offset || target + _itemExtent > offset + view) {
        unawaited(
          _scroll.animateTo(
            (target - view / 2 + _itemExtent / 2).clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
            duration: WeCordMotion.durationOf(context, WeCordMotion.base),
            curve: WeCordMotion.standard,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final pages = widget.document.pages;
    return Container(
      key: const ValueKey('pdf-thumbnails'),
      width: 148,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.lineSoft)),
      ),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemExtent: _itemExtent,
        itemCount: pages.length,
        itemBuilder: (context, index) {
          final number = index + 1;
          final selected = number == widget.current;
          return WeCordPressable(
            onPressed: () => widget.onSelect(number),
            selected: selected,
            semanticLabel: tr('Page {page}', {'page': number}),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.sm),
            ),
            builder: (context, states) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: WeCordMotion.quick,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(WeCordRadii.sm),
                        border: Border.all(
                          width: 2,
                          color: selected
                              ? c.accent
                              : states.contains(WidgetState.hovered)
                              ? c.line
                              : c.panel.withValues(alpha: 0),
                        ),
                      ),
                      child: PdfPageView(
                        document: widget.document,
                        pageNumber: number,
                        maximumDpi: 72,
                        decoration: BoxDecoration(
                          color: WeCordPalette.light.panel,
                          boxShadow: context.tokens.shadows.hairline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? c.accentText : c.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
