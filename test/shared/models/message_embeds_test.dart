import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_embeds.dart';

Map<String, dynamic> sampleEmbedsJson() => {
  'cards': [
    {
      'title': 'Deploy finished',
      'url': 'https://ci.example.com/run/12',
      'description': 'main to production\nin 4m 12s',
      'color': '#2da44e',
      'author': {
        'name': 'wecord/app',
        'url': 'https://github.com/wecord/app',
        'icon_url': 'https://example.com/a.png',
      },
      'fields': [
        {'name': 'Branch', 'value': 'main', 'inline': true},
        {'name': 'Tests', 'value': '778 passed', 'inline': true},
        {'name': 'Notes', 'value': 'All good'},
      ],
      'image': {'url': 'https://example.com/chart.png'},
      'thumbnail': {'url': 'https://example.com/t.png'},
      'footer': {'text': 'ada', 'icon_url': 'https://example.com/f.png'},
      'timestamp': '2026-10-28T10:00:00Z',
    },
  ],
  'components': [
    [
      {'type': 'link', 'label': 'Open run', 'url': 'https://ci.example.com/12'},
    ],
  ],
  'summary': true,
};

void main() {
  test('a server row becomes cards with everything a card has', () {
    final embeds = MessageEmbeds.maybeFromJson(sampleEmbedsJson())!;
    expect(embeds.summary, isTrue);
    expect(embeds.components?.rows.single.length, 1);
    final card = embeds.cards.single;
    expect(card.title, 'Deploy finished');
    expect(card.url?.host, 'ci.example.com');
    expect(card.description, 'main to production\nin 4m 12s');
    expect(card.color, 0xFF2DA44E);
    expect(card.author?.name, 'wecord/app');
    expect(card.author?.url?.host, 'github.com');
    expect(card.author?.iconUrl?.host, 'example.com');
    expect(card.fields.map((f) => f.name), ['Branch', 'Tests', 'Notes']);
    expect(card.fields.map((f) => f.inline), [true, true, false]);
    expect(card.image?.path, '/chart.png');
    expect(card.thumbnail?.path, '/t.png');
    expect(card.footer?.text, 'ada');
    expect(card.timestamp?.toUtc(), DateTime.utc(2026, 10, 28, 10));
    expect(card.semanticText, contains('Deploy finished'));
    expect(card.semanticText, contains('Branch: main'));
  });

  test('nothing is drawn for no cards or the wrong shape', () {
    expect(MessageEmbeds.maybeFromJson(null), isNull);
    expect(MessageEmbeds.maybeFromJson('x'), isNull);
    expect(MessageEmbeds.maybeFromJson(<Object?>[]), isNull);
    expect(MessageEmbeds.maybeFromJson({'cards': 'x'}), isNull);
    expect(MessageEmbeds.maybeFromJson({'cards': []}), isNull);
    expect(
      MessageEmbeds.maybeFromJson({
        'cards': ['x', 5, null, <String, Object?>{}],
      }),
      isNull,
    );
    // A card of only an address or a color says nothing.
    expect(
      MessageEmbeds.maybeFromJson({
        'cards': [
          {'url': 'https://example.com', 'color': '#ffffff'},
        ],
      }),
      isNull,
    );
  });

  test('links and pictures that are not safe https are dropped', () {
    final card = EmbedCard.maybeFromJson({
      'title': 'T',
      'url': 'javascript:alert(1)',
      'author': {
        'name': 'A',
        'url': 'http://example.com/',
        'icon_url': 'https://127.0.0.1/a.png',
      },
      'image': {'url': 'data:image/png;base64,AAAA'},
      'thumbnail': 'https://10.0.0.5/t.png',
      'footer': {'text': 'F', 'icon_url': 'file:///etc/passwd'},
    })!;
    expect(card.url, isNull);
    expect(card.author?.url, isNull);
    expect(card.author?.iconUrl, isNull);
    expect(card.image, isNull);
    expect(card.thumbnail, isNull);
    expect(card.footer?.iconUrl, isNull);
  });

  test(
    'colors, texts and limits hold even when the server does not keep them',
    () {
      expect(
        EmbedCard.maybeFromJson({'title': 'T', 'color': 'red'})!.color,
        isNull,
      );
      expect(
        EmbedCard.maybeFromJson({'title': 'T', 'color': '#12345'})!.color,
        isNull,
      );
      // A title that is too long is not drawn; a description is cut short.
      expect(
        EmbedCard.maybeFromJson({
          'title': 'x' * 121,
          'description': 'd',
        })!.title,
        isNull,
      );
      final cut = EmbedCard.maybeFromJson({'description': 'd' * 2000})!;
      expect(cut.description!.runes.length, EmbedLimits.maxDescription);
      expect(cut.description, endsWith('…'));
      // Hidden characters go; line breaks stay.
      final plain = EmbedCard.maybeFromJson({
        'title': '\u202eEvil\u200b',
        'description': 'a\r\nb\u0007c',
      })!;
      expect(plain.title, 'Evil');
      expect(plain.description, 'a\nbc');
      // Fields: bad ones are skipped, at most ten are kept.
      final fields = EmbedCard.maybeFromJson({
        'title': 'T',
        'fields': [
          'x',
          {'name': '', 'value': 'v'},
          {'name': 'n', 'value': ''},
          for (var i = 0; i < 20; i++) {'name': 'f$i', 'value': 'v$i'},
        ],
      })!.fields;
      expect(fields.length, EmbedLimits.maxFields);
      expect(fields.first.name, 'f0');
      // At most three cards.
      final many = MessageEmbeds.maybeFromJson({
        'cards': [
          for (var i = 0; i < 8; i++) {'title': 'Card $i'},
        ],
      })!;
      expect(many.cards.length, EmbedLimits.maxCards);
      // Markup stays markup: nothing is parsed.
      expect(
        EmbedCard.maybeFromJson({'title': '<b>hi</b> **x**'})!.title,
        '<b>hi</b> **x**',
      );
    },
  );

  test('messages carry embeds and keep them when copied', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'type': 'text',
      'body': 'Deploy finished',
      'created_at': '2026-10-28T10:00:00Z',
      'embeds': sampleEmbedsJson(),
    });
    expect(message.embeds?.cards.length, 1);
    expect(message.copyWith(body: 'x').embeds?.cards.length, 1);
    expect(message.copyWith(embeds: null).embeds, isNull);
    expect(
      ChatMessage.fromJson({
        'id': 'm2',
        'conversation_id': 'c1',
        'sender_id': 'u',
        'type': 'text',
        'body': 'hi',
        'created_at': '2026-10-28T10:00:00Z',
      }).embeds,
      isNull,
    );
  });
}
