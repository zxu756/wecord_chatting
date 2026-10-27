import 'dart:math' as math;

import 'package:wecord/features/whiteboard/whiteboard_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Words for what is on a board, for the element list (the alternative to
/// the drawing for screen readers) and for the spoken labels of the page.

const _namedColors = <(int, String Function())>[
  (0xFF1B1B1F, _black),
  (0xFFE5484D, _red),
  (0xFFF76B15, _orange),
  (0xFFE6A700, _yellow),
  (0xFF30A46C, _green),
  (0xFF3B6EF5, _blue),
  (0xFF8E4EC6, _purple),
  (0xFF8B8D98, _gray),
  (0xFFFFFFFF, _white),
  (0xFFFFE08A, _yellow),
  (0xFFFFC9C9, _pink),
  (0xFFC7F0D2, _green),
  (0xFFCDE3FF, _blue),
  (0xFFE6D5FF, _purple),
  (0xFFFFD8A8, _orange),
];

String _black() => tr('black');
String _red() => tr('red');
String _orange() => tr('orange');
String _yellow() => tr('yellow');
String _green() => tr('green');
String _blue() => tr('blue');
String _purple() => tr('purple');
String _gray() => tr('gray');
String _white() => tr('white');
String _pink() => tr('pink');

/// The name of the nearest color a person can pick.
String whiteboardColorName(int color) {
  int channel(int value, int shift) => (value >> shift) & 0xFF;
  var best = _namedColors.first;
  var bestDistance = double.infinity;
  for (final candidate in _namedColors) {
    final dr = channel(color, 16) - channel(candidate.$1, 16);
    final dg = channel(color, 8) - channel(candidate.$1, 8);
    final db = channel(color, 0) - channel(candidate.$1, 0);
    final distance = math.sqrt((dr * dr + dg * dg + db * db).toDouble());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  return best.$2();
}

String whiteboardShapeName(WhiteboardShape shape) {
  return switch (shape) {
    WhiteboardShape.rect => tr('Rectangle'),
    WhiteboardShape.ellipse => tr('Ellipse'),
    WhiteboardShape.triangle => tr('Triangle'),
    WhiteboardShape.diamond => tr('Diamond'),
    WhiteboardShape.line => tr('Line'),
    WhiteboardShape.arrow => tr('Arrow'),
  };
}

String _clip(String text, [int length = 80]) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= length ? flat : '${flat.substring(0, length)}…';
}

/// What kind of thing [element] is, in a word or two.
String whiteboardKindName(WhiteboardElement element) {
  return switch (element.kind) {
    WhiteboardKind.stroke =>
      element.highlighter ? tr('Highlighter line') : tr('Pen line'),
    WhiteboardKind.shape => whiteboardShapeName(element.shape),
    WhiteboardKind.sticky => tr('Sticky note'),
    WhiteboardKind.text => tr('Text'),
    WhiteboardKind.image => tr('Picture'),
  };
}

/// One line that says what [element] is and what it says.
String describeWhiteboardElement(WhiteboardElement element) {
  final kind = whiteboardKindName(element);
  switch (element.kind) {
    case WhiteboardKind.sticky:
    case WhiteboardKind.text:
      final words = _clip(element.text);
      final color = whiteboardColorName(element.color);
      if (words.isEmpty) {
        return element.kind == WhiteboardKind.sticky
            ? tr('{kind}, {color}, empty', {'kind': kind, 'color': color})
            : tr('{kind}, empty', {'kind': kind});
      }
      return element.kind == WhiteboardKind.sticky
          ? tr('{kind}, {color}: {words}', {
              'kind': kind,
              'color': color,
              'words': words,
            })
          : tr('{kind}: {words}', {'kind': kind, 'words': words});
    case WhiteboardKind.stroke:
      return tr('{kind}, {color}', {
        'kind': kind,
        'color': whiteboardColorName(element.color),
      });
    case WhiteboardKind.shape:
      return tr('{kind}, {color}', {
        'kind': kind,
        'color': whiteboardColorName(element.color),
      });
    case WhiteboardKind.image:
      return kind;
  }
}

/// Where [element] is, in words a person can use.
String describeWhiteboardPlace(WhiteboardElement element) {
  final box = element.bounds;
  return tr('At {x} across, {y} down', {
    'x': box.left.round(),
    'y': box.top.round(),
  });
}

/// The board's elements in reading order: top to bottom, then left to right
/// (rows of about 80 units count as one line).
List<WhiteboardElement> readingOrder(Iterable<WhiteboardElement> elements) {
  final list = elements.toList();
  list.sort((a, b) {
    final rowA = (a.bounds.top / 80).floor();
    final rowB = (b.bounds.top / 80).floor();
    if (rowA != rowB) {
      return rowA.compareTo(rowB);
    }
    final byX = a.bounds.left.compareTo(b.bounds.left);
    return byX != 0 ? byX : a.id.compareTo(b.id);
  });
  return list;
}
