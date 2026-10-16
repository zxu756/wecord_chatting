import 'dart:math' as math;
import 'dart:ui';

/// The most items one album holds (the server's limit too).
const maxAlbumItems = 10;

/// How an album of 1 to 10 pictures is laid out in a bubble: justified rows
/// that fill the width, each row as tall as its pictures' proportions ask
/// (within limits), with a thin gap between tiles.
///
/// Pure geometry, so it is tested without widgets; `AlbumGrid` draws it.
class AlbumLayout {
  const AlbumLayout({required this.size, required this.tiles});

  /// The whole grid.
  final Size size;

  /// One rectangle per item, in order, relative to the grid's top left.
  final List<Rect> tiles;

  /// The shape of each row for [count] items.
  static List<int> rowsFor(int count, List<double> aspects) {
    if (count <= 0) {
      return const [];
    }
    switch (count) {
      case 1:
        return const [1];
      case 2:
        // Two wide pictures stack; otherwise they sit side by side.
        return aspects[0] >= 1.25 && aspects[1] >= 1.25
            ? const [1, 1]
            : const [2];
      case 3:
        return const [1, 2];
      case 4:
        return const [2, 2];
      case 5:
        return const [2, 3];
      case 6:
        return const [3, 3];
      case 7:
        return const [1, 3, 3];
      case 8:
        return const [2, 3, 3];
      case 9:
        return const [3, 3, 3];
      default:
        return count == 10 ? const [1, 3, 3, 3] : _evenRows(count);
    }
  }

  static List<int> _evenRows(int count) {
    final rows = <int>[];
    var left = count;
    while (left > 0) {
      final take = math.min(3, left);
      rows.add(take);
      left -= take;
    }
    return rows;
  }

  /// Lays out [aspects] (width / height of each item; null or not
  /// positive means unknown, taken as 4:3) in [width].
  static AlbumLayout compute({
    required List<double?> aspects,
    required double width,
    double gap = 2,
  }) {
    final count = math.min(aspects.length, maxAlbumItems);
    if (count == 0 || width <= 0) {
      return const AlbumLayout(size: Size.zero, tiles: []);
    }
    final ratios = [
      for (var i = 0; i < count; i++)
        (aspects[i] != null && aspects[i]! > 0 && aspects[i]!.isFinite)
            ? aspects[i]!.clamp(0.3, 4.0)
            : 4 / 3,
    ];

    if (count == 1) {
      // A single picture keeps its proportions, within limits.
      final height = (width / ratios.first).clamp(width * 0.5, width * 1.2);
      return AlbumLayout(
        size: Size(width, height),
        tiles: [Rect.fromLTWH(0, 0, width, height)],
      );
    }

    final rows = rowsFor(count, ratios);
    final tiles = <Rect>[];
    var top = 0.0;
    var index = 0;
    for (final (rowIndex, rowCount) in rows.indexed) {
      final rowRatios = ratios.sublist(index, index + rowCount);
      final available = width - gap * (rowCount - 1);
      final natural = available / rowRatios.fold(0.0, (a, b) => a + b);
      // Single-picture rows and rows of several differ in how tall they
      // may get.
      final minHeight = rowCount == 1 ? width * 0.4 : width * 0.26;
      final maxHeight = rowCount == 1 ? width * 0.75 : width * 0.6;
      final height = natural.clamp(minHeight, maxHeight);
      var left = 0.0;
      final sum = rowRatios.fold(0.0, (a, b) => a + b);
      for (var i = 0; i < rowCount; i++) {
        final isLast = i == rowCount - 1;
        final tileWidth = isLast
            ? width - left
            : (available * rowRatios[i] / sum).floorToDouble();
        tiles.add(Rect.fromLTWH(left, top, tileWidth, height));
        left += tileWidth + gap;
      }
      top += height + (rowIndex == rows.length - 1 ? 0 : gap);
      index += rowCount;
    }
    return AlbumLayout(size: Size(width, top), tiles: tiles);
  }
}
