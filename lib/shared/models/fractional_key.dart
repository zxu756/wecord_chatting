/// Fractional ordering keys: strings that sort between any two others, so an
/// item can be placed between two neighbours without renumbering them.
///
/// Notes (blocks) and lists (items on a board) both order their rows with
/// these. Keys use the digits `0-9A-Za-z` (base 62, in that order, which is
/// also their ASCII order, so plain string comparison and the server's
/// `collate "C"` agree) and read as a fraction 0.d1d2d3… Keys never end in
/// `0`, so each fraction has exactly one spelling.
library;

const _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _base = 62;

int _digit(String character) => _digits.indexOf(character);

/// The first key of an empty list.
const firstFractionalKey = 'V';

/// A key strictly between [a] and [b]. Null [a] stands for the start and
/// null [b] for the end; both null gives [firstFractionalKey]. Throws an
/// [ArgumentError] unless [a] sorts before [b].
String keyBetween(String? a, String? b) {
  if (a != null && b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a must sort before $b');
  }
  for (final key in [a, b]) {
    if (key != null && !isFractionalKey(key)) {
      throw ArgumentError('$key is not a valid ordering key');
    }
  }
  return _midpoint(a ?? '', b);
}

/// [count] keys in order, all strictly between [a] and [b].
List<String> keysBetween(String? a, String? b, int count) {
  if (count <= 0) {
    return const [];
  }
  if (count == 1) {
    return [keyBetween(a, b)];
  }
  final middle = keyBetween(a, b);
  final before = count ~/ 2;
  return [
    ...keysBetween(a, middle, before),
    middle,
    ...keysBetween(middle, b, count - before - 1),
  ];
}

/// Whether [key] is a usable key: 1 to 64 digits of `0-9A-Za-z`, not
/// ending in `0` (the server accepts a trailing `0` but we never make one).
bool isFractionalKey(String key) {
  return key.isNotEmpty &&
      key.length <= 64 &&
      key.codeUnits.every(
        (unit) => _digits.contains(String.fromCharCode(unit)),
      ) &&
      !key.endsWith('0');
}

/// [a] is the lower bound ('' = 0), [b] the upper one (null = 1).
String _midpoint(String a, String? b) {
  if (b != null) {
    // Share the common prefix, then split what is left.
    var common = 0;
    while (common < b.length &&
        (common < a.length ? a[common] : '0') == b[common]) {
      common++;
    }
    if (common > 0) {
      return b.substring(0, common) +
          _midpoint(
            a.length > common ? a.substring(common) : '',
            b.substring(common),
          );
    }
  }
  final digitA = a.isEmpty ? 0 : _digit(a[0]);
  final digitB = b == null ? _base : _digit(b[0]);
  if (digitB - digitA > 1) {
    final middle = ((digitA + digitB) / 2).round();
    return _digits[middle];
  }
  if (b != null && b.length > 1) {
    // b has more digits: its first digit alone sits between a and b.
    return b.substring(0, 1);
  }
  // Adjacent digits: keep a's digit and go deeper.
  return _digits[digitA] + _midpoint(a.isEmpty ? '' : a.substring(1), null);
}
