// A link to a GitHub issue or pull request, drawn as what it links to: its
// state's icon, its title and its number, in place of the address.
//
// It reads [GithubLinkStore], and only the one link it shows, so a title
// arriving rebuilds this chip and nothing around it. A surface decides whether
// to draw one at all from [GithubLinkStore.enabled]; signed out, the address is
// the address.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_link_store.dart';
import 'package:moonswing/github/github_links.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart' show SettingsTooltip;
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// [chip] as a span that sits in a line of text.
///
/// The span scales its child by the text's own [TextScaler] already, so the
/// chip is built with none of its own — or a larger `font_size` would grow it
/// twice.
WidgetSpan githubLinkChipSpan(GithubLinkChip chip) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: MediaQuery.withNoTextScaling(child: chip),
);

/// One link to an issue or pull request, as a chip that opens it.
class GithubLinkChip extends StatelessWidget {
  const GithubLinkChip({
    super.key,
    required this.store,
    required this.ref,
    required this.onOpen,
    this.highlighted = false,
    this.fontSize = ShellFontSizes.secondary,
  });

  final GithubLinkStore store;
  final GithubRef ref;
  final VoidCallback onOpen;

  /// Whether a search matched the address the chip stands in for.
  final bool highlighted;

  final double fontSize;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: store.watch(ref),
    builder: (context, state, _) => _chip(context, state),
  );

  Widget _chip(BuildContext context, GithubLinkState state) {
    final theme = ThemeScope.of(context);
    final dim = theme.popupForeground.withValues(alpha: 0.6);
    final issue = state.issue;
    final failed = issue == null && state.error.isNotEmpty;
    final (icon, color) = failed
        ? (FontAwesomeIcons.triangleExclamation, dim)
        : _look(issue, theme.accentText, dim);
    final title = issue?.title ?? '';
    final label = title.isEmpty
        ? TextSpan(text: ref.shortLabel)
        : TextSpan(
            children: [
              TextSpan(text: title),
              TextSpan(
                text: ' #${ref.number}',
                style: TextStyle(color: dim),
              ),
            ],
          );
    // Its own layer: the hover tint repaints the chip, not the paragraph and
    // card around it.
    return RepaintBoundary(
      child: SettingsTooltip(
        message: _tooltip(state),
        child: HoverRegion(
          onTap: onOpen,
          builder: (context, hovered) => Container(
            constraints: const BoxConstraints(
              minHeight: ShellSizes.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: hovered
                  ? theme.surfaceHover
                  : highlighted
                  ? theme.accent.withValues(alpha: 0.35)
                  : theme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(ShellRadii.control),
              border: Border.all(
                color: highlighted ? theme.accent : const Color(0x00000000),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(icon, size: fontSize - 1, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text.rich(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                      color: theme.popupForeground,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The icon and its colour: the shape says what state it is in, the colour
  /// whether it still wants anything — open in the accent, finished receding,
  /// closed without being finished in the error colour.
  (FaIconData, Color) _look(GithubIssue? issue, Color live, Color dim) {
    final pull = issue?.isPullRequest ?? ref.isPullRequest;
    return switch (issue?.state) {
      null => (
        pull ? FontAwesomeIcons.codePullRequest : FontAwesomeIcons.circleDot,
        dim,
      ),
      GithubIssueState.open => (
        pull ? FontAwesomeIcons.codePullRequest : FontAwesomeIcons.circleDot,
        live,
      ),
      GithubIssueState.draft => (FontAwesomeIcons.codePullRequest, dim),
      GithubIssueState.merged => (FontAwesomeIcons.codeMerge, dim),
      GithubIssueState.completed => (FontAwesomeIcons.circleCheck, dim),
      GithubIssueState.closed => (
        pull ? FontAwesomeIcons.codePullRequest : FontAwesomeIcons.ban,
        kErrorColor,
      ),
    };
  }

  String _tooltip(GithubLinkState state) {
    final issue = state.issue;
    final where = ref.fullLabel;
    if (issue == null) {
      if (state.error.isNotEmpty) return '$where — ${state.error}';
      return where;
    }
    final kind = issue.isPullRequest ? 'Pull request' : 'Issue';
    final status = switch (issue.state) {
      GithubIssueState.open => 'open',
      GithubIssueState.draft => 'draft',
      GithubIssueState.merged => 'merged',
      GithubIssueState.completed => 'closed as completed',
      GithubIssueState.closed =>
        issue.isPullRequest
            ? 'closed without merging'
            : 'closed, not completed',
    };
    final stale = state.error.isEmpty
        ? ''
        : '\nCould not refresh: ${state.error}';
    return '$where · $kind, $status$stale';
  }
}
