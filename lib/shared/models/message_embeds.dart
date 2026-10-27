/// The cards a webhook, an RSS feed or a GitHub connection puts on a message
/// (messages.embeds, see migration 202610290200). The server cleans them
/// before storing; this reads them again defensively - anything that does not
/// fit the rules is left out rather than drawn - so a row from an older or
/// hostile server can not show a link to a script, a giant picture list or an
/// endless card. Every text is plain text to the app: nothing here is ever
/// parsed as markdown or HTML.
library;

import 'package:flutter/foundation.dart';
import 'package:wecord/shared/models/message_components.dart';

/// The server's limits (migration 202610290200); the app draws up to them.
abstract final class EmbedLimits {
  static const maxCards = 3;
  static const maxFields = 10;
  static const maxTitle = 120;
  static const maxDescription = 1500;
  static const maxAuthor = 60;
  static const maxFieldName = 60;
  static const maxFieldValue = 300;
  static const maxFooter = 100;
}

/// The name and picture of whoever a card is about.
@immutable
class EmbedAuthor {
  const EmbedAuthor({required this.name, this.url, this.iconUrl});

  final String name;
  final Uri? url;
  final Uri? iconUrl;
}

@immutable
class EmbedField {
  const EmbedField({
    required this.name,
    required this.value,
    this.inline = false,
  });

  final String name;
  final String value;

  /// May sit beside another inline field.
  final bool inline;
}

@immutable
class EmbedFooter {
  const EmbedFooter({required this.text, this.iconUrl});

  final String text;
  final Uri? iconUrl;
}

/// One card.
@immutable
class EmbedCard {
  const EmbedCard({
    this.title,
    this.url,
    this.description,
    this.color,
    this.author,
    this.fields = const [],
    this.image,
    this.thumbnail,
    this.footer,
    this.timestamp,
  });

  /// Null when [json] holds nothing the app may draw.
  static EmbedCard? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final title = cleanComponentText(json['title'], max: EmbedLimits.maxTitle);
    final description = _block(json['description'], EmbedLimits.maxDescription);
    final author = _author(json['author']);
    final fields = <EmbedField>[];
    if (json['fields'] is List) {
      for (final raw in json['fields'] as List) {
        final field = _field(raw);
        if (field != null && fields.length < EmbedLimits.maxFields) {
          fields.add(field);
        }
      }
    }
    final footer = _footer(json['footer']);
    if (title == null &&
        description == null &&
        author == null &&
        fields.isEmpty &&
        footer == null) {
      return null;
    }
    return EmbedCard(
      title: title,
      url: safeComponentUri(json['url']),
      description: description,
      color: _color(json['color']),
      author: author,
      fields: fields,
      image: _picture(json['image']),
      thumbnail: _picture(json['thumbnail']),
      footer: footer,
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)?.toLocal()
          : null,
    );
  }

  final String? title;

  /// An https address, already checked by [safeComponentUri].
  final Uri? url;
  final String? description;

  /// The stripe along the card's side.
  final int? color;
  final EmbedAuthor? author;
  final List<EmbedField> fields;
  final Uri? image;
  final Uri? thumbnail;
  final EmbedFooter? footer;
  final DateTime? timestamp;

  /// Something the person reads, for a screen reader to start with.
  String get semanticText => [
    ?author?.name,
    ?title,
    ?description,
    for (final field in fields) '${field.name}: ${field.value}',
    ?footer?.text,
  ].join('. ');

  static String? _block(Object? value, int max) {
    if (value is! String) {
      return null;
    }
    // Line breaks are kept; other control and direction characters are not.
    final cleaned = value
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(
          RegExp(
            '[\\u0000-\\u0009\\u000b\\u000c\\u000e-\\u001f\\u007f'
            '\\u200b-\\u200f\\u202a-\\u202e\\u2060-\\u2064\\u2066-\\u2069'
            '\\ufeff]',
          ),
          '',
        )
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }
    final runes = cleaned.runes;
    return runes.length > max
        ? '${String.fromCharCodes(runes.take(max - 1))}…'
        : cleaned;
  }

  static EmbedAuthor? _author(Object? json) {
    if (json is! Map) {
      return null;
    }
    final name = cleanComponentText(json['name'], max: EmbedLimits.maxAuthor);
    if (name == null) {
      return null;
    }
    return EmbedAuthor(
      name: name,
      url: safeComponentUri(json['url']),
      iconUrl: safeComponentUri(json['icon_url']),
    );
  }

  static EmbedField? _field(Object? json) {
    if (json is! Map) {
      return null;
    }
    final name = cleanComponentText(
      json['name'],
      max: EmbedLimits.maxFieldName,
    );
    final value = _block(json['value'], EmbedLimits.maxFieldValue);
    if (name == null || value == null) {
      return null;
    }
    return EmbedField(name: name, value: value, inline: json['inline'] == true);
  }

  static EmbedFooter? _footer(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = cleanComponentText(json['text'], max: EmbedLimits.maxFooter);
    if (text == null) {
      return null;
    }
    return EmbedFooter(text: text, iconUrl: safeComponentUri(json['icon_url']));
  }

  static Uri? _picture(Object? json) {
    if (json is Map) {
      return safeComponentUri(json['url']);
    }
    return safeComponentUri(json);
  }

  /// `#rrggbb` as an opaque color value.
  static int? _color(Object? value) {
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return 0xFF000000 | int.parse(value.substring(1), radix: 16);
  }
}

/// All the cards of a message, and the link buttons under them.
@immutable
class MessageEmbeds {
  const MessageEmbeds({
    required this.cards,
    this.components,
    this.summary = false,
  });

  /// Null when [json] holds nothing the app may draw.
  static MessageEmbeds? maybeFromJson(Object? json) {
    if (json is! Map || json['cards'] is! List) {
      return null;
    }
    final cards = <EmbedCard>[];
    for (final raw in json['cards'] as List) {
      final card = EmbedCard.maybeFromJson(raw);
      if (card != null && cards.length < EmbedLimits.maxCards) {
        cards.add(card);
      }
    }
    if (cards.isEmpty) {
      return null;
    }
    return MessageEmbeds(
      cards: cards,
      components: MessageComponents.maybeFromJson(json['components']),
      summary: json['summary'] == true,
    );
  }

  final List<EmbedCard> cards;

  /// Link buttons under the cards.
  final MessageComponents? components;

  /// The message's text is only a one-line summary of the cards (for the
  /// chat list and notifications): the thread draws the cards instead.
  final bool summary;
}
