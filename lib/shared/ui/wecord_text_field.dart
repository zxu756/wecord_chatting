import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/shared/theme/wecord_field_border.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// A filled, borderless text field with its label above it (13/600,
/// muted), as on the sign-in page. On a panel it fills with the raised
/// color; on [onPaper] pages it is white with a hairline edge. Focus draws
/// an accent edge.
class WeCordTextField extends StatelessWidget {
  const WeCordTextField({
    this.controller,
    this.label,
    this.labelTrailing,
    this.hint,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.onPaper = false,
    this.fieldKey,
    super.key,
  });

  final TextEditingController? controller;

  /// Shown above the field.
  final String? label;

  /// Beside the label on the right, e.g. a "Forgot password?" link.
  final Widget? labelTrailing;

  final String? hint;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  /// For fields on the paper background (sign in, settings pages).
  final bool onPaper;

  /// Key for the inner [TextField], for tests.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    const radius = BorderRadius.all(Radius.circular(WeCordRadii.lg));
    WeCordFieldBorder border(Color color, double width) => WeCordFieldBorder(
      borderRadius: radius,
      borderSide: width == 0
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );
    final idle = onPaper ? border(c.line, 1) : border(c.raised, 0);

    final field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      style: TextStyle(fontSize: 16, color: c.ink),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        helperText: helperText,
        filled: true,
        fillColor: onPaper ? c.panel : c.raised,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: idle,
        enabledBorder: idle,
        disabledBorder: idle,
        focusedBorder: border(c.accent, 1.5),
        errorBorder: border(c.danger, 1.5),
        focusedErrorBorder: border(c.danger, 1.5),
      ),
    );

    final label = this.label;
    if (label == null) {
      return field;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
              ?labelTrailing,
            ],
          ),
        ),
        field,
      ],
    );
  }
}
