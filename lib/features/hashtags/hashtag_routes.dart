/// Where the topics (#话题) of Moments live. A topic is a filter of the
/// Moments the person can already see, never a public page.
const String momentTopicsPath = '/moments/topics';

/// The Moments with one topic.
String momentTagPath(String tag) => '/moments/tag/${Uri.encodeComponent(tag)}';
