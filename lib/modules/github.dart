// The bar's GitHub strip: the mark, an unread count, and the notification
// inbox behind a click.
//
// Everything that is not rendering — the sign-in, the token, the poll, the two
// writes that mark a thread read — is `lib/github/`, one store for the machine
// and leased, so two bars are one poll rather than two. What is left here is the
// button, the card, and the three states the card has to be able to be: signed
// out, half-way through a sign-in, and showing a list.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_config.dart';
import 'package:moonswing/github/github_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart';
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
  // Not const: the default store is the process-wide singleton, which a const
  // constructor cannot reach.
  GithubNotifications({super.key, GithubStore? store, this.showCount = true})
      : store = store ?? GithubStore.instance;

  /// Injected by tests, which seed a store rather than reaching the network.
  final GithubStore store;

  /// `[modules.github] show_count`.
  final bool showCount;

  @override
  State<GithubNotifications> createState() => _GithubNotificationsState();
}

class _GithubNotificationsState extends State<GithubNotifications>
    with PopupHost<GithubNotifications> {
  @override
  void initState() {
    super.initState();
    widget.store.acquire();
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(GithubNotifications oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store
      ..removeListener(_onChanged)
      ..release();
    widget.store
      ..acquire()
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store
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
        child: GithubPopup(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = widget.store;
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
/// behind it and a sign-in that completes while the user is looking at it.
class GithubPopup extends StatelessWidget {
  const GithubPopup({
    super.key,
    required this.store,
    this.copy = copyTextToClipboard,
  });

  final GithubStore store;

  /// How the user code reaches the clipboard. Injected by tests, which must not
  /// fork `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

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
                _Header(store: store, theme: theme),
                Container(height: 1, color: theme.divider),
                Expanded(child: _Body(store: store, theme: theme, copy: copy)),
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
  const _Header({required this.store, required this.theme});

  final GithubStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final signedIn = store.stage == GithubAuthStage.signedIn;
    final unread = store.unreadCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          FaIcon(
            FontAwesomeIcons.github,
            size: ShellFontSizes.label,
            color: theme.popupForeground,
          ),
          const SizedBox(width: 8),
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
                onTap: store.markAllRead,
                enabled: !store.busy,
              ),
            SettingsIconButton(
              icon: FontAwesomeIcons.rotate,
              onTap: store.refresh,
              enabled: !store.busy,
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.rightFromBracket,
              onTap: store.signOut,
            ),
          ],
        ],
      ),
    );
  }
}

/// Whichever of the card's three states applies.
class _Body extends StatelessWidget {
  const _Body({required this.store, required this.theme, required this.copy});

  final GithubStore store;
  final ThemeConfig theme;
  final Future<ClipboardResult> Function(String text) copy;

  @override
  Widget build(BuildContext context) {
    switch (store.stage) {
      case GithubAuthStage.signedOut:
        return _ShortBody(child: _SignedOut(store: store, theme: theme));
      case GithubAuthStage.requestingCode:
      case GithubAuthStage.awaitingAuthorization:
        return _ShortBody(
          child: _DeviceCode(store: store, theme: theme, copy: copy),
        );
      case GithubAuthStage.signedIn:
        return _Inbox(store: store, theme: theme);
    }
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

/// The sign-in invitation, and where a failed sign-in reports back to.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.store, required this.theme});

  final GithubStore store;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sign in to GitHub',
            style: TextStyle(
              fontSize: ShellFontSizes.title,
              fontWeight: FontWeight.w600,
              color: theme.popupForeground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // Said before the button rather than after it: the user is about to
            // be sent to a browser, and what will happen there is the one thing
            // worth knowing first.
            'A code appears here and a browser opens at github.com, where you '
            'type it in. Your password never reaches the shell.',
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              height: 1.45,
              color: theme.popupForeground.withValues(alpha: 0.65),
            ),
          ),
          if (store.error.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ErrorLine(message: store.error),
          ],
          const SizedBox(height: 14),
          SettingsActionButton(
            label: 'Sign in with GitHub',
            primary: true,
            loading: store.busy,
            onTap: store.signIn,
          ),
        ],
      ),
    );
  }
}

/// The user's half of the device flow: the code, and the two ways to get it to
/// GitHub.
class _DeviceCode extends StatelessWidget {
  const _DeviceCode({
    required this.store,
    required this.theme,
    required this.copy,
  });

  final GithubStore store;
  final ThemeConfig theme;
  final Future<ClipboardResult> Function(String text) copy;

  @override
  Widget build(BuildContext context) {
    final code = store.deviceCode;
    if (code == null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(child: LoadingIndicator(color: theme.popupForeground)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter this code at ${_shortUri(code.verificationUri)}',
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              color: theme.popupForeground.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
          _UserCode(code: code.userCode, theme: theme, copy: copy),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SettingsActionButton(
                  label: 'Open GitHub',
                  primary: true,
                  onTap: () => store.openVerificationPage(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SettingsActionButton(
                  label: 'Cancel',
                  onTap: store.cancelSignIn,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Waiting for you to authorise the shell…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              color: theme.popupForeground.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// `github.com/login/device` — the URL without its scheme, which is what a
  /// person reads out to themselves while typing it.
  static String _shortUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.hasAuthority) return uri;
    return '${parsed.host}${parsed.path}';
  }
}

/// The code itself: eight characters, spaced, and click-to-copy.
///
/// Through `wl-copy` rather than Flutter's own `Clipboard`, for the reason
/// `emoji/emoji_clipboard.dart` documents: a Wayland client cannot take the
/// selection without a seat and a serial, and every surface the shell owns is a
/// layer-shell one. `Clipboard.setData` from here is a silent no-op.
class _UserCode extends StatefulWidget {
  const _UserCode({
    required this.code,
    required this.theme,
    required this.copy,
  });

  final String code;
  final ThemeConfig theme;
  final Future<ClipboardResult> Function(String text) copy;

  @override
  State<_UserCode> createState() => _UserCodeState();
}

class _UserCodeState extends State<_UserCode> {
  ClipboardResult? _result;

  Future<void> _copy() async {
    final result = await widget.copy(widget.code);
    if (mounted) setState(() => _result = result);
  }

  /// The line under the code, which is where a failed copy is reported: the
  /// card is still on screen, so it says so itself rather than through a
  /// notification the user would have to leave the sign-in to read. A missing
  /// helper names the *package*, never a package manager.
  String get _hint => switch (_result) {
        null => 'Click to copy',
        ClipboardResult.copied => 'Copied',
        ClipboardResult.unavailable =>
          'Install $kClipboardPackage to copy it, or type it in',
        ClipboardResult.failed => '$kClipboardCommand could not copy it',
      };

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return RepaintBoundary(
      child: HoverRegion(
        onTap: _copy,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Column(
            children: [
              Text(
                widget.code,
                style: TextStyle(
                  fontSize: ShellFontSizes.heading,
                  fontWeight: FontWeight.w700,
                  // The one place in the shell that sets a family the theme did
                  // not choose: this is a string to be transcribed character by
                  // character, and a proportional face makes O and 0 the same
                  // picture.
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                  color: theme.popupForeground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _hint,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: _result == ClipboardResult.copied ||
                          _result == null
                      ? theme.popupForeground.withValues(alpha: 0.5)
                      : kErrorColor,
                ),
              ),
            ],
          ),
        ),
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
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
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
