// How risky a link looks, from the address alone: no network, no model, and
// nothing about the message it came in. These are the same rules, with the
// same numbers, as supabase/functions/link-preview/link_risk.ts; both run
// against the cases in test/fixtures/link_risk_cases.json, so they cannot
// drift apart. When you change one, change the other.
//
// A score is added up from signals and read as:
//   >= 5 high      (a warning page before the link opens)
//   >= 2 caution   (a note on the preview card)
//   else none
// A link whose host is one of the sites in [_knownSites] or [_brands] is never
// scored for its words; only a disguised address (user@host, an IP) counts.

import 'package:flutter/foundation.dart';

enum LinkRiskLevel {
  none,
  caution,
  high;

  static LinkRiskLevel fromName(Object? name) =>
      values.firstWhere((level) => level.name == name, orElse: () => none);
}

/// What made a link look risky. The names match the server's.
enum LinkRiskReason {
  credentialsInUrl('credentials_in_url'),
  ipAddress('ip_address'),
  punycode('punycode'),
  shortLink('short_link'),
  lookalikeBrand('lookalike_brand'),
  brandInSubdomain('brand_in_subdomain'),
  riskyTld('risky_tld'),
  loginWords('login_words'),
  manySubdomains('many_subdomains'),
  manyHyphens('many_hyphens'),
  downloadFile('download_file'),
  plainHttpLogin('plain_http_login'),
  redirectsRisky('redirects_risky');

  const LinkRiskReason(this.code);

  final String code;

  static LinkRiskReason? fromCode(Object? code) {
    for (final reason in values) {
      if (reason.code == code) {
        return reason;
      }
    }
    return null;
  }
}

@immutable
class LinkRisk {
  const LinkRisk({
    required this.level,
    this.score = 0,
    this.reasons = const [],
  });

  /// From the `risk` object of the link-preview function.
  factory LinkRisk.fromJson(Object? json) {
    if (json is! Map) {
      return LinkRisk.none;
    }
    return LinkRisk(
      level: LinkRiskLevel.fromName(json['level']),
      reasons: [
        for (final code in (json['reasons'] as List? ?? const []))
          ?LinkRiskReason.fromCode(code),
      ],
    );
  }

  static const none = LinkRisk(level: LinkRiskLevel.none);

  final LinkRiskLevel level;
  final int score;
  final List<LinkRiskReason> reasons;

  bool get isHigh => level == LinkRiskLevel.high;
  bool get isRisky => level != LinkRiskLevel.none;

  /// The worse of two.
  LinkRisk worst(LinkRisk other) =>
      other.level.index > level.index ? other : this;
}

const highScore = 5;
const cautionScore = 2;

const _brands = <String, List<String>>{
  'paypal': ['paypal.com', 'paypal.me'],
  'apple': ['apple.com', 'icloud.com'],
  'icloud': ['icloud.com', 'apple.com'],
  'microsoft': [
    'microsoft.com',
    'live.com',
    'office.com',
    'outlook.com',
    'microsoftonline.com',
  ],
  'google': ['google.com', 'gmail.com', 'goo.gl', 'google.cn'],
  'amazon': [
    'amazon.com',
    'amazon.co.uk',
    'amazon.de',
    'amazon.fr',
    'amazon.co.jp',
    'amazon.in',
    'amazon.ca',
    'amazon.com.au',
    'amazon.cn',
  ],
  'alipay': ['alipay.com', 'antgroup.com'],
  'wechat': ['wechat.com', 'weixin.qq.com', 'qq.com'],
  'weixin': ['weixin.qq.com', 'wechat.com', 'qq.com'],
  'taobao': ['taobao.com', 'tmall.com', 'alibaba.com', 'aliexpress.com'],
  'binance': ['binance.com', 'binance.us', 'binance.org'],
  'coinbase': ['coinbase.com'],
  'metamask': ['metamask.io'],
  'discord': ['discord.com', 'discord.gg', 'discordapp.com', 'discord.media'],
  'steam': ['steampowered.com', 'steamcommunity.com', 'steamstatic.com'],
  'telegram': ['telegram.org', 't.me', 'telegram.me'],
  'whatsapp': ['whatsapp.com', 'whatsapp.net', 'wa.me'],
  'netflix': ['netflix.com'],
  'instagram': ['instagram.com'],
  'facebook': ['facebook.com', 'fb.com', 'fb.me', 'facebook.net'],
  'tiktok': ['tiktok.com'],
  'github': ['github.com', 'github.io', 'githubusercontent.com'],
  'wecord': ['jokebear.fyi'],
};

const _knownSites = [
  'wikipedia.org',
  'youtube.com',
  'youtu.be',
  'twitter.com',
  'x.com',
  'reddit.com',
  'linkedin.com',
  'baidu.com',
  'bilibili.com',
  'zhihu.com',
  'weibo.com',
  'apple.com',
  'mozilla.org',
  'cloudflare.com',
];

const _brandFiller = [
  'secure',
  'security',
  'login',
  'signin',
  'verify',
  'verification',
  'account',
  'support',
  'help',
  'service',
  'services',
  'official',
  'wallet',
  'pay',
  'id',
  'app',
  'web',
  'online',
  'update',
  'customer',
  'center',
  'centre',
  'mail',
  'store',
  'shop',
  'com',
  'net',
  'org',
];

const _shorteners = [
  'bit.ly',
  't.co',
  'tinyurl.com',
  'is.gd',
  'cutt.ly',
  'rb.gy',
  't.cn',
  'url.cn',
  'dwz.cn',
  'ow.ly',
  'buff.ly',
  'shorturl.at',
  'tiny.cc',
  's.id',
  'v.gd',
  'lnkd.in',
  'goo.gl',
  'reurl.cc',
  'suo.im',
];

const _riskyTlds = [
  'zip',
  'mov',
  'top',
  'xyz',
  'click',
  'gq',
  'tk',
  'ml',
  'cf',
  'ga',
  'icu',
  'buzz',
  'rest',
  'cyou',
  'sbs',
  'cfd',
  'monster',
  'work',
  'loan',
  'country',
];

const _loginWords = [
  'login',
  'signin',
  'verify',
  'verification',
  'secure',
  'account',
  'wallet',
  'claim',
  'airdrop',
  'prize',
  'reward',
  'bonus',
  'giftcard',
  'recover',
  'unlock',
  'suspended',
  'billing',
  'password',
  'refund',
];

const _downloadExtensions = [
  '.apk',
  '.exe',
  '.msi',
  '.scr',
  '.bat',
  '.cmd',
  '.dmg',
  '.pkg',
  '.jar',
  '.ps1',
];

const _secondLevels = ['co', 'com', 'net', 'org', 'gov', 'edu', 'ac'];

bool _hostMatches(String host, List<String> domains) =>
    domains.any((domain) => host == domain || host.endsWith('.$domain'));

/// The part of [host] a person registered: "evil.example.co.uk" gives
/// "example.co.uk".
@visibleForTesting
String registrableDomain(String host) {
  final labels = host.split('.');
  if (labels.length <= 2) {
    return host;
  }
  final tld = labels.last;
  final second = labels[labels.length - 2];
  if (tld.length == 2 && _secondLevels.contains(second)) {
    return labels.sublist(labels.length - 3).join('.');
  }
  return labels.sublist(labels.length - 2).join('.');
}

bool _isIpHost(String host) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');

final _fillerLongestFirst = [..._brandFiller]
  ..sort((a, b) => b.length.compareTo(a.length));

/// Whether [label] is only [brand] and filler words (digits that stand for
/// letters turned back into them).
bool _reducesToBrand(String label, String brand) {
  final plain = label.replaceAll('-', '');
  final variants = <String>{
    plain.replaceAll(RegExp(r'[0-9]'), ''),
    plain
        .replaceAll('0', 'o')
        .replaceAll('1', 'l')
        .replaceAll('3', 'e')
        .replaceAll('5', 's')
        .replaceAll('rn', 'm')
        .replaceAll('vv', 'w'),
  };
  for (final variant in variants) {
    if (!variant.contains(brand)) {
      continue;
    }
    var rest = variant.split(brand).join();
    for (final word in _fillerLongestFirst) {
      rest = rest.split(word).join();
    }
    if (rest.isEmpty) {
      return true;
    }
  }
  return false;
}

/// Scores [rawUrl]. Anything that is not an http(s) address with a host
/// scores nothing.
LinkRisk assessLink(String rawUrl) {
  final Uri url;
  try {
    url = Uri.parse(rawUrl.trim());
  } on FormatException {
    return LinkRisk.none;
  }
  if ((url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty) {
    return LinkRisk.none;
  }
  var host = url.host.toLowerCase();
  if (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }

  final reasons = <LinkRiskReason>[];
  var score = 0;
  void add(LinkRiskReason reason, int points) {
    reasons.add(reason);
    score += points;
  }

  // "https://paypal.com@evil.example": the part before the @ is not the host.
  if (url.userInfo.isNotEmpty) {
    add(LinkRiskReason.credentialsInUrl, url.userInfo.contains('.') ? 5 : 2);
  }

  final ipHost = _isIpHost(host);
  if (ipHost) {
    add(LinkRiskReason.ipAddress, 3);
  }

  final labels = host.split('.');
  // Dart keeps a unicode host as percent-encoded text; the server's URL
  // parser turns it into "xn--" labels. Both count as an unusual address.
  final nonAscii = host.contains('%') || host.runes.any((rune) => rune > 127);
  if (labels.any((label) => label.startsWith('xn--')) || nonAscii) {
    add(LinkRiskReason.punycode, 3);
  }

  final known =
      _hostMatches(host, _knownSites) ||
      _brands.values.any((domains) => _hostMatches(host, domains));

  final path = '${url.path}${url.hasQuery ? '?${url.query}' : ''}'
      .toLowerCase();
  bool wordsIn(String text) => _loginWords.any(text.contains);
  var loginWords = false;

  if (!known) {
    if (!ipHost) {
      final registrableLabels = registrableDomain(host).split('.');
      for (final MapEntry(key: brand, value: domains) in _brands.entries) {
        if (_hostMatches(host, domains)) {
          continue;
        }
        final index = labels.indexWhere(
          (label) => _reducesToBrand(label, brand),
        );
        if (index == -1) {
          continue;
        }
        // In the part the owner chose it is an imitation; in a subdomain it
        // is a disguise.
        final inRegistrable = index >= labels.length - registrableLabels.length;
        add(
          inRegistrable
              ? LinkRiskReason.lookalikeBrand
              : LinkRiskReason.brandInSubdomain,
          inRegistrable ? 3 : 5,
        );
        break;
      }
    }

    if (wordsIn(host)) {
      add(LinkRiskReason.loginWords, 2);
      loginWords = true;
    } else if (wordsIn(path)) {
      add(LinkRiskReason.loginWords, 1);
      loginWords = true;
    }

    if (labels.length > 5) {
      add(LinkRiskReason.manySubdomains, 1);
    }
    if ('-'.allMatches(host.replaceAll('xn--', '')).length >= 3) {
      add(LinkRiskReason.manyHyphens, 1);
    }
    if (_riskyTlds.contains(labels.last)) {
      add(LinkRiskReason.riskyTld, 1);
    }
  }

  if (_shorteners.contains(host)) {
    add(LinkRiskReason.shortLink, 2);
  }

  final pathOnly = url.path.toLowerCase();
  if (_downloadExtensions.any(pathOnly.endsWith)) {
    add(LinkRiskReason.downloadFile, 3);
  }

  if (url.scheme == 'http' && loginWords) {
    add(LinkRiskReason.plainHttpLogin, 1);
  }

  return LinkRisk(
    level: score >= highScore
        ? LinkRiskLevel.high
        : score >= cautionScore
        ? LinkRiskLevel.caution
        : LinkRiskLevel.none,
    score: score,
    reasons: reasons,
  );
}

/// The host to show people for [uri]: without "www.".
String displayHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}
