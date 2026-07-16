import 'package:flutter/widgets.dart';
import 'package:graceful_shell/scopes.dart';

/// The elevated surface every block on the overview sits on.
///
/// `controlSurface` on `popupBackground` is the one-step elevation the panel
/// already uses for its controls, so the cards read as part of the same surface
/// hierarchy rather than as a new one.
class SystemCard extends StatelessWidget {
  const SystemCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.subtitle,
  });

  final String title;

  /// The headline figure, shown right-aligned against [title].
  final Widget? trailing;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final subtitle = this.subtitle;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: theme.fontFamily,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.45),
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// The headline figure in a [SystemCard]'s header.
class CardValue extends StatelessWidget {
  const CardValue(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontFamily: theme.fontFamily,
        fontWeight: FontWeight.w600,
        color: theme.popupForeground,
      ),
    );
  }
}

/// A label/value line inside a card — the vitals list is a column of these.
class StatLine extends StatelessWidget {
  const StatLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
        ],
      ),
    );
  }
}
