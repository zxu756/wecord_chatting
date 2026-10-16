import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/album_layout.dart';

void main() {
  AlbumLayout layout(List<double?> aspects, {double width = 260}) {
    return AlbumLayout.compute(aspects: aspects, width: width);
  }

  test('a single picture keeps its proportions within limits', () {
    final wide = layout([2.0]);
    expect(wide.tiles.single, const Rect.fromLTWH(0, 0, 260, 130));
    // Very wide pictures are not thinner than half the width...
    expect(layout([4.0]).size.height, 130);
    // ...and tall ones not taller than 1.2 times it.
    expect(layout([0.3]).size.height, closeTo(312, 0.001));
    // Unknown proportions are taken as 4:3.
    expect(layout([null]).size.height, closeTo(195, 0.001));
    expect(layout([0.0]).size.height, closeTo(195, 0.001));
  });

  test('every album size from 1 to 10 fills its width with no overlap', () {
    for (var count = 1; count <= 10; count++) {
      final aspects = [
        for (var i = 0; i < count; i++) [0.75, 1.0, 1.5, 0.6, 1.8][i % 5],
      ];
      final result = layout(aspects);
      expect(result.tiles, hasLength(count), reason: '$count items');
      for (final tile in result.tiles) {
        expect(tile.left, greaterThanOrEqualTo(0));
        expect(tile.right, lessThanOrEqualTo(260.0001));
        expect(tile.top, greaterThanOrEqualTo(0));
        expect(tile.bottom, lessThanOrEqualTo(result.size.height + 0.0001));
        expect(tile.width, greaterThan(20));
        expect(tile.height, greaterThan(20));
      }
      for (var i = 0; i < count; i++) {
        for (var j = i + 1; j < count; j++) {
          expect(
            result.tiles[i].overlaps(result.tiles[j]),
            isFalse,
            reason: 'tiles $i and $j of $count',
          );
        }
      }
      // Each row reaches the right edge.
      final rights = <double, double>{};
      for (final tile in result.tiles) {
        rights[tile.top] = tile.right;
      }
      for (final right in rights.values) {
        expect(right, closeTo(260, 0.001), reason: '$count items');
      }
    }
  });

  test('rows follow the album size', () {
    List<int> rows(int count, [double aspect = 1.0]) =>
        AlbumLayout.rowsFor(count, List.filled(count, aspect));
    expect(rows(1), [1]);
    expect(rows(2), [2]);
    expect(rows(2, 1.6), [1, 1], reason: 'two wide pictures stack');
    expect(rows(3), [1, 2]);
    expect(rows(4), [2, 2]);
    expect(rows(5), [2, 3]);
    expect(rows(6), [3, 3]);
    expect(rows(7), [1, 3, 3]);
    expect(rows(8), [2, 3, 3]);
    expect(rows(9), [3, 3, 3]);
    expect(rows(10), [1, 3, 3, 3]);
  });

  test('wider pictures get wider tiles in a row', () {
    final result = layout([2.0, 1.0]);
    expect(result.tiles[0].width, greaterThan(result.tiles[1].width));
    expect(result.tiles[0].height, result.tiles[1].height);
    // Only the gap lies between them.
    expect(result.tiles[1].left - result.tiles[0].right, 2);
  });

  test('rows stay between a quarter and three quarters of the width', () {
    final tall = layout([0.3, 0.3]);
    expect(tall.tiles.first.height, closeTo(260 * 0.6, 0.001));
    final flat = layout([4.0, 4.0, 4.0]);
    for (final tile in flat.tiles) {
      expect(tile.height, greaterThanOrEqualTo(260 * 0.26 - 0.001));
    }
  });

  test('more than ten items are cut at ten, an empty album is empty', () {
    expect(layout(List.filled(14, 1.0)).tiles, hasLength(maxAlbumItems));
    expect(layout(const []).tiles, isEmpty);
    expect(layout([1.0], width: 0).tiles, isEmpty);
  });
}
