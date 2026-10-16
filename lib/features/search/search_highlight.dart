import 'package:flutter/painting.dart';

/// A range of a text that matched a search term.
typedef SearchMatch = ({int start, int end});

/// Where [terms] occur in [text], ignoring case, merged where they
/// overlap, in order. Phrases match as a whole.
List<SearchMatch> findSearchMatches(String text, Iterable<String> terms) {
  // Lower-casing a few characters changes their length; match those texts
  // as they are rather than at shifted offsets.
  final folded = text.toLowerCase();
  final fold = folded.length == text.length;
  final lower = fold ? folded : text;
  final ranges = <SearchMatch>[];
  for (final term in terms) {
    final needle = fold ? term.trim().toLowerCase() : term.trim();
    if (needle.isEmpty) {
      continue;
    }
    var from = 0;
    while (from <= lower.length - needle.length) {
      final at = lower.indexOf(needle, from);
      if (at < 0) {
        break;
      }
      ranges.add((start: at, end: at + needle.length));
      from = at + needle.length;
    }
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  final merged = <SearchMatch>[];
  for (final range in ranges) {
    final last = merged.lastOrNull;
    if (last != null && range.start <= last.end) {
      merged[merged.length - 1] = (
        start: last.start,
        end: range.end > last.end ? range.end : last.end,
      );
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// [text] cut to start a little before its first match when that match is
/// further in than [lead] characters, so it shows in a two-line preview.
String searchSnippet(String text, Iterable<String> terms, {int lead = 48}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final first = findSearchMatches(flat, terms).firstOrNull;
  if (first == null || first.start <= lead) {
    return flat;
  }
  var start = first.start - lead ~/ 2;
  final space = flat.lastIndexOf(' ', start);
  if (space > 0 && start - space < 12) {
    start = space + 1;
  }
  return '…${flat.substring(start)}';
}

/// [text] as spans with the matches of [terms] in [highlight].
TextSpan highlightSearchMatches(
  String text,
  Iterable<String> terms, {
  required TextStyle style,
  required TextStyle highlight,
}) {
  final matches = findSearchMatches(text, terms);
  if (matches.isEmpty) {
    return TextSpan(text: text, style: style);
  }
  final children = <TextSpan>[];
  var at = 0;
  for (final match in matches) {
    if (match.start > at) {
      children.add(TextSpan(text: text.substring(at, match.start)));
    }
    children.add(
      TextSpan(text: text.substring(match.start, match.end), style: highlight),
    );
    at = match.end;
  }
  if (at < text.length) {
    children.add(TextSpan(text: text.substring(at)));
  }
  return TextSpan(style: style, children: children);
}
