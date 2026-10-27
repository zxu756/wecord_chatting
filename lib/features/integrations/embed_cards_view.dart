// How the cards of webhook, RSS and GitHub messages plug into the chat page
// (see "Chat page extension points" in docs/design/wecord-design-language.md).
// Nothing here edits a chat page file beyond one line in message_content.dart
// that hides the one-line summary a card-only message carries as its text:
//
//  * [embedCardsFooterEntry] draws the cards inside the bubble, then the link
//    buttons under them.
// It is listed in bubble_footer_registrations.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_markdown_text.dart'
    show linkLauncherProvider;
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/interactions/components_view.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message_embeds.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The cards of a webhook, feed or GitHub message, inside its bubble.
final embedCardsFooterEntry = BubbleFooterEntry.inside(
  id: 'embed-cards',
  order: 140,
  build: (ctx) {
    final embeds = ctx.message.embeds;
    if (embeds == null || ctx.isRecalled) {
      return const [];
    }
    return [EmbedCardsView(embeds: embeds, messageId: ctx.message.id)];
  },
);

/// The widest a card gets.
const embedCardMaxWidth = 420.0;

/// The cards of one message, one under the other, and its link buttons.
class EmbedCardsView extends StatelessWidget {
  const EmbedCardsView({
    required this.embeds,
    required this.messageId,
    super.key,
  });

  final MessageEmbeds embeds;
  final String messageId;

  @override
  Widget build(BuildContext context) {
    final components = embeds.components;
    return Padding(
      key: const ValueKey('embed-cards'),
      padding: EdgeInsets.only(top: embeds.summary ? 0 : 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: embedCardMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final card in embeds.cards) ...[
              EmbedCardView(card: card),
              const SizedBox(height: 6),
            ],
            if (components != null)
              MessageComponentsView(
                components: components,
                targetId: messageId,
              ),
          ],
        ),
      ),
    );
  }
}

/// One card: a stripe in its color along the side, an author, a title that
/// may be a link, a description, fields, a picture and a footer. Every text is
/// drawn as plain text; a link asks before it opens.
class EmbedCardView extends ConsumerWidget {
  const EmbedCardView({required this.card, super.key});

  final EmbedCard card;

  static const _stripe = 4.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final stripe = card.color == null ? c.accent : Color(card.color!);
    void open(Uri uri) {
      ref.read(linkLauncherProvider)(context, uri).catchError((Object _) {});
    }

    final body = <Widget>[
      if (card.author case final author?)
        _AuthorRow(author: author, onOpen: open),
      if (card.title case final title?)
        Padding(
          // A link is grown to a comfortable tap size, which is the space.
          padding: EdgeInsets.only(
            top: card.author == null || card.author!.url != null ? 0 : 6,
          ),
          child: card.url == null
              ? Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                )
              : _LinkText(
                  text: title,
                  uri: card.url!,
                  onOpen: open,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: c.accentText,
                  ),
                ),
        ),
      if (card.description case final description?)
        Padding(
          padding: EdgeInsets.only(
            top: card.title != null && card.url != null ? 0 : 6,
          ),
          child: Text(
            description,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
          ),
        ),
      if (card.fields.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _Fields(fields: card.fields),
        ),
      if (card.image case final image?)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.md),
            // A picture the sender chose: still under reduced motion.
            child: MotionSafeImage.network(
              image.toString(),
              playButton: false,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      if (card.footer != null || card.timestamp != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _FooterRow(footer: card.footer, timestamp: card.timestamp),
        ),
    ];

    final thumbnail = card.thumbnail;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: body,
    );

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          border: Border.all(color: c.lineSoft),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_stripe + 12, 10, 12, 11),
                child: thumbnail == null
                    ? content
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: content),
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(WeCordRadii.md),
                            child: MotionSafeImage.network(
                              thumbnail.toString(),
                              playButton: false,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 56, height: 56),
                            ),
                          ),
                        ],
                      ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _stripe,
                child: ExcludeSemantics(child: ColoredBox(color: stripe)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text that opens a link when pressed.
class _LinkText extends StatelessWidget {
  const _LinkText({
    required this.text,
    required this.uri,
    required this.onOpen,
    required this.style,
  });

  final String text;
  final Uri uri;
  final void Function(Uri uri) onOpen;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return WeCordPressable(
      onPressed: () => onOpen(uri),
      pressedScale: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      semanticLabel: text,
      hint: tr('Opens {site}', {'site': uri.host}),
      excludeSemantics: true,
      builder: (context, states) => Text(
        text,
        style: style.copyWith(
          decoration: states.contains(WidgetState.hovered)
              ? TextDecoration.underline
              : null,
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.author, required this.onOpen});

  final EmbedAuthor author;
  final void Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: author.url == null ? c.muted : c.accentText,
    );
    final name = Text(author.name, style: style);
    return Row(
      children: [
        if (author.iconUrl case final icon?) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
            child: MotionSafeImage.network(
              icon.toString(),
              playButton: false,
              width: 20,
              height: 20,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox(width: 20, height: 20),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: author.url == null
              ? name
              : _LinkText(
                  text: author.name,
                  uri: author.url!,
                  onOpen: onOpen,
                  style: style,
                ),
        ),
      ],
    );
  }
}

/// Fields one under the other; neighbours marked inline sit side by side as
/// far as there is room.
class _Fields extends StatelessWidget {
  const _Fields({required this.fields});

  final List<EmbedField> fields;

  @override
  Widget build(BuildContext context) {
    final rows = <List<EmbedField>>[];
    for (final field in fields) {
      if (field.inline && rows.isNotEmpty && rows.last.first.inline) {
        rows.last.add(field);
      } else {
        rows.add([field]);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: rows[i].first.inline
                ? Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      for (final field in rows[i])
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 80,
                            maxWidth: 170,
                          ),
                          child: _FieldView(field: field),
                        ),
                    ],
                  )
                : _FieldView(field: rows[i].first),
          ),
      ],
    );
  }
}

class _FieldView extends StatelessWidget {
  const _FieldView({required this.field});

  final EmbedField field;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.name,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          field.value,
          style: TextStyle(fontSize: 13.5, height: 1.35, color: c.ink),
        ),
      ],
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({this.footer, this.timestamp});

  final EmbedFooter? footer;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final localizations = MaterialLocalizations.of(context);
    final when = timestamp == null
        ? null
        : '${localizations.formatShortDate(timestamp!)} '
              '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp!))}';
    final text = [?footer?.text, ?when].join(' · ');
    return Row(
      children: [
        if (footer?.iconUrl case final icon?) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
            child: MotionSafeImage.network(
              icon.toString(),
              playButton: false,
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox(width: 16, height: 16),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.3, color: c.subtle),
          ),
        ),
      ],
    );
  }
}
