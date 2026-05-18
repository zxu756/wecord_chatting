enum ReportReason {
  spam('spam', 'Spam'),
  harassment('harassment', 'Harassment'),
  impersonation('impersonation', 'Impersonation'),
  unsafeContent('unsafe_content', 'Unsafe content'),
  other('other', 'Other');

  const ReportReason(this.value, this.label);

  final String value;
  final String label;
}
