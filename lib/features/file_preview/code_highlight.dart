import 'package:flutter/material.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/clojure.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/elixir.dart';
import 'package:re_highlight/languages/erlang.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/protobuf.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:wecord/features/file_preview/code_highlight_limits.dart';
import 'package:wecord/shared/ui/ui.dart';

Highlight? _highlight;

Highlight get _highlighter => _highlight ??= Highlight()
  ..registerLanguages({
    'bash': langBash,
    'c': langC,
    'clojure': langClojure,
    'cmake': langCmake,
    'cpp': langCpp,
    'csharp': langCsharp,
    'css': langCss,
    'dart': langDart,
    'diff': langDiff,
    'dockerfile': langDockerfile,
    'elixir': langElixir,
    'erlang': langErlang,
    'go': langGo,
    'gradle': langGradle,
    'graphql': langGraphql,
    'groovy': langGroovy,
    'haskell': langHaskell,
    'ini': langIni,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'kotlin': langKotlin,
    'less': langLess,
    'lua': langLua,
    'makefile': langMakefile,
    'objectivec': langObjectivec,
    'perl': langPerl,
    'php': langPhp,
    'powershell': langPowershell,
    'protobuf': langProtobuf,
    'python': langPython,
    'r': langR,
    'ruby': langRuby,
    'rust': langRust,
    'scala': langScala,
    'scss': langScss,
    'sql': langSql,
    'swift': langSwift,
    'typescript': langTypescript,
    'xml': langXml,
    'yaml': langYaml,
  });

/// Syntax colors from the palette roles, so code reads well in both
/// themes: keywords accent, strings success, numbers and literals warning,
/// comments subtle, types and titles accent text.
Map<String, TextStyle> codeThemeFor(WeCordPalette c) {
  final keyword = TextStyle(color: c.accent, fontWeight: FontWeight.w600);
  final string = TextStyle(color: c.successText);
  final number = TextStyle(color: c.warningText);
  final comment = TextStyle(color: c.subtle, fontStyle: FontStyle.italic);
  final title = TextStyle(color: c.accentText, fontWeight: FontWeight.w600);
  final danger = TextStyle(color: c.dangerText);
  return {
    'root': TextStyle(color: c.ink),
    'keyword': keyword,
    'built_in': title,
    'type': title,
    'class': title,
    'title': title,
    'title.class_': title,
    'title.function_': title,
    'function': title,
    'literal': number,
    'number': number,
    'symbol': number,
    'string': string,
    'regexp': string,
    'char.escape_': number,
    'subst': TextStyle(color: c.ink),
    'comment': comment,
    'quote': comment,
    'doctag': keyword,
    'meta': TextStyle(color: c.muted),
    'meta-keyword': keyword,
    'meta-string': string,
    'attr': title,
    'attribute': title,
    'property': title,
    'variable': TextStyle(color: c.dangerText),
    'template-variable': TextStyle(color: c.dangerText),
    'params': TextStyle(color: c.ink),
    'tag': TextStyle(color: c.muted),
    'name': keyword,
    'selector-tag': keyword,
    'selector-id': title,
    'selector-class': title,
    'section': title,
    'bullet': number,
    'link': TextStyle(
      color: c.accentText,
      decoration: TextDecoration.underline,
    ),
    'addition': TextStyle(color: c.successText, backgroundColor: c.successSoft),
    'deletion': danger.copyWith(backgroundColor: c.dangerSoft),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.w700),
  };
}

/// [code] as colored spans in [language], or null when the language isn't
/// known or the text is too long.
TextSpan? highlightCode(
  String code, {
  required String? language,
  required TextStyle base,
  required WeCordPalette colors,
}) {
  if (language == null || code.length > maxHighlightedChars) {
    return null;
  }
  try {
    final result = _highlighter.highlight(code: code, language: language);
    final renderer = TextSpanRenderer(base, codeThemeFor(colors));
    result.render(renderer);
    return renderer.span;
  } on Object {
    return null;
  }
}
