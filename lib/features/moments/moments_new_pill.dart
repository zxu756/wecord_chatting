import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "N new posts": floats at the top of the feed when friends post while it
/// is open. Tapping it scrolls up and shows them. Glass, because it floats
/// over the posts.
class NewMomentsPill extends StatelessWidget {
  const NewMomentsPill({
    required this.count,
    required this.onPressed,
    super.key,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final label = count == 1
        ? tr('1 new post')
        : tr('{count} new posts', {'count': count});
    return Semantics(
      button: true,
      liveRegion: true,
      onTap: onPressed,
      label: label,
      child: ExcludeSemantics(
        child: WeCordPressable(
          key: const ValueKey('moments-new-pill'),
          onPressed: onPressed,
          shape: const StadiumBorder(),
          builder: (context, states) => WeCordGlass(
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: c.accentText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: c.accentText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
