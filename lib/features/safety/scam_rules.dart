// Anti-scam hints (roadmap F7): the words that make a stranger's message in a
// group or circle worth a second look. Rules only, run on the device: the
// message is not sent anywhere.
//
// This is a hint, never a block. It shows under a message from someone who is
// not a friend, and says what to be careful about; the AI guard (for new
// members), AutoMod and reports do the enforcing. A link alone is not a signal
// (strangers share links all day): it counts when the address itself looks
// off (see link_risk.dart) or when the message also asks for something.

import 'package:wecord/features/safety/link_risk.dart';

/// What a message seems to be after, most worrying first.
enum ScamSignal {
  /// Asks for money, a transfer or a payment.
  payment,

  /// Asks for a verification code.
  code,

  /// A prize, a giveaway, a "you won".
  prize,

  /// Easy returns, signals, "guaranteed" profit, paid tasks.
  investment,

  /// Wants to be paid in gift cards or game credit.
  giftCard,

  /// Claims to be support or an official and says the account has a problem.
  impersonation,

  /// A link that looks off.
  link,
}

final _payment = RegExp(
  r'(收款|转账|汇款|打款|打钱|付款|代付|垫付|保证金|手续费|解冻金|扫码支付|银行卡号|先付|预付|'
  r'transfer (me )?(the )?(money|funds)|send (me )?(the )?(money|funds|cash|payment)|wire (me|the)|'
  r'bank account|pay me|western union|moneygram|advance fee|deposit fee|processing fee|'
  r'\b(venmo|cash ?app|zelle)\b|paypal me)',
  caseSensitive: false,
);

final _codeAsk = RegExp(
  r'((验证码|校验码|动态码|短信码|安全码).{0,10}(发|给|告诉|提供|转|报|截图|念))|'
  r'((发|给|告诉|提供|转|报|截图|念).{0,10}(验证码|校验码|动态码|短信码|安全码))|'
  r'((send|give|tell|share|forward|read|text).{0,24}(verification|security|one[- ]time|2fa|login|sms)? ?(code|otp))|'
  r'((verification|security|one[- ]time|2fa|login|sms) ?(code|otp).{0,24}(send|give|tell|share|forward|read))',
  caseSensitive: false,
);

final _prize = RegExp(
  r'(中奖|恭喜.{0,8}(获得|抽中|中)|领奖|抽中|领取.{0,6}(红包|奖品|礼品)|免费领|空投|'
  r'you (have )?won|you.?re (a )?winner|claim your (prize|reward|gift)|free giveaway|airdrop)',
  caseSensitive: false,
);

final _investment = RegExp(
  r'(带单|稳赚|高回报|日收益|内幕消息|荐股|刷单|兼职.{0,10}(日结|日赚|日入)|躺赚|'
  r'guaranteed (returns?|profit)|double your (money|crypto|bitcoin)|trading signals?|'
  r'passive income|crypto (investment|giveaway)|investment opportunity)',
  caseSensitive: false,
);

final _giftCard = RegExp(
  r'(礼品卡|点卡|游戏点卡|代充|gift ?cards?|steam cards?|itunes cards?|google play cards?)',
  caseSensitive: false,
);

final _impersonation = RegExp(
  r'((官方|平台|系统).{0,4}(客服|通知|审核)|客服.{0,6}(联系|通知)|账号.{0,6}(冻结|异常|封禁|被盗|风险)|'
  r'(customer|official) (service|support)|account (has been )?(suspended|locked|compromised)|'
  r'unusual (sign[- ]?in|activity)|verify your account)',
  caseSensitive: false,
);

final _url = RegExp(r'(https?://|www\.)[^\s<>]+', caseSensitive: false);

/// The most worrying thing [text] seems to ask for, or null when it is
/// nothing special.
ScamSignal? detectScamSignal(String text) {
  final body = text.trim();
  if (body.isEmpty) {
    return null;
  }
  if (_payment.hasMatch(body)) {
    return ScamSignal.payment;
  }
  if (_codeAsk.hasMatch(body)) {
    return ScamSignal.code;
  }
  if (_prize.hasMatch(body)) {
    return ScamSignal.prize;
  }
  if (_investment.hasMatch(body)) {
    return ScamSignal.investment;
  }
  if (_giftCard.hasMatch(body)) {
    return ScamSignal.giftCard;
  }
  if (_impersonation.hasMatch(body)) {
    return ScamSignal.impersonation;
  }
  for (final match in _url.allMatches(body)) {
    var address = match.group(0)!.replaceAll(RegExp(r'[).,;!?，。！？]+$'), '');
    if (!address.toLowerCase().startsWith('http')) {
      address = 'https://$address';
    }
    if (assessLink(address).isRisky) {
      return ScamSignal.link;
    }
  }
  return null;
}
