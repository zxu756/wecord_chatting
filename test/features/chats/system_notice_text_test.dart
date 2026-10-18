import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/system_notice_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  test('English stays as the server wrote it', () {
    expect(systemNoticeText('Ada pinned a message.'), 'Ada pinned a message.');
    expect(cardBodyText('Contact card: Ada'), 'Contact card: Ada');
  });

  test('notices read in Chinese', () {
    AppStrings.isChinese = true;
    expect(systemNoticeText('Ada pinned a message.'), 'Ada 置顶了一条消息');
    expect(systemNoticeText('Ada started a call.'), 'Ada 发起了通话');
    expect(
      systemNoticeText('Ada started a call that lasted 1 hour 5 minutes.'),
      'Ada 发起的通话持续了 1 小时 5 分钟',
    );
    expect(
      systemNoticeText('Ada started a call that lasted a few seconds.'),
      'Ada 发起的通话持续了 几秒钟',
    );
    expect(systemNoticeText('Something else'), 'Something else');
  });

  test('cards read in Chinese', () {
    AppStrings.isChinese = true;
    expect(cardBodyText('📍 Live location'), '📍 实时位置');
    expect(cardBodyText('Contact card: Ada'), '名片：Ada');
    expect(cardBodyText('Chat history: Trip'), 'Trip的聊天记录');
    expect(cardBodyText('📝 Untitled note'), '📝 未命名笔记');
    expect(cardBodyText('Contact card: '), 'Contact card: ');
    expect(cardBodyText('hello'), 'hello');
  });
}
