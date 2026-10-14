import 'package:wecord/shared/l10n/l10n.dart';

enum ReportReason {
  spam('spam', 'Spam'),
  harassment('harassment', 'Harassment'),
  impersonation('impersonation', 'Impersonation'),
  unsafeContent('unsafe_content', 'Unsafe content'),
  other('other', 'Other');

  const ReportReason(this.value, this._label);

  final String value;
  final String _label;

  String get label => tr(_label);
}
