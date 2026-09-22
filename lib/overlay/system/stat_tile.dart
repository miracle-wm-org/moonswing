import 'package:flutter/widgets.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// A named block of content: its heading, and the elevated surface the content
/// sits on.
///
/// **The heading is outside the surface, not inside it.** It used to be an 11px
/// half-transparent uppercase line in the card's own padding, which read as a
/// caption belonging to the first row rather than as the name of the block. Set
/// above the surface at [ShellFontSizes.heading] and full contrast, the page is
/// scannable by its headings and the card holds only data.
///
/// `controlSurface` on `popupBackground` is the one-step elevation the panel
/// already uses for its controls.
class SystemCard extends StatelessWidget {
  const SystemCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.subtitle,
    this.stretch = false,
  });

  final String title;

  /// The headline figure, shown right-aligned against [title].
  final Widget? trailing;
  final String? subtitle;
  final List<Widget> children;

  /// Let the surface fill the height it is given, rather than sizing to its
  /// content.
  ///
  /// Required by the side-by-side pairs on the overview, which sit in an
  /// [IntrinsicHeight] row so both surfaces end level: with the heading outside
  /// the surface, a content-sized card there would draw its background only as
  /// far as its own rows reach. Only ever pass this where the height is bounded —
  /// under an unbounded one a flexible column child is an error.
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final subtitle = this.subtitle;

    final surface = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                // The headline figure sits on the heading's own baseline, and the
                // subtitle goes under both. Aligning the figure against the
                // heading *block* would drop it to the subtitle's line on the two
                // cards that have one.
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: ShellFontSizes.heading,
                        fontFamily: theme.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: theme.popupForeground,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (stretch) Expanded(child: surface) else surface,
      ],
    );
  }
}

/// The headline figure beside a [SystemCard]'s heading.
class CardValue extends StatelessWidget {
  const CardValue(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: ShellFontSizes.title,
        fontFamily: theme.fontFamily,
        fontWeight: FontWeight.w600,
        color: theme.popupForeground,
      ),
    );
  }
}

/// A label/value line inside a card — the vitals list is a column of these.
class StatLine extends StatelessWidget {
  const StatLine({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth,
  });

  final String label;
  final String value;

  /// Width of the label column, which puts the value directly beside it.
  ///
  /// Null keeps the spread layout — label left, value hard right — which is what
  /// the narrow overview cards want, because at that width the two are adjacent
  /// anyway and a right-aligned column of figures is easier to compare down. On a
  /// full-width page it is the wrong shape: System Info is up to 1600 logical
  /// pixels across, so a spread pair puts a hand's breadth of empty card between
  /// a label and its value. Setting this also lets a long value wrap to the right
  /// instead of overflowing the row.
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final labelWidth = this.labelWidth;

    final labelText = Text(
      label,
      style: TextStyle(
        fontSize: ShellFontSizes.label,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground.withValues(alpha: 0.6),
      ),
    );
    final valueStyle = TextStyle(
      fontSize: ShellFontSizes.label,
      fontFamily: theme.fontFamily,
      fontWeight: FontWeight.w500,
      color: theme.popupForeground,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: labelWidth == null
            ? [
                Expanded(child: labelText),
                const SizedBox(width: 8),
                Text(value, style: valueStyle),
              ]
            : [
                SizedBox(width: labelWidth, child: labelText),
                const SizedBox(width: 12),
                Expanded(child: Text(value, style: valueStyle)),
              ],
      ),
    );
  }
}
