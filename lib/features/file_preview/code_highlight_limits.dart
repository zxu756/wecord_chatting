/// Highlighting stops past this much text (the plain view stays fast).
///
/// Apart from `code_highlight.dart` so the code viewer can read it without
/// loading the highlighter, which the web app fetches only when a code file
/// is opened.
const maxHighlightedChars = 400 * 1024;
