// The overview's Code tab: one place for everything waiting on the user across
// GitHub and GitLab — the reviews somebody asked them for, their own open
// changes and what each one needs, the issues assigned to them, their inbox,
// and what they shipped lately — with anything left too long called stale.
//
// The tab draws; it reads nothing itself. `CodeStore` reads both forges (under
// a lease this tab holds only while it is the tab showing), `GithubStore` is
// the GitHub inbox the bar module already polls, and the board's grouping,
// ordering and staleness are the pure `buildCodeBoard` in `code_model.dart`.
//
// The layout is a summary strip over two columns: the work (reviews, changes,
// issues) on the left, the inbox and the shipped list on the right, or all of
// it in one column when the panel is narrow. A summary tile is also a filter —
// the Stale tile narrows every list to what has gone quiet — and an account
// chip, with both forges linked, narrows the tab to one of them. Every list is
// a fixed-extent sliver: rows are two lines whatever they hold, so a long
// review queue scrolls without laying out what is off screen.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/code/code_github.dart';
import 'package:moonswing/code/code_model.dart';
import 'package:moonswing/code/code_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/icon_pack.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// Below this width the tab is one column: two would leave the work list too
/// narrow to hold a title beside its status.
const double kCodeTwoColumnWidth = 960;

/// The inbox and shipped column's share of a wide tab.
const double kCodeSideColumnWidth = 360;

/// The Code tab.
///
/// **It must be told when it is visible**, as the System tab is: the
/// overview's `IndexedStack` keeps a visited tab alive, and [active] is what
/// holds the leases — so neither forge is read while the user is on another
/// tab.
class CodeDashboard extends StatefulWidget {
  const CodeDashboard({
    super.key,
    required this.active,
    this.onOpenAccounts,
    this.store,
    this.inbox,
  });

  final bool active;

  /// Where "Connect an account" goes — the overview's Accounts page, in place.
  /// Null jumps there through the settings search's seam instead.
  final VoidCallback? onOpenAccounts;

  /// Injected by tests. Null reads the [AccountsScope].
  final CodeStore? store;
  final GithubStore? inbox;

  @override
  State<CodeDashboard> createState() => _CodeDashboardState();
}

class _CodeDashboardState extends State<CodeDashboard> {
  late final CodeStore _store = widget.store ?? AccountsScope.codeOf(context);
  late final GithubStore _inbox =
      widget.inbox ?? AccountsScope.githubNotificationsOf(context);

  /// Built once: a `ListenableBuilder` is an `AnimatedWidget`, and a merge
  /// made in `build` would re-subscribe on every rebuild.
  late final Listenable _both = Listenable.merge([_store, _inbox]);

  bool _holding = false;
  CodeFocus _focus = CodeFocus.all;

  /// The one forge the tab is narrowed to, or null for both.
  CodeProvider? _only;

  @override
  void initState() {
    super.initState();
    _hold(widget.active);
  }

  @override
  void didUpdateWidget(CodeDashboard old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _hold(widget.active);
  }

  @override
  void dispose() {
    _hold(false);
    super.dispose();
  }

  void _hold(bool want) {
    if (want == _holding) return;
    _holding = want;
    if (want) {
      _store.acquire();
      _inbox.acquire();
    } else {
      _store.release();
      _inbox.release();
    }
  }

  void _openAccounts(CodeProvider? provider) {
    final open = widget.onOpenAccounts;
    if (open != null) {
      open();
      return;
    }
    openSettingsAt(
      context,
      provider == CodeProvider.gitlab
          ? SettingsCatalog.gitlabAccount
          : SettingsCatalog.githubAccount,
    );
  }

  void _setFocus(CodeFocus focus) =>
      setState(() => _focus = _focus == focus ? CodeFocus.all : focus);

  void _toggleOnly(CodeProvider provider) =>
      setState(() => _only = _only == provider ? null : provider);

  void _refresh() {
    _store.refresh();
    if (_store.linked(CodeProvider.github)) _inbox.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _both,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    if (!_store.accountsLoaded) {
      return const Center(child: LoadingIndicator(size: 20));
    }
    final linked = _store.linkedProviders;
    if (linked.isEmpty) {
      return _ConnectPrompt(onConnect: () => _openAccounts(null));
    }

    // A narrowing to a forge that is no longer linked, or that is the only one
    // left, narrows nothing.
    final only = _only;
    final providers = only != null && linked.length > 1 && linked.contains(only)
        ? {only}
        : null;
    final now = _store.now();
    final board = buildCodeBoard(
      _store.snapshots,
      thresholds: _store.config.thresholds,
      now: now,
      providers: providers,
    );

    final githubById = <String, GithubNotification>{};
    final notices = <CodeNotice>[
      if (_store.linked(CodeProvider.github))
        for (final n in _inbox.items) codeNoticeFromGithub(n),
      ...?_store.snapshotOf(CodeProvider.gitlab)?.inbox,
    ];
    for (final n in _inbox.items) {
      githubById[n.id] = n;
    }
    final inbox = mergeCodeInbox(notices, providers: providers);

    final view = _BoardView(
      board: board,
      focus: _focus,
      inbox: inbox,
      now: now,
      thresholds: _store.config.thresholds,
      shippedDays: _store.config.shippedDays,
      showProvider: linked.length > 1 && providers == null,
      githubPublicOnly:
          _store.linked(CodeProvider.github) &&
          !_store.github.scopes.split(RegExp(r'[\s,]+')).contains('repo'),
      inboxLoading:
          _store.linked(CodeProvider.github) &&
          _inbox.loading &&
          _inbox.items.isEmpty,
      onOpen: _store.open,
      onOpenNotice: (notice) {
        final github = githubById[notice.id];
        if (notice.provider == CodeProvider.github && github != null) {
          _inbox.open(github);
        } else {
          _store.open(notice.url);
        }
      },
      onDismissNotice: (notice) {
        final github = githubById[notice.id];
        if (notice.provider == CodeProvider.github && github != null) {
          _inbox.markRead(github);
        } else {
          _store.markTodoDone(notice);
        }
      },
      onDismissAll: () {
        if (providers == null || providers.contains(CodeProvider.github)) {
          _inbox.markAllRead();
        }
        if (providers == null || providers.contains(CodeProvider.gitlab)) {
          _store.markAllTodosDone();
        }
      },
    );

    final loadingAll = linked.every(_store.loadingOf);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            store: _store,
            only: providers?.single,
            // The forges' reads only: the notification inbox is polled every
            // minute on GitHub's cadence, and a spinner flicking on for each
            // of those would read as the tab never settling.
            busy: _store.busy,
            onToggle: linked.length > 1 ? _toggleOnly : null,
            onConnect: _openAccounts,
            onRefresh: _refresh,
          ),
          const SizedBox(height: 12),
          ..._banners(linked),
          _SummaryRow(board: board, focus: _focus, onFocus: _setFocus),
          const SizedBox(height: 18),
          Expanded(
            child: loadingAll
                ? const Center(child: LoadingIndicator(size: 20))
                : view,
          ),
        ],
      ),
    );
  }

  /// What went wrong, above everything it affects. Each read failure keeps the
  /// last good lists on screen and offers the retry; nothing here recovers on
  /// its own sooner than the next poll.
  List<Widget> _banners(List<CodeProvider> linked) {
    final banners = <Widget>[
      for (final p in linked)
        if (_store.errorOf(p) case final error when error.isNotEmpty)
          SettingsBanner(
            title: 'Could not read ${p.label}',
            message: _store.snapshotOf(p) == null
                ? error
                : '$error. Showing what was read before.',
            action: SettingsActionButton(
              label: 'Retry',
              compact: true,
              onTap: _store.refresh,
            ),
          ),
      if (_store.linked(CodeProvider.github) && _inbox.error.isNotEmpty)
        SettingsBanner(
          title: 'GitHub notifications',
          message: _inbox.error,
          action: SettingsActionButton(
            label: 'Retry',
            compact: true,
            onTap: _inbox.refresh,
          ),
        ),
      if (_store.actionError.isNotEmpty)
        SettingsBanner(
          title: 'That did not work',
          message: _store.actionError,
          action: SettingsActionButton(
            label: 'Dismiss',
            compact: true,
            onTap: _store.clearActionError,
          ),
        ),
    ];
    return [
      for (final banner in banners) ...[banner, const SizedBox(height: 10)],
    ];
  }
}

// ---------------------------------------------------------------------------
// Signed out
// ---------------------------------------------------------------------------

/// What the tab is before any forge is linked: what it would show, and the way
/// to Settings › Accounts.
class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final dim = theme.popupForeground.withValues(alpha: 0.7);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(AccountBrand.github, size: 48),
                  SizedBox(width: 14),
                  BrandMark(AccountBrand.gitlab, size: 48),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Everything waiting on you, in one place',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ShellFontSizes.heading,
                  fontWeight: FontWeight.w600,
                  color: theme.popupForeground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Link GitHub or GitLab — or both — and this tab gathers your '
                'review requests, your open pull and merge requests, the '
                'issues assigned to you and your inbox, and says which have '
                'gone quiet for too long.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  height: 1.5,
                  color: dim,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: theme.controlSurface,
                  borderRadius: BorderRadius.circular(ShellRadii.card),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Feature(
                      ShellGlyph.eye,
                      'Reviews waiting on you, longest-waiting first',
                    ),
                    _Feature(
                      ShellGlyph.pullRequest,
                      'Your changes, with their checks, reviews and conflicts',
                    ),
                    _Feature(
                      ShellGlyph.hourglass,
                      'Anything left too long, called stale',
                    ),
                    _Feature(
                      ShellGlyph.inbox,
                      'Notifications and to-dos from every forge in one inbox',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsActionButton(
                    label: 'Connect an account',
                    icon: ShellGlyph.link,
                    primary: true,
                    compact: true,
                    onTap: onConnect,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Opens Settings › Accounts. GitHub signs in through your '
                'browser; GitLab takes a read-only token.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: theme.popupForeground.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);

  final ShellGlyph icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            child: ShellIcon(
              icon,
              size: ShellFontSizes.secondary,
              color: theme.accentText,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: theme.popupForeground.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

/// Whose accounts these are, and the refresh. With both forges linked the
/// account chips are also the forge filter.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.store,
    required this.only,
    required this.busy,
    required this.onToggle,
    required this.onConnect,
    required this.onRefresh,
  });

  final CodeStore store;
  final CodeProvider? only;
  final bool busy;

  /// Null while only one forge is linked, when there is nothing to narrow.
  final ValueChanged<CodeProvider>? onToggle;
  final ValueChanged<CodeProvider> onConnect;
  final VoidCallback onRefresh;

  String _label(CodeProvider p) => switch (p) {
    CodeProvider.github =>
      store.github.login.isEmpty ? 'GitHub' : store.github.login,
    CodeProvider.gitlab => store.gitlab.label,
  };

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final onToggle = this.onToggle;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          for (final p in CodeProvider.values) ...[
            if (store.linked(p))
              _AccountChip(
                provider: p,
                label: _label(p),
                selected: only == p,
                tooltip: onToggle == null
                    ? null
                    : only == p
                    ? 'Show both GitHub and GitLab'
                    : 'Show only ${p.label}',
                onTap: onToggle == null ? null : () => onToggle(p),
              )
            else
              _ConnectChip(provider: p, onTap: () => onConnect(p)),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          SizedBox.square(
            dimension: ShellSizes.iconButton,
            child: busy
                ? Center(
                    child: LoadingIndicator(
                      size: 12,
                      color: theme.popupForeground.withValues(alpha: 0.6),
                    ),
                  )
                : SettingsIconButton(
                    icon: ShellGlyph.refresh,
                    tooltip:
                        'Refresh — read every ${store.config.refreshMinutes} '
                        'min while this tab is open',
                    onTap: onRefresh,
                  ),
          ),
          const SizedBox(width: 2),
          SettingsIconButton(
            icon: ShellGlyph.sliders,
            tooltip: 'When things go stale',
            onTap: () =>
                openSettingsAt(context, SettingsCatalog.codeReviewStaleDays),
          ),
        ],
      ),
    );
  }
}

AccountBrand _brand(CodeProvider p) => switch (p) {
  CodeProvider.github => AccountBrand.github,
  CodeProvider.gitlab => AccountBrand.gitlab,
};

ShellGlyph _brandGlyph(CodeProvider p) => switch (p) {
  CodeProvider.github => ShellGlyph.github,
  CodeProvider.gitlab => ShellGlyph.gitlab,
};

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.provider,
    required this.label,
    required this.selected,
    this.tooltip,
    this.onTap,
  });

  final CodeProvider provider;
  final String label;
  final bool selected;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: SettingsTooltip(
        message: tooltip,
        child: HoverRegion(
          enabled: onTap != null,
          onTap: onTap,
          builder: (context, hovered) => Container(
            height: 30,
            padding: const EdgeInsets.fromLTRB(5, 0, 11, 0),
            decoration: BoxDecoration(
              color: selected
                  ? theme.accent.withValues(alpha: 0.16)
                  : hovered
                  ? theme.surfaceHover
                  : theme.controlSurface,
              borderRadius: BorderRadius.circular(ShellRadii.pill),
              border: Border.all(
                color: selected ? theme.accent : const Color(0x00000000),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(_brand(provider), size: 20),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ShellFontSizes.secondary,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? theme.accentText
                          : theme.popupForeground,
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
}

/// A forge with nothing linked: a quiet, dashed-looking invitation rather than
/// a second call to action — the tab already has data from the other one.
class _ConnectChip extends StatelessWidget {
  const _ConnectChip({required this.provider, required this.onTap});

  final CodeProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) {
          final color = theme.popupForeground.withValues(
            alpha: hovered ? 0.85 : 0.5,
          );
          return Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: hovered ? theme.surfaceHover : const Color(0x00000000),
              borderRadius: BorderRadius.circular(ShellRadii.pill),
              border: Border.all(color: theme.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShellIcon(ShellGlyph.add, size: 10, color: color),
                const SizedBox(width: 6),
                ShellIcon(
                  _brandGlyph(provider),
                  size: ShellFontSizes.secondary,
                  color: color,
                  pack: IconPack.fontAwesome,
                ),
                const SizedBox(width: 6),
                Text(
                  'Connect ${provider.label}',
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// The four numbers the tab is read by, each also the filter for its group.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.board,
    required this.focus,
    required this.onFocus,
  });

  final CodeBoard board;
  final CodeFocus focus;
  final ValueChanged<CodeFocus> onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quiet = theme.popupForeground.withValues(alpha: 0.55);

    (String, Color) waiting(CodeSection s, String none) {
      final stale = s.staleCount;
      if (stale > 0) return ('$stale waiting too long', kWarningColor);
      if (s.total == 0) return (none, quiet);
      return ('All recent', quiet);
    }

    final needs = board.needsActionCount;
    final ready = board.readyCount;
    final authoredStale = board.authored.staleCount;
    final (changesDetail, changesColor) = needs > 0
        ? ('$needs need${needs == 1 ? 's' : ''} you', kErrorColor)
        : authoredStale > 0
        ? ('$authoredStale gone quiet', kWarningColor)
        : ready > 0
        ? ('$ready ready to merge', theme.accentText)
        : board.authored.total == 0
        ? ('None open', quiet)
        : ('All moving', quiet);
    final (reviewDetail, reviewColor) = waiting(
      board.reviews,
      'Nothing waiting on you',
    );
    final (issueDetail, issueColor) = waiting(board.assigned, 'None assigned');
    final stale = board.staleCount;

    final tiles = [
      _SummaryTile(
        icon: ShellGlyph.eye,
        label: 'Review requests',
        value: board.reviews.total,
        detail: reviewDetail,
        detailColor: reviewColor,
        selected: focus == CodeFocus.reviews,
        onTap: () => onFocus(CodeFocus.reviews),
      ),
      _SummaryTile(
        icon: ShellGlyph.pullRequest,
        label: 'Your changes',
        value: board.authored.total,
        detail: changesDetail,
        detailColor: changesColor,
        selected: focus == CodeFocus.authored,
        onTap: () => onFocus(CodeFocus.authored),
      ),
      _SummaryTile(
        icon: ShellGlyph.circleDot,
        label: 'Assigned issues',
        value: board.assigned.total,
        detail: issueDetail,
        detailColor: issueColor,
        selected: focus == CodeFocus.assigned,
        onTap: () => onFocus(CodeFocus.assigned),
      ),
      _SummaryTile(
        icon: ShellGlyph.hourglass,
        label: 'Stale',
        value: stale,
        valueColor: stale > 0 ? kWarningColor : null,
        detail: stale > 0
            ? 'Show only what has gone quiet'
            : 'Nothing gone quiet',
        detailColor: quiet,
        selected: focus == CodeFocus.stale,
        onTap: () => onFocus(CodeFocus.stale),
      ),
    ];
    return Row(
      children: [
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tile),
        ],
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.detailColor,
    required this.selected,
    required this.onTap,
    this.valueColor,
  });

  final ShellGlyph icon;
  final String label;
  final int value;
  final Color? valueColor;
  final String detail;
  final Color detailColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quiet = theme.popupForeground.withValues(alpha: 0.6);
    return RepaintBoundary(
      child: SettingsTooltip(
        message: selected
            ? 'Show everything'
            : 'Show only ${label.toLowerCase()}',
        child: HoverRegion(
          onTap: onTap,
          builder: (context, hovered) => Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              color: selected
                  ? theme.accent.withValues(alpha: 0.14)
                  : hovered
                  ? theme.surfaceHover
                  : theme.controlSurface,
              borderRadius: BorderRadius.circular(ShellRadii.card),
              border: Border.all(
                color: selected ? theme.accent : const Color(0x00000000),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ShellIcon(
                      icon,
                      size: ShellFontSizes.caption,
                      color: selected ? theme.accentText : quiet,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          color: selected ? theme.accentText : quiet,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: valueColor ?? theme.popupForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    color: detailColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The board
// ---------------------------------------------------------------------------

/// The lists: the work on the left and the inbox and shipped list on the
/// right, or one column of all of it when the tab is narrow.
class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.board,
    required this.focus,
    required this.inbox,
    required this.now,
    required this.thresholds,
    required this.shippedDays,
    required this.showProvider,
    required this.githubPublicOnly,
    required this.inboxLoading,
    required this.onOpen,
    required this.onOpenNotice,
    required this.onDismissNotice,
    required this.onDismissAll,
  });

  final CodeBoard board;
  final CodeFocus focus;
  final List<CodeNotice> inbox;
  final DateTime now;
  final CodeThresholds thresholds;
  final int shippedDays;

  /// Whether rows carry their forge's mark — only while both are shown.
  final bool showProvider;

  /// Whether to say that private GitHub repositories are not being read.
  final bool githubPublicOnly;
  final bool inboxLoading;

  final bool Function(String url) onOpen;
  final ValueChanged<CodeNotice> onOpenNotice;
  final ValueChanged<CodeNotice> onDismissNotice;
  final VoidCallback onDismissAll;

  /// Two lines of text and their air, at the text scale actually drawn — a
  /// fixed extent that ignored `font_size` would clip the second line.
  static double _rowExtent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return (20 +
            scaler.scale(ShellFontSizes.body) * 1.35 +
            scaler.scale(ShellFontSizes.caption) * 1.35)
        .ceilToDouble();
  }

  Duration _threshold(CodeGroup group) => switch (group) {
    CodeGroup.reviews => thresholds.review,
    CodeGroup.authored => thresholds.change,
    CodeGroup.assigned => thresholds.issue,
  };

  List<Widget> _work(BuildContext context, double extent) {
    final slivers = <Widget>[];
    for (final section in board.visible(focus)) {
      slivers.add(
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: section.group.title,
            subtitle: section.group.subtitle,
            count: section.total,
            shown: section.entries.length,
            stale: focus == CodeFocus.stale ? 0 : section.staleCount,
          ),
        ),
      );
      final entries = section.entries;
      if (entries.isEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: _EmptyCard(
              height: extent,
              text: focus == CodeFocus.stale
                  ? 'Nothing here has gone quiet.'
                  : switch (section.group) {
                      CodeGroup.reviews => 'No reviews waiting on you.',
                      CodeGroup.authored => 'You have no open changes.',
                      CodeGroup.assigned => 'No open issues assigned to you.',
                    },
            ),
          ),
        );
      } else {
        final threshold = _threshold(section.group);
        slivers.add(
          _CardSliver(
            extent: extent,
            count: entries.length,
            builder: (context, i, position) => _ItemRow(
              key: ValueKey(entries[i].item.id),
              entry: entries[i],
              group: section.group,
              threshold: threshold,
              now: now,
              position: position,
              showProvider: showProvider,
              onOpen: () => onOpen(entries[i].item.url),
            ),
          ),
        );
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 22)));
    }
    if (githubPublicOnly) {
      slivers.add(const SliverToBoxAdapter(child: _ScopeHint()));
    }
    return slivers;
  }

  List<Widget> _side(BuildContext context, double extent) {
    final theme = ThemeScope.of(context);
    final unread = inbox.where((n) => n.unread).length;
    final merged = board.merged;
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          title: 'Inbox',
          subtitle: 'Notifications and to-dos',
          count: unread,
          shown: unread,
          trailing: unread == 0
              ? null
              : SettingsIconButton(
                  icon: ShellGlyph.checkDouble,
                  tooltip: 'Mark everything read',
                  onTap: onDismissAll,
                ),
        ),
      ),
      if (inboxLoading)
        SliverToBoxAdapter(
          child: _EmptyCard(
            height: extent,
            child: const LoadingIndicator(size: 14),
          ),
        )
      else if (inbox.isEmpty)
        SliverToBoxAdapter(
          child: _EmptyCard(height: extent, text: 'Inbox zero.'),
        )
      else
        _CardSliver(
          extent: extent,
          count: inbox.length,
          builder: (context, i, position) => _NoticeRow(
            key: ValueKey('${inbox[i].provider.name}-${inbox[i].id}'),
            notice: inbox[i],
            now: now,
            position: position,
            showProvider: showProvider,
            onOpen: () => onOpenNotice(inbox[i]),
            onDismiss: () => onDismissNotice(inbox[i]),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
      SliverToBoxAdapter(
        child: _SectionHeader(
          title: 'Shipped',
          subtitle:
              'Merged in the last ${shippedDays == 1 ? 'day' : '$shippedDays days'}',
          count: merged.length,
          shown: merged.length,
          countColor: merged.isEmpty ? null : theme.accentText,
        ),
      ),
      if (merged.isEmpty)
        SliverToBoxAdapter(
          child: _EmptyCard(
            height: extent,
            text: 'Nothing merged in that time.',
          ),
        )
      else
        _CardSliver(
          extent: extent,
          count: merged.length,
          builder: (context, i, position) => _ShippedRow(
            key: ValueKey(merged[i].id),
            item: merged[i],
            now: now,
            position: position,
            showProvider: showProvider,
            onOpen: () => onOpen(merged[i].url),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final extent = _rowExtent(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kCodeTwoColumnWidth) {
          return CustomScrollView(
            scrollCacheExtent: ScrollCacheExtent.pixels(extent * 6),
            slivers: [..._work(context, extent), ..._side(context, extent)],
          );
        }
        final side = math.min(
          kCodeSideColumnWidth,
          constraints.maxWidth * 0.38,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                scrollCacheExtent: ScrollCacheExtent.pixels(extent * 6),
                slivers: _work(context, extent),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: side,
              child: CustomScrollView(
                scrollCacheExtent: ScrollCacheExtent.pixels(extent * 6),
                slivers: _side(context, extent),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Where a row sits in its card, for its corners and its rule.
enum _Position { only, first, middle, last }

_Position _positionOf(int i, int count) {
  if (count == 1) return _Position.only;
  if (i == 0) return _Position.first;
  if (i == count - 1) return _Position.last;
  return _Position.middle;
}

/// The corners a row's hover tint is rounded at, so it follows the card.
BorderRadius _cornersOf(_Position p) {
  const r = Radius.circular(ShellRadii.card);
  return switch (p) {
    _Position.only => const BorderRadius.all(r),
    _Position.first => const BorderRadius.vertical(top: r),
    _Position.last => const BorderRadius.vertical(bottom: r),
    _Position.middle => BorderRadius.zero,
  };
}

/// A card of fixed-extent rows: the card is a [DecoratedSliver], so the list
/// inside it stays lazy however long it is.
class _CardSliver extends StatelessWidget {
  const _CardSliver({
    required this.extent,
    required this.count,
    required this.builder,
  });

  final double extent;
  final int count;
  final Widget Function(BuildContext context, int i, _Position position)
  builder;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.card),
      ),
      sliver: SliverFixedExtentList.builder(
        itemExtent: extent,
        itemCount: count,
        itemBuilder: (context, i) => builder(context, i, _positionOf(i, count)),
      ),
    );
  }
}

/// A group's name, how many are in it, and how many have gone stale.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.shown,
    this.stale = 0,
    this.trailing,
    this.countColor,
  });

  final String title;
  final String subtitle;

  /// How many there are…
  final int count;

  /// …and how many of them are listed; a search returns a page.
  final int shown;
  final int stale;
  final Widget? trailing;
  final Color? countColor;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.title,
                          fontWeight: FontWeight.w600,
                          color: theme.popupForeground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      text: shown < count ? '$shown of $count' : '$count',
                      color: countColor ?? theme.popupForeground,
                      faint: count == 0,
                    ),
                    if (stale > 0) ...[
                      const SizedBox(width: 6),
                      _Pill(
                        text: '$stale stale',
                        color: kWarningColor,
                        icon: ShellGlyph.hourglass,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.caption,
                    color: theme.popupForeground.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing],
        ],
      ),
    );
  }
}

/// A small rounded count or status, tinted in [color].
class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
    this.icon,
    this.faint = false,
  });

  final String text;
  final Color color;
  final ShellGlyph? icon;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final ink = faint ? color.withValues(alpha: 0.45) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: faint ? 0.05 : 0.12),
        borderRadius: BorderRadius.circular(ShellRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ShellIcon(icon, size: 9, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A card with one quiet line in it — an empty group, or a loader.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.height, this.text, this.child});

  final double height;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quiet = theme.popupForeground.withValues(alpha: 0.45);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.card),
      ),
      alignment: Alignment.center,
      child:
          child ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShellIcon(
                ShellGlyph.circleCheck,
                size: ShellFontSizes.secondary,
                color: quiet,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: quiet,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

/// The note under the lists when GitHub is read without `repo`.
class _ScopeHint extends StatelessWidget {
  const _ScopeHint();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quiet = theme.popupForeground.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ShellIcon(ShellGlyph.info, size: 10, color: quiet),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'GitHub is read without the repo scope, so private '
              'repositories are left out. Add repo to scopes on the GitHub '
              'module’s page, then sign in again.',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                height: 1.4,
                color: quiet,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

/// The frame every row shares: its rule, its hover tint following the card's
/// corners, its own layer, and the click.
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.position,
    required this.onTap,
    required this.builder,
    this.marker,
  });

  final _Position position;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  /// A short bar down the row's leading edge — a stale row's amber, so the
  /// list is scannable by what has gone quiet as well as the age column.
  final Color? marker;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final marker = this.marker;
    final ruled = position == _Position.middle || position == _Position.last;
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          decoration: BoxDecoration(
            color: hovered
                ? theme.surfaceHover.atMostAlpha(0.18)
                : const Color(0x00000000),
            borderRadius: _cornersOf(position),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: ruled ? theme.divider : const Color(0x00000000),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 12, 1),
                      child: builder(context, hovered),
                    ),
                  ),
                ],
              ),
              if (marker != null)
                Positioned(
                  left: 4,
                  top: 12,
                  bottom: 12,
                  width: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: marker,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row's second line: the forge's mark when both are shown, then the
/// details, dim and on one line.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.provider,
    required this.showProvider,
    required this.parts,
  });

  final CodeProvider provider;
  final bool showProvider;
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final quiet = theme.popupForeground.withValues(alpha: 0.55);
    return Row(
      children: [
        if (showProvider) ...[
          ShellIcon(
            _brandGlyph(provider),
            size: 10,
            color: quiet,
            pack: IconPack.fontAwesome,
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            parts.where((p) => p.isNotEmpty).join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: ShellFontSizes.caption, color: quiet),
          ),
        ),
      ],
    );
  }
}

TextStyle _titleStyle(ThemeConfig theme, {bool strong = false}) => TextStyle(
  fontSize: ShellFontSizes.body,
  fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
  color: theme.popupForeground,
);

/// One pull request, merge request or issue.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.entry,
    required this.group,
    required this.threshold,
    required this.now,
    required this.position,
    required this.showProvider,
    required this.onOpen,
  });

  final CodeEntry entry;
  final CodeGroup group;
  final Duration threshold;
  final DateTime now;
  final _Position position;
  final bool showProvider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final item = entry.item;
    final pull = item.kind == CodeItemKind.pullRequest;
    final dim = theme.popupForeground.withValues(alpha: 0.45);
    final chips = codeChipsFor(item).take(2).toList();
    // The author is worth a word on somebody else's change; on the user's own
    // it is always them.
    final byline = group == CodeGroup.authored || item.author.isEmpty
        ? ''
        : 'by ${item.author}';
    final comments = item.comments == 0
        ? ''
        : '${item.comments} comment${item.comments == 1 ? '' : 's'}';
    return _RowFrame(
      position: position,
      onTap: onOpen,
      marker: entry.staleness.isStale
          ? kWarningColor.withValues(alpha: 0.8)
          : null,
      builder: (context, hovered) => Row(
        children: [
          SizedBox(
            width: 18,
            child: ShellIcon(
              pull ? ShellGlyph.pullRequest : ShellGlyph.circleDot,
              size: ShellFontSizes.label,
              color: item.draft ? dim : theme.accentText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.isEmpty ? item.reference : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(theme),
                ),
                const SizedBox(height: 3),
                _MetaLine(
                  provider: item.provider,
                  showProvider: showProvider,
                  parts: [
                    '${item.repository}${item.reference}',
                    byline,
                    comments,
                  ],
                ),
              ],
            ),
          ),
          for (final chip in chips) ...[
            const SizedBox(width: 6),
            _StatusChip(chip),
          ],
          const SizedBox(width: 10),
          _AgeBadge(
            time: item.updatedAt,
            staleness: entry.staleness,
            threshold: threshold,
            now: now,
            waiting: group == CodeGroup.reviews,
          ),
        ],
      ),
    );
  }
}

/// What a status chip says: its glyph, its words, and how loudly.
@immutable
class CodeChip {
  const CodeChip(this.icon, this.label, this.tone);

  final ShellGlyph icon;
  final String label;
  final CodeChipTone tone;

  @override
  bool operator ==(Object other) =>
      other is CodeChip &&
      other.icon == icon &&
      other.label == label &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(icon, label, tone);
}

/// A chip's colour, by what it asks of the user: [action] is theirs to fix,
/// [good] is good news, [quiet] is a fact.
enum CodeChipTone { action, good, quiet }

/// The statuses a change's row shows, the ones that need its author first —
/// a row has room for two, and those are the two that matter.
List<CodeChip> codeChipsFor(CodeItem item) {
  if (item.kind != CodeItemKind.pullRequest) return const [];
  return [
    if (item.conflicts)
      const CodeChip(ShellGlyph.ban, 'Conflicts', CodeChipTone.action),
    if (item.review == CodeReview.changesRequested)
      const CodeChip(
        ShellGlyph.comments,
        'Changes requested',
        CodeChipTone.action,
      ),
    if (item.checks == CodeChecks.failing)
      const CodeChip(ShellGlyph.warning, 'Checks failing', CodeChipTone.action),
    if (item.readyToMerge)
      const CodeChip(
        ShellGlyph.circleCheck,
        'Ready to merge',
        CodeChipTone.good,
      )
    else if (item.review == CodeReview.approved)
      const CodeChip(ShellGlyph.check, 'Approved', CodeChipTone.good),
    if (item.draft)
      const CodeChip(ShellGlyph.edit, 'Draft', CodeChipTone.quiet),
    if (item.checks == CodeChecks.pending)
      const CodeChip(ShellGlyph.clock, 'Checks running', CodeChipTone.quiet),
  ];
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.chip);

  final CodeChip chip;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = switch (chip.tone) {
      CodeChipTone.action => kErrorColor,
      CodeChipTone.good => theme.accentText,
      CodeChipTone.quiet => theme.popupForeground.withValues(alpha: 0.55),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ShellRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShellIcon(chip.icon, size: 9, color: color),
          const SizedBox(width: 4),
          Text(
            chip.label,
            style: TextStyle(fontSize: ShellFontSizes.caption, color: color),
          ),
        ],
      ),
    );
  }
}

/// How long since anything happened, and whether that is too long: dim while
/// fresh, amber once half the threshold is gone, and an hourglass pill once it
/// is stale.
class _AgeBadge extends StatelessWidget {
  const _AgeBadge({
    required this.time,
    required this.staleness,
    required this.threshold,
    required this.now,
    this.waiting = false,
  });

  final DateTime? time;
  final CodeStaleness staleness;
  final Duration threshold;
  final DateTime now;

  /// A review request: the wait is somebody else's, and the tooltip says so.
  final bool waiting;

  String get _tooltip {
    final words = codeAgeWords(time, now: now);
    if (words.isEmpty) return 'No activity recorded';
    final days = threshold.inDays;
    final limit = '${days == 1 ? 'a day' : '$days days'} is the limit';
    return switch (staleness) {
      CodeStaleness.stale =>
        waiting
            ? 'Stale: waiting with no activity for $words — $limit'
            : 'Stale: no activity for $words — $limit',
      CodeStaleness.aging => 'Going quiet: no activity for $words — $limit',
      CodeStaleness.fresh => 'Last activity $words ago',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final age = codeAge(time, now: now);
    final Widget badge = switch (staleness) {
      CodeStaleness.stale => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: kWarningColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(ShellRadii.pill),
          border: Border.all(color: kWarningColor.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ShellIcon(
              ShellGlyph.hourglass,
              size: 9,
              color: kWarningColor,
            ),
            const SizedBox(width: 4),
            Text(
              age,
              style: const TextStyle(
                fontSize: ShellFontSizes.caption,
                fontWeight: FontWeight.w600,
                color: kWarningColor,
              ),
            ),
          ],
        ),
      ),
      CodeStaleness.aging => Text(
        age,
        style: const TextStyle(
          fontSize: ShellFontSizes.caption,
          color: kWarningColor,
        ),
      ),
      CodeStaleness.fresh => Text(
        age,
        style: TextStyle(
          fontSize: ShellFontSizes.caption,
          color: theme.popupForeground.withValues(alpha: 0.45),
        ),
      ),
    };
    return SizedBox(
      width: 54,
      child: Align(
        alignment: Alignment.centerRight,
        child: SettingsTooltip(message: _tooltip, child: badge),
      ),
    );
  }
}

/// One inbox thread.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    super.key,
    required this.notice,
    required this.now,
    required this.position,
    required this.showProvider,
    required this.onOpen,
    required this.onDismiss,
  });

  final CodeNotice notice;
  final DateTime now;
  final _Position position;
  final bool showProvider;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  static ShellGlyph _glyph(CodeNoticeSubject s) => switch (s) {
    CodeNoticeSubject.pullRequest => ShellGlyph.pullRequest,
    CodeNoticeSubject.issue => ShellGlyph.circleDot,
    CodeNoticeSubject.commit => ShellGlyph.commit,
    CodeNoticeSubject.release => ShellGlyph.tag,
    CodeNoticeSubject.discussion => ShellGlyph.comments,
    CodeNoticeSubject.pipeline => ShellGlyph.circlePlay,
    CodeNoticeSubject.other => ShellGlyph.bell,
  };

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final unread = notice.unread;
    return _RowFrame(
      position: position,
      onTap: onOpen,
      builder: (context, hovered) => Row(
        children: [
          // Unread is a dot as well as a weight, so a read row's title can
          // stay fully legible.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unread ? theme.accent : const Color(0x00000000),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            child: ShellIcon(
              _glyph(notice.subject),
              size: ShellFontSizes.secondary,
              color: unread
                  ? theme.accentText
                  : theme.popupForeground.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title.isEmpty ? notice.repository : notice.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(theme, strong: unread),
                ),
                const SizedBox(height: 3),
                _MetaLine(
                  provider: notice.provider,
                  showProvider: showProvider,
                  parts: [notice.reason, notice.repository],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // The age and the dismiss share a slot: the age is what the row
          // says at rest, the action replaces it under the pointer.
          SizedBox(
            width: ShellSizes.iconButton + 4,
            child: hovered && unread
                ? SettingsIconButton(
                    icon: ShellGlyph.check,
                    tooltip: notice.provider == CodeProvider.gitlab
                        ? 'Mark done'
                        : 'Mark read',
                    onTap: onDismiss,
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      codeAge(notice.updatedAt, now: now),
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        color: theme.popupForeground.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One change merged in the shipped window.
class _ShippedRow extends StatelessWidget {
  const _ShippedRow({
    super.key,
    required this.item,
    required this.now,
    required this.position,
    required this.showProvider,
    required this.onOpen,
  });

  final CodeItem item;
  final DateTime now;
  final _Position position;
  final bool showProvider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final merged = codeAge(item.mergedAt ?? item.updatedAt, now: now);
    return _RowFrame(
      position: position,
      onTap: onOpen,
      builder: (context, hovered) => Row(
        children: [
          SizedBox(
            width: 18,
            child: ShellIcon(
              ShellGlyph.merge,
              size: ShellFontSizes.label,
              color: theme.accentText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.isEmpty ? item.reference : item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(theme),
                ),
                const SizedBox(height: 3),
                _MetaLine(
                  provider: item.provider,
                  showProvider: showProvider,
                  parts: ['${item.repository}${item.reference}'],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            merged.isEmpty ? '' : merged,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              color: theme.popupForeground.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
