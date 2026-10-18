/// Whether a browser is Safari on an iPhone or iPad (Chrome, Firefox and
/// Edge on iOS are skipped: their own menus differ). iPadOS 13+ reports a
/// Mac user agent, told apart by its touch screen.
bool isIosSafariUserAgent(String userAgent, {int maxTouchPoints = 0}) {
  final iPhoneOrPod = RegExp(r'iPhone|iPod').hasMatch(userAgent);
  final iPad =
      userAgent.contains('iPad') ||
      (userAgent.contains('Macintosh') && maxTouchPoints > 1);
  if (!iPhoneOrPod && !iPad) {
    return false;
  }
  return !RegExp(r'CriOS|FxiOS|EdgiOS|OPiOS|GSA/').hasMatch(userAgent);
}

/// The tab title with the unread [count] in front ("(3) WeCord"), the
/// plain [base] at zero; counts above 99 read "99+".
String titleWithUnread(String base, int count) {
  if (count <= 0) {
    return base;
  }
  return '(${count > 99 ? '99+' : count}) $base';
}
