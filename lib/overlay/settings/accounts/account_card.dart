// The chrome every service on Settings › Accounts is drawn in: one card per
// service, its mark in the service's own colours, whether it is linked, the
// accounts it holds, and what in the shell reads it.
//
// One card for each service rather than one form per service because the page
// is a list of *linkages*, and a user scanning it is asking two questions —
// "is it connected?" and "as whom?" — that should be answered in the same place
// on every card.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// Where a service's linkage stands, as its card's badge says it.
enum AccountLinkState {
  /// Nothing linked. The card's body offers the sign-in.
  none,

  /// A sign-in is under way in the browser.
  pending,

  /// At least one account.
  linked,
}

/// One service's card.
class AccountProviderCard extends StatelessWidget {
  const AccountProviderCard({
    super.key,
    required this.brand,
    required this.tagline,
    required this.state,
    required this.children,
    this.info,
    this.trailing,
    this.usedBy = const [],
  });

  final AccountBrand brand;

  /// What linking the service gives the shell, in a line.
  final String tagline;

  final AccountLinkState state;

  /// The body: the accounts, the sign-in, whatever went wrong.
  final List<Widget> children;

  /// The long explanation, behind a [SettingsInfoTip] beside the name.
  final String? info;

  /// The card's action — an add button goes at the top right of the collection
  /// it adds to.
  final Widget? trailing;

  /// What in the shell reads this service, for the card's footer: the reason
  /// to link it at all, said where the user decides.
  final List<(FaIconData, String)> usedBy;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final info = this.info;
    final trailing = this.trailing;
    return Container(
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(
          // A linked card is ringed in the accent, so the page reads as a
          // checklist at a glance.
          color: state == AccountLinkState.linked
              ? theme.accent.withValues(alpha: 0.55)
              : theme.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                BrandMark(brand, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              brand.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: ShellFontSizes.label,
                                fontFamily: theme.fontFamily,
                                fontWeight: FontWeight.w600,
                                color: theme.popupForeground,
                              ),
                            ),
                          ),
                          if (info != null) ...[
                            const SizedBox(width: 6),
                            SettingsInfoTip(info),
                          ],
                          const SizedBox(width: 8),
                          _LinkBadge(state: state),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tagline,
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing],
              ],
            ),
          ),
          Container(height: 1, color: theme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          if (usedBy.isNotEmpty) _UsedBy(usedBy: usedBy),
        ],
      ),
    );
  }
}

/// Linked, signing in, or nothing — nothing at all, rather than a grey "Not
/// connected" pill: the sign-in button in the body already says that louder.
class _LinkBadge extends StatelessWidget {
  const _LinkBadge({required this.state});

  final AccountLinkState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    AccountLinkState.none => const SizedBox.shrink(),
    AccountLinkState.pending => const SettingsBadge('Signing in…'),
    AccountLinkState.linked => const SettingsBadge('Connected'),
  };
}

/// The footer naming what reads the service.
class _UsedBy extends StatelessWidget {
  const _UsedBy({required this.usedBy});

  final List<(FaIconData, String)> usedBy;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quiet = theme.popupForeground.withValues(alpha: 0.55);
    final style = TextStyle(
      fontSize: ShellFontSizes.caption,
      fontFamily: theme.fontFamily,
      color: quiet,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
      decoration: BoxDecoration(
        color: theme.popupForeground.withValues(alpha: 0.03),
        border: Border(top: BorderSide(color: theme.divider)),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(ShellRadii.card),
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Used by', style: style),
          for (final (icon, label) in usedBy)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(icon, size: ShellFontSizes.caption, color: quiet),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: style.copyWith(
                    color: theme.popupForeground.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One linked account inside a card: who, a line under it, and its actions.
class AccountIdentityRow extends StatelessWidget {
  const AccountIdentityRow({
    super.key,
    required this.name,
    required this.actions,
    this.detail,
  });

  /// The address or login the account is known by.
  final String name;

  final String? detail;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final detail = this.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _Initial(name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 6), action],
        ],
      ),
    );
  }
}

/// The account's initial in an accent disc — an avatar that needs no request.
class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final trimmed = name.replaceFirst('@', '').trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.accent.withValues(alpha: 0.18),
      ),
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          fontFamily: theme.fontFamily,
          fontWeight: FontWeight.w600,
          color: theme.accentText,
        ),
      ),
    );
  }
}

/// The paragraph a signed-out card leads with: what happens when the button is
/// pressed, said before it is.
class AccountBlurb extends StatelessWidget {
  const AccountBlurb(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: ShellFontSizes.secondary,
        fontFamily: theme.fontFamily,
        height: 1.45,
        color: theme.popupForeground.withValues(alpha: 0.7),
      ),
    );
  }
}
