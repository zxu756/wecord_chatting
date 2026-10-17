import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

/// The card people save, share and show: who it is for, the QR code with
/// their picture in the middle, and a line saying what scanning it does.
///
/// Design "C": a warm paper card with a hairline, big friendly type, and the
/// code on a white squircle tile (scanners need dark modules on a light
/// background in either theme). The code is drawn with round modules and
/// error correction H, so the picture in the middle (about 6% of the code)
/// never gets in the way.
class QrCard extends StatelessWidget {
  const QrCard({
    required this.data,
    required this.title,
    required this.avatarBuilder,
    this.subtitle,
    this.hint,
    this.note,
    this.semanticLabel,
    super.key,
  });

  /// What the code carries: the link.
  final String data;

  /// The name, large (a person's or a group's).
  final String title;

  /// "@username", or "12 members".
  final String? subtitle;

  /// A line under the code: what scanning does.
  final String? hint;

  /// A quieter line at the bottom: how long it works, for instance.
  final String? note;

  /// Draws the avatar at [size]: round for people, a squircle for groups.
  final Widget Function(double size) avatarBuilder;

  final String? semanticLabel;

  /// The card's width; the picture saved from it is this wide times the
  /// pixel ratio.
  static const width = 320.0;

  static const _codeSize = 232.0;
  static const _centerSize = 52.0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    // The code keeps one look in both themes.
    final tileInk = WeCordPalette.light.ink;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: BorderRadius.circular(WeCordRadii.xxl),
          border: Border.all(color: c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  avatarBuilder(52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: c.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: c.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                container: true,
                image: true,
                label: semanticLabel ?? tr('QR code'),
                excludeSemantics: true,
                child: Container(
                  key: const ValueKey('qr-card-code'),
                  padding: const EdgeInsets.all(14),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(WeCordRadii.xl),
                    ),
                    shadows: tokens.shadows.hairline,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      QrImageView(
                        data: data,
                        size: _codeSize,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.circle,
                          color: tileInk,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: tileInk,
                        ),
                        semanticsLabel: '',
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: avatarBuilder(_centerSize),
                      ),
                    ],
                  ),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 14),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ],
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'WeCord',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: c.subtle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
