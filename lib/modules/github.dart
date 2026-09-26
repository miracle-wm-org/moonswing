// The bar's GitHub strip: the mark, an unread count, and the notification
// inbox behind a click.
//
// Everything that is not rendering — the poll and the two writes that mark a
// thread read — is `lib/github/`, one store for the machine and leased, so two
// bars are one poll rather than two. The sign-in is not here at all: it is
// Settings › Accounts', the one GitHub linkage every module shares, and a card
// with no account behind it sends the user there. What is left here is the
// button, and the card.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_config.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

export 'package:moonswing/github/github_config.dart' show GithubConfig;

/// The width of the popup. Fixed, like the app directory's: the rows hold two
/// lines of text that must wrap somewhere the card does not choose per item.
const double kGithubPopupWidth = 380;

/// The height of the popup. Fixed too, for a reason of its own.
///
/// A popup's surface is measured **once**, from the post-frame callback in
/// [PopupHost.openPopup], and GTK3 resolves `gdk_window_move_to_rect` at map
/// time and never revisits it — so a card sized to its content has to be the
/// size it will *stay*. This card's content is the one in the shell that does
/// not settle: the poll adds threads while the card is up, `markAllRead` empties
/// it, and a sign-in completing swaps a form for a list. Sized to content that
/// is a window that chases the inbox, anchored for a height it no longer has.
///
/// So the card is this tall whatever is in it: the list scrolls inside it, and
/// everything shorter is centred in what it does not fill.
const double kGithubPopupHeight = 460;

/// The bar module.
class GithubNotifications extends StatefulWidget {
  const GithubNotifications({super.key, this.store, this.showCount = true});

  /// Injected by tests, which seed a store rather than reaching the network.
  /// Null reads the [AccountsScope], which is the shell's one inbox.
  final GithubStore? store;

  /// `[modules.github] show_count`.
  final bool showCount;

  @override
  State<GithubNotifications> createState() => _GithubNotificationsState();
}

class _GithubNotificationsState extends State<GithubNotifications>
    with PopupHost<GithubNotifications> {
  late GithubStore _store = _resolve();

  GithubStore _resolve() =>
      widget.store ?? AccountsScope.githubNotificationsOf(context);

  @override
  void initState() {
    super.initState();
    _store
      ..acquire()
      ..addListener(_onChanged);
  }

  @override
  void didUpdateWidget(GithubNotifications oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _resolve();
    if (next == _store) return;
    _store
      ..removeListener(_onChanged)
      ..release();
    _store = next
      ..acquire()
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    _store
      ..removeListener(_onChanged)
      ..release();
    closePopup();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      // Both axes pinned, so the window the compositor places is the window the
      // card keeps: see [kGithubPopupHeight].
      preferredConstraints: const BoxConstraints(
        minWidth: kGithubPopupWidth,
        maxWidth: kGithubPopupWidth,
        minHeight: kGithubPopupHeight,
        maxHeight: kGithubPopupHeight,
      ),
      child: ThemeProvider(
        child: GithubPopup(store: _store, onClose: closePopup),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = _store;
    final signedIn = store.stage == GithubAuthStage.signedIn;
    final count = store.unreadCount;

    return BarButton(
      active: isPopupOpen,
      onTapDown: (_) => _togglePopup(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.github,
            size: ShellFontSizes.title,
            // Dimmed until there is an account behind it: a signed-out module
            // has nothing to say, and a full-strength mark claims otherwise.
            // The error case is *not* dimmed — a module that cannot reach
            // GitHub has a count on screen that may be stale, and the popup is
            // where the reason is.
            color: signedIn ? theme.foreground : theme.muted,
          ),
          if (widget.showCount && count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                color: theme.foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The card behind the mark.
///
/// Takes the store rather than a snapshot of it: a popup built from values read
/// at open time is frozen for as long as it is up, and this one has a poll
/// behind it and a sign-in in Settings that completes while it is open.
class GithubPopup extends StatelessWidget {
  const GithubPopup({
    super.key,
    required this.store,
    this.onClose,
    this.openAccounts,
  });

  final GithubStore store;

  /// Closes the popup — after a button that sends the user to Settings, whose
  /// overlay the card would otherwise sit on top of.
  final VoidCallback? onClose;

  /// Opens Settings › Accounts. Injected by tests; the default asks the root
  /// through [SettingsController].
  final VoidCallback? openAccounts;

  void _openAccounts() {
    final open = openAccounts;
    if (open != null) {
      open();
    } else {
      SettingsController.instance.open(SettingsRoute.accounts);
    }
    onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = ThemeScope.of(context);
        // [ShellTextRoot] because popup content lays out under its own
        // FlutterView: nothing above it supplies a Directionality, and every
        // Text and Row in this card needs one.
        return ShellTextRoot(
          style: TextStyle(
            color: theme.popupForeground,
            fontSize: ShellFontSizes.secondary,
          ),
          child: PopupCard(
            // [Expanded], not [Flexible]: the card's height is fixed, so the
            // body is given what the header leaves rather than asked how tall it
            // would like to be.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  store: store,
                  theme: theme,
                  onAccounts: _openAccounts,
                ),
                Container(height: 1, color: theme.divider),
                Expanded(
                  child: _Body(
                    store: store,
                    theme: theme,
                    onAccounts: _openAccounts,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The card's top strip: who is signed in, and the actions that act on the
/// whole list.
class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.theme,
    required this.onAccounts,
  });

  final GithubStore store;
  final ThemeConfig theme;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    final signedIn = store.stage == GithubAuthStage.signedIn;
    final unread = store.unreadCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          const BrandMark(AccountBrand.github, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // The login when `/user` has answered, the count when it has not
              // and there is one, and the plain name otherwise — never a
              // placeholder that shifts to a name a moment later.
              store.login.isNotEmpty ? store.login : 'GitHub',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
          ),
          if (signedIn) ...[
            if (unread > 0)
              SettingsIconButton(
                icon: FontAwesomeIcons.checkDouble,
                tooltip: 'Mark all read',
                onTap: store.markAllRead,
                enabled: !store.busy,
              ),
            SettingsIconButton(
              icon: FontAwesomeIcons.rotate,
              tooltip: 'Refresh',
              onTap: store.refresh,
              enabled: !store.busy,
            ),
            // The account is Settings' to manage — signing out here would sign
            // every other GitHub consumer out with it, from a place that does
            // not say so.
            SettingsIconButton(
              icon: FontAwesomeIcons.userGear,
              tooltip: 'Account settings',
              onTap: onAccounts,
            ),
          ],
        ],
      ),
    );
  }
}

/// Whichever of the card's states applies.
class _Body extends StatelessWidget {
  const _Body({
    required this.store,
    required this.theme,
    required this.onAccounts,
  });

  final GithubStore store;
  final ThemeConfig theme;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    if (store.stage == GithubAuthStage.signedIn) {
      return _Inbox(store: store, theme: theme);
    }
    return _ShortBody(
      child: _SignedOut(store: store, theme: theme, onAccounts: onAccounts),
    );
  }
}

/// Content that is shorter than the card it is in, now that the card's height no
/// longer follows it: centred in what it does not fill, and scrolled rather than
/// overflowed if it turns out to be taller after all.
///
/// The scroller is not decoration. Every one of these states is text at the
/// user's own `font_size` — a sign-in paragraph that wraps to three lines at 13
/// and to six at 20 — and [kGithubPopupHeight] is one number for all of them.
class _ShortBody extends StatelessWidget {
  const _ShortBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // [LayoutBuilder] for the one thing a [SingleChildScrollView] cannot tell
    // its child: how much room there is to be centred in. The minimum is what
    // fills the card; anything taller scrolls, and is then top-aligned because
    // the [Center] has no slack left to give. An unbounded height — which the
    // card no longer hands out, but a harness could — is no room to centre in
    // rather than an infinite minimum, which is an assertion.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.hasBoundedHeight ? constraints.maxHeight : 0.0,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// No account yet: where to link one, and why the last one went away.
///
/// The sign-in itself is not here. It is Settings › Accounts', where every
/// module reading GitHub shares it; this card says so and takes the user there.
class _SignedOut extends StatelessWidget {
  const _SignedOut({
    required this.store,
    required this.theme,
    required this.onAccounts,
  });

  final GithubStore store;
  final ThemeConfig theme;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    final pending = store.stage != GithubAuthStage.signedOut;
    final error = store.account.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandMark(AccountBrand.github, size: 48)),
          const SizedBox(height: 14),
          Text(
            pending ? 'Finishing the sign-in' : 'Connect GitHub',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ShellFontSizes.title,
              fontWeight: FontWeight.w600,
              color: theme.popupForeground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pending
                ? 'Type the code shown in Settings › Accounts in at '
                      'github.com, and your notifications appear here.'
                : 'Sign in once under Settings › Accounts, and your '
                      'notifications appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              height: 1.45,
              color: theme.popupForeground.withValues(alpha: 0.65),
            ),
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ErrorLine(message: error, center: true),
          ],
          const SizedBox(height: 16),
          SettingsActionButton(
            label: pending ? 'Show the code' : 'Open Accounts settings',
            icon: FontAwesomeIcons.userGear,
            primary: true,
            onTap: onAccounts,
          ),
        ],
      ),
    );
  }
}

/// The list, and the three things that can be there instead of one.
class _Inbox extends StatelessWidget {
  const _Inbox({required this.store, required this.theme});

  final GithubStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final items = store.items;

    if (store.loading && items.isEmpty) {
      return Center(child: LoadingIndicator(color: theme.popupForeground));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Above the list rather than in place of it: a failed refresh keeps the
        // last list on screen, and this says which one is being looked at.
        if (store.error.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, items.isEmpty ? 0 : 4),
            child: Row(
              children: [
                Expanded(child: _ErrorLine(message: store.error)),
                const SizedBox(width: 8),
                SettingsActionButton(
                  label: 'Retry',
                  compact: true,
                  onTap: store.refresh,
                  enabled: !store.busy,
                ),
              ],
            ),
          ),
        if (items.isEmpty)
          Expanded(child: _Empty(theme: theme))
        else
          Expanded(
            // No `shrinkWrap`: the list is a viewport the size of the space the
            // card has left, not a column as tall as its items. That is the
            // whole of "fixed size, scrolled when it overflows" — one thread or
            // fifty, the surface is [kGithubPopupHeight].
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  Container(height: 1, color: theme.divider),
              itemBuilder: (context, i) => _NotificationRow(
                item: items[i],
                theme: theme,
                onOpen: () => store.open(items[i]),
                onMarkRead: () => store.markRead(items[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return _ShortBody(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              FontAwesomeIcons.inbox,
              size: 32,
              color: theme.popupForeground.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 12),
            Text(
              'No unread notifications',
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                color: theme.popupForeground.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One thread.
///
/// Its own [RepaintBoundary], like every other hover-tinted row in the shell:
/// the card has no boundary of its own, so without one a pointer crossing the
/// list re-records the whole popup picture per row.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.theme,
    required this.onOpen,
    required this.onMarkRead,
  });

  final GithubNotification item;
  final ThemeConfig theme;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (item.repository.isNotEmpty) item.repository,
      if (githubReasonLabel(item.reason).isNotEmpty)
        githubReasonLabel(item.reason),
    ].join(' · ');

    return RepaintBoundary(
      child: HoverRegion(
        onTap: onOpen,
        builder: (context, hovered) => Container(
          color: hovered ? theme.surfaceHover.atMostAlpha(0.16) : null,
          padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FaIcon(
                  _iconFor(item.type),
                  size: ShellFontSizes.secondary,
                  color: item.unread
                      ? theme.accentText
                      : theme.popupForeground.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? item.repository : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ShellFontSizes.body,
                        height: 1.3,
                        // Weight, not colour, carries unread: a read row must
                        // still be readable, and dimming both lines of it makes
                        // the list look half-broken.
                        fontWeight:
                            item.unread ? FontWeight.w600 : FontWeight.w400,
                        color: theme.popupForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        color: theme.popupForeground.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The age and the mark-read button share a slot: the timestamp is
              // what the row says at rest, and the action replaces it under the
              // pointer rather than sitting there on every row of a long list.
              SizedBox(
                width: ShellSizes.iconButton,
                child: hovered && item.unread
                    ? SettingsIconButton(
                        icon: FontAwesomeIcons.check,
                        box: ShellSizes.iconButton,
                        onTap: onMarkRead,
                      )
                    : Center(
                        child: Text(
                          githubAge(item.updatedAt),
                          style: TextStyle(
                            fontSize: ShellFontSizes.caption,
                            color:
                                theme.popupForeground.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static FaIconData _iconFor(GithubSubjectType type) => switch (type) {
        GithubSubjectType.pullRequest => FontAwesomeIcons.codePullRequest,
        GithubSubjectType.issue => FontAwesomeIcons.circleDot,
        GithubSubjectType.commit => FontAwesomeIcons.codeCommit,
        GithubSubjectType.release => FontAwesomeIcons.tag,
        GithubSubjectType.discussion => FontAwesomeIcons.comments,
        GithubSubjectType.checkSuite => FontAwesomeIcons.circlePlay,
        GithubSubjectType.other => FontAwesomeIcons.bell,
      };
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, this.center = false});

  final String message;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: center ? TextAlign.center : null,
      style: const TextStyle(
        fontSize: ShellFontSizes.caption,
        color: kErrorColor,
      ),
    );
  }
}

/// How long ago [time] was, in the two characters a list column has room for:
/// `4m`, `3h`, `6d`, `2w`. Empty for no timestamp at all.
///
/// Pure and takes [now], so `test/github_api_test.dart` can pin it without
/// waiting for a clock. Elapsed time is *derived* here rather than counted: the
/// row is rebuilt when the list changes, and nothing in this module ticks.
String githubAge(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final elapsed = (now ?? DateTime.now()).difference(time);
  // A clock that stepped backwards, or a thread updated a moment in the future
  // by a machine whose clock is ahead: both are "just now", never a negative.
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  return '${elapsed.inDays ~/ 7}w';
}

final Module githubModule = Module.simple<GithubConfig>(
  configKey: 'github',
  fromMap: (map) {
    final config = GithubConfig.fromMap(map);
    // A side effect in `fromMap`, the shape `screenshot.dart` has and for its
    // reason: the store is where the poll reads its settings, and
    // `Module.simple`'s signature guard is what stops this re-running on every
    // keystroke in the settings UI.
    GithubStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => GithubNotifications(showCount: config.showCount),
);
