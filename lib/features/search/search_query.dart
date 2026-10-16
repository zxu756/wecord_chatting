// The message search box's language: free text with Discord-style
// operators, parsed for the search request, the filter chips, highlighting
// and autocomplete. The text stays the one source of truth; chips and menus
// edit it through [SearchQueryEdit].
//
//   from:@user   mentions:@user   in:#channel (or a group / person)
//   has:file|image|video|link|poll|voice|sticker
//   before:YYYY-MM-DD   after:YYYY-MM-DD   during:YYYY-MM-DD   pinned:true
//
// Values with spaces are quoted (in:"design team"). Free text keeps
// "quoted phrases" and -exclusions for the server.

/// What a message can have, for `has:`.
enum SearchHas {
  file,
  image,
  video,
  link,
  poll,
  voice,
  sticker;

  static SearchHas? tryParse(String value) {
    final lower = value.toLowerCase();
    for (final kind in values) {
      if (kind.name == lower) {
        return kind;
      }
    }
    return null;
  }
}

enum SearchOperator {
  from('from'),
  mentions('mentions'),
  inPlace('in'),
  has('has'),
  before('before'),
  after('after'),
  during('during'),
  pinned('pinned');

  const SearchOperator(this.keyword);

  /// What is typed before the colon.
  final String keyword;

  static SearchOperator? tryParse(String keyword) {
    final lower = keyword.toLowerCase();
    for (final operator in values) {
      if (operator.keyword == lower) {
        return operator;
      }
    }
    return null;
  }

  bool get takesPerson =>
      this == SearchOperator.from || this == SearchOperator.mentions;

  bool get takesDate =>
      this == SearchOperator.before ||
      this == SearchOperator.after ||
      this == SearchOperator.during;
}

/// One word, phrase or operator of the search box, with where it is.
class SearchToken {
  const SearchToken({
    required this.start,
    required this.end,
    required this.raw,
    required this.value,
    this.operator,
    this.negated = false,
    this.quoted = false,
  });

  /// Offsets in the input, [start] inclusive, [end] exclusive.
  final int start;
  final int end;

  /// Exactly as typed.
  final String raw;

  /// The operator's value or the free text, unquoted, without a leading
  /// `@` or `#` for people and places.
  final String value;

  /// Null for free text.
  final SearchOperator? operator;

  /// `-word` or `-"a phrase"`: results must not have it.
  final bool negated;
  final bool quoted;

  bool get isOperator => operator != null;

  /// Whether an operator's value is one it understands (always true for
  /// free text). An empty value is not.
  bool get isValid {
    final operator = this.operator;
    if (operator == null) {
      return value.isNotEmpty;
    }
    if (value.isEmpty) {
      return false;
    }
    return switch (operator) {
      SearchOperator.from ||
      SearchOperator.mentions ||
      SearchOperator.inPlace => true,
      SearchOperator.has => SearchHas.tryParse(value) != null,
      SearchOperator.before ||
      SearchOperator.after ||
      SearchOperator.during => parseSearchDate(value) != null,
      SearchOperator.pinned => parseSearchBool(value) != null,
    };
  }

  @override
  String toString() => 'SearchToken(${operator?.keyword ?? 'text'}: $raw)';
}

/// The search box read as free text plus filters.
class ParsedSearchQuery {
  ParsedSearchQuery._(this.input, this.tokens);

  factory ParsedSearchQuery.parse(String input) {
    return ParsedSearchQuery._(input, tokenizeSearchQuery(input));
  }

  final String input;
  final List<SearchToken> tokens;

  Iterable<SearchToken> get textTokens =>
      tokens.where((token) => !token.isOperator && token.value.isNotEmpty);

  Iterable<SearchToken> get operatorTokens =>
      tokens.where((token) => token.isOperator);

  Iterable<SearchToken> tokensFor(SearchOperator operator) =>
      tokens.where((token) => token.operator == operator && token.isValid);

  /// The free text for the server: words, "phrases" and -exclusions.
  String get text => [
    for (final token in textTokens)
      [
        if (token.negated) '-',
        if (token.quoted) '"${token.value}"' else token.value,
      ].join(),
  ].join(' ');

  /// The words and phrases results contain, for highlighting.
  List<String> get highlightTerms => [
    for (final token in textTokens)
      if (!token.negated) token.value,
  ];

  List<String> get fromHandles => [
    for (final token in tokensFor(SearchOperator.from)) token.value,
  ];

  List<String> get mentionHandles => [
    for (final token in tokensFor(SearchOperator.mentions)) token.value,
  ];

  List<String> get placeNames => [
    for (final token in tokensFor(SearchOperator.inPlace)) token.value,
  ];

  Set<SearchHas> get has => {
    for (final token in tokensFor(SearchOperator.has))
      SearchHas.tryParse(token.value)!,
  };

  /// The last valid date given for [operator] (a local calendar day).
  SearchDate? dateFor(SearchOperator operator) {
    SearchDate? date;
    for (final token in tokensFor(operator)) {
      date = parseSearchDate(token.value);
    }
    return date;
  }

  bool? get pinned {
    bool? value;
    for (final token in tokensFor(SearchOperator.pinned)) {
      value = parseSearchBool(token.value);
    }
    return value;
  }

  /// Operators typed with a value they don't understand.
  List<SearchToken> get invalidOperators => [
    for (final token in operatorTokens)
      if (!token.isValid && token.value.isNotEmpty) token,
  ];

  /// Whether there is anything to search for: some text or a filter.
  bool get hasCriteria =>
      textTokens.any((token) => !token.negated) ||
      operatorTokens.any((token) => token.isValid);
}

/// A calendar day, as typed in a date operator.
class SearchDate implements Comparable<SearchDate> {
  const SearchDate(this.year, this.month, this.day);

  factory SearchDate.fromDateTime(DateTime value) =>
      SearchDate(value.year, value.month, value.day);

  final int year;
  final int month;
  final int day;

  /// The start of the day on this device.
  DateTime get startLocal => DateTime(year, month, day);

  /// The start of the next day on this device.
  DateTime get endLocal => DateTime(year, month, day + 1);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is SearchDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  int compareTo(SearchDate other) => startLocal.compareTo(other.startLocal);
}

final _datePattern = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

/// `YYYY-MM-DD` (months and days may have one digit); null for anything
/// else or a day that does not exist.
SearchDate? parseSearchDate(String value) {
  final match = _datePattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return SearchDate(year, month, day);
}

bool? parseSearchBool(String value) {
  return switch (value.toLowerCase()) {
    'true' || 'yes' || '1' => true,
    'false' || 'no' || '0' => false,
    _ => null,
  };
}

bool _isSpace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    unit == 0x3000; // ideographic space

final _operatorPrefix = RegExp(r'^([A-Za-z]+):');

/// Splits [input] into words, phrases and operators. Never throws: an
/// unclosed quote runs to the end, unknown `key:` words are free text.
List<SearchToken> tokenizeSearchQuery(String input) {
  final tokens = <SearchToken>[];
  var index = 0;
  final length = input.length;

  int readQuoted(int from) {
    // [from] is just after the opening quote; returns the index after the
    // closing quote (or the end).
    final close = input.indexOf('"', from);
    return close == -1 ? length : close + 1;
  }

  int readWord(int from) {
    var at = from;
    while (at < length && !_isSpace(input.codeUnitAt(at))) {
      at++;
    }
    return at;
  }

  while (index < length) {
    if (_isSpace(input.codeUnitAt(index))) {
      index++;
      continue;
    }
    final start = index;
    final rest = input.substring(index);
    final operatorMatch = _operatorPrefix.firstMatch(rest);
    final operator = operatorMatch == null
        ? null
        : SearchOperator.tryParse(operatorMatch.group(1)!);
    if (operator != null) {
      final valueStart = index + operatorMatch!.group(0)!.length;
      var end = valueStart;
      var quoted = false;
      String value;
      if (valueStart < length && input[valueStart] == '"') {
        quoted = true;
        end = readQuoted(valueStart + 1);
        final closed = end - 1 > valueStart && input[end - 1] == '"';
        value = input.substring(valueStart + 1, closed ? end - 1 : end);
      } else {
        end = readWord(valueStart);
        value = input.substring(valueStart, end);
      }
      value = value.trim();
      if (operator.takesPerson && value.startsWith('@')) {
        value = value.substring(1);
      } else if (operator == SearchOperator.inPlace &&
          (value.startsWith('#') || value.startsWith('@'))) {
        value = value.substring(1);
      }
      tokens.add(
        SearchToken(
          start: start,
          end: end,
          raw: input.substring(start, end),
          value: value,
          operator: operator,
          quoted: quoted,
        ),
      );
      index = end;
      continue;
    }

    var negated = false;
    var at = index;
    if (input[at] == '-' &&
        at + 1 < length &&
        !_isSpace(input.codeUnitAt(at + 1))) {
      negated = true;
      at++;
    }
    if (input[at] == '"') {
      final end = readQuoted(at + 1);
      final closed = end - 1 > at && input[end - 1] == '"';
      final value = input.substring(at + 1, closed ? end - 1 : end).trim();
      tokens.add(
        SearchToken(
          start: start,
          end: end,
          raw: input.substring(start, end),
          value: value,
          negated: negated,
          quoted: true,
        ),
      );
      index = end;
      continue;
    }
    final end = readWord(at);
    tokens.add(
      SearchToken(
        start: start,
        end: end,
        raw: input.substring(start, end),
        value: input.substring(at, end),
        negated: negated,
      ),
    );
    index = end;
  }
  return tokens;
}

/// How a value is written after an operator: quoted when it has spaces or
/// quotes, people as `@name`, places as `#name`.
String formatOperatorValue(SearchOperator operator, String value) {
  final needsQuotes = value.isEmpty || value.contains(RegExp(r'[\s"]'));
  final clean = value.replaceAll('"', '');
  final body = needsQuotes ? '"$clean"' : clean;
  if (needsQuotes) {
    return body;
  }
  if (operator.takesPerson) {
    return '@$body';
  }
  if (operator == SearchOperator.inPlace) {
    return '#$body';
  }
  return body;
}

/// A change to the search box text and where the cursor goes.
class SearchQueryEdit {
  const SearchQueryEdit(this.text, this.cursor);

  final String text;
  final int cursor;

  /// Adds `operator:value` at the end (after a space).
  static SearchQueryEdit append(
    String input,
    SearchOperator operator,
    String value,
  ) {
    final token = '${operator.keyword}:${formatOperatorValue(operator, value)}';
    final trimmed = input.trimRight();
    final text = trimmed.isEmpty ? '$token ' : '$trimmed $token ';
    return SearchQueryEdit(text, text.length);
  }

  /// Replaces [token] with [replacement] and a trailing space.
  static SearchQueryEdit replace(
    String input,
    SearchToken token,
    String replacement, {
    bool trailingSpace = true,
  }) {
    final after = input.substring(token.end);
    final space = trailingSpace && !after.startsWith(' ') ? ' ' : '';
    final text = '${input.substring(0, token.start)}$replacement$space$after';
    return SearchQueryEdit(
      text,
      token.start + replacement.length + (trailingSpace ? 1 : 0),
    );
  }

  /// Removes [token] and the space after it.
  static SearchQueryEdit remove(String input, SearchToken token) {
    var end = token.end;
    while (end < input.length && _isSpace(input.codeUnitAt(end))) {
      end++;
    }
    var start = token.start;
    if (end == input.length) {
      while (start > 0 && _isSpace(input.codeUnitAt(start - 1))) {
        start--;
      }
    }
    final text = input.substring(0, start) + input.substring(end);
    return SearchQueryEdit(text, start.clamp(0, text.length));
  }

  /// Removes every [operator] token, then appends one with [value] (or
  /// none when [value] is null): for single-valued filters like dates.
  static SearchQueryEdit setSingle(
    String input,
    SearchOperator operator,
    String? value,
  ) {
    var text = input;
    while (true) {
      final existing = tokenizeSearchQuery(
        text,
      ).where((token) => token.operator == operator).firstOrNull;
      if (existing == null) {
        break;
      }
      text = remove(text, existing).text;
    }
    if (value == null) {
      return SearchQueryEdit(text, text.length);
    }
    return append(text, operator, value);
  }
}

/// What the user is typing at the cursor, for autocomplete.
sealed class SearchCompletionContext {
  const SearchCompletionContext();
}

/// A bare word that starts an operator name (`fr` → `from:`), or nothing
/// typed yet at the cursor.
class OperatorCompletion extends SearchCompletionContext {
  const OperatorCompletion(this.token, this.prefix);

  /// The word being typed, or null at a fresh position.
  final SearchToken? token;
  final String prefix;
}

/// The value of an operator being typed (`from:@ad`).
class ValueCompletion extends SearchCompletionContext {
  const ValueCompletion(this.token);

  final SearchToken token;

  SearchOperator get operator => token.operator!;
  String get prefix => token.value;
}

/// What to complete with the cursor at [cursor] in [input], or null when
/// the cursor is inside plain text that isn't an operator name.
SearchCompletionContext? searchCompletionAt(String input, int cursor) {
  final tokens = tokenizeSearchQuery(input);
  for (final token in tokens) {
    if (cursor < token.start || cursor > token.end) {
      continue;
    }
    if (token.isOperator) {
      // Closed quotes mean the value is done.
      if (token.quoted && token.raw.endsWith('"') && cursor == token.end) {
        return null;
      }
      return ValueCompletion(token);
    }
    if (token.negated || token.quoted || cursor != token.end) {
      return null;
    }
    final word = token.value.toLowerCase();
    final matches = SearchOperator.values.any(
      (operator) => operator.keyword.startsWith(word),
    );
    return matches ? OperatorCompletion(token, word) : null;
  }
  final atFreshPosition = cursor == 0 || _isSpace(input.codeUnitAt(cursor - 1));
  return atFreshPosition ? const OperatorCompletion(null, '') : null;
}
