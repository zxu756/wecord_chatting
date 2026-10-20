/// Joins the transcripts of a browser speech recognition event's results into
/// the text heard so far.
///
/// Browsers number each phrase as its own result and a phrase's transcript is
/// just its own words, so the text is the transcripts one after another.
/// Chrome on Android differs in continuous mode: while a phrase is still being
/// recognized, every update arrives as a *new* result holding the whole phrase
/// so far ("hello", "hello how", "hello how are you"), so joining them as they
/// are says it three times. With [cumulative] a result that starts with the one
/// before it replaces it instead of following it.
///
/// The words are kept as the browser wrote them (later phrases begin with a
/// space where the language has spaces), and only the whole is trimmed.
String joinSpeechResults(
  Iterable<String> transcripts, {
  required bool cumulative,
}) {
  final parts = <String>[];
  for (final transcript in transcripts) {
    if (transcript.trim().isEmpty) {
      continue;
    }
    if (cumulative &&
        parts.isNotEmpty &&
        transcript.trim().startsWith(parts.last.trim())) {
      parts[parts.length - 1] = transcript;
    } else {
      parts.add(transcript);
    }
  }
  return parts.join().trim();
}

/// Whether [userAgent] is Chrome (or another Chromium browser) on Android,
/// whose continuous recognition repeats growing phrases (see
/// [joinSpeechResults]).
bool isAndroidBrowser(String userAgent) =>
    userAgent.contains('Android') && !userAgent.contains('Firefox');
