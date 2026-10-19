/// One line of the "What's new" popup, in both languages. The texts ship with
/// the app, so the popup works offline and needs nothing from the server.
class WhatsNewText {
  const WhatsNewText(this.en, this.zh);

  final String en;
  final String zh;

  String of({required bool chinese}) => chinese ? zh : en;
}

/// What changed in one version.
class WhatsNewEntry {
  const WhatsNewEntry({
    required this.version,
    required this.title,
    required this.items,
  });

  /// The app version (`--dart-define=APP_VERSION=...`) this is for.
  final String version;
  final WhatsNewText title;
  final List<WhatsNewText> items;
}

/// The versions that have something to say, newest last. A version with no
/// entry shows no popup. To announce a release, add its entry here, set the
/// same version in the build (`APP_VERSION`), and ship.
const whatsNewEntries = <WhatsNewEntry>[
  WhatsNewEntry(
    version: '0.2.0',
    title: WhatsNewText('What is new in WeCord', 'WeCord 有什么新功能'),
    items: [
      WhatsNewText(
        'Auto-translate: read a chat in your own language, one message or the '
            'whole chat.',
        '自动翻译：用你自己的语言阅读聊天，可以翻译单条消息，也可以翻译整个聊天。',
      ),
      WhatsNewText(
        'Your own stickers: turn any picture into a sticker and send it from '
            'the Mine tab.',
        '自己的表情：把任何图片变成表情，然后在“我的”标签里发送。',
      ),
      WhatsNewText(
        'Forms: collect answers from a group with a form in the chat.',
        '表单：在聊天里发一份表单，收集大家的回答。',
      ),
      WhatsNewText(
        'Join requests: circles can ask people to apply, and you hear back in '
            'Notifications.',
        '入圈申请：圈子可以要求申请加入，结果会出现在通知里。',
      ),
      WhatsNewText(
        'Feedback and help: tell us what went wrong, with a screenshot, from '
            'Settings.',
        '反馈与帮助：在设置里告诉我们哪里出了问题，还可以附上截图。',
      ),
    ],
  ),
];

/// The entry for [version], or null when there is none.
WhatsNewEntry? whatsNewFor(
  String version, [
  List<WhatsNewEntry> entries = whatsNewEntries,
]) {
  for (final entry in entries) {
    if (entry.version == version) {
      return entry;
    }
  }
  return null;
}
