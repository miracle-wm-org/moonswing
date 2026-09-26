// Settings › Accounts: the services the whole shell signs in to once — any
// number of Google accounts, and a GitHub account — each on a card in the
// service's own colours, saying whether it is linked, as whom, and what in the
// shell reads it.
//
// An account is not config. Each sign-in runs as the project's own OAuth app,
// so there is nothing to set up before it, and the grant it earns lives in the
// XDG state directory behind `GoogleAccountStore` / `GithubAccountStore`. The
// stores come from `AccountsScope`, the same ones every module and desktop
// widget reads, so a sign-in here is the one they all use. What the shell
// *does* with an account is ordinary config — `[google]` here, and
// `[modules.github]` on the module's own page — and goes through `ConfigStore`
// like every other row.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/overlay/settings/accounts/account_card.dart';
import 'package:moonswing/overlay/settings/accounts/github_account.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

class AccountsSettingsPage extends StatefulWidget {
  const AccountsSettingsPage({
    super.key,
    GoogleAccountStore? account,
    GoogleCalendarStore? calendar,
    GithubAccountStore? github,
    ConfigStore? config,
    this.copy = copyTextToClipboard,
  }) : _account = account,
       _calendar = calendar,
       _github = github,
       _config = config;

  /// Injected by widget tests, so nothing here touches the network. Null reads
  /// the [AccountsScope].
  final GoogleAccountStore? _account;
  final GoogleCalendarStore? _calendar;
  final GithubAccountStore? _github;
  final ConfigStore? _config;

  /// How the GitHub sign-in code reaches the clipboard; tests must not fork
  /// `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  @override
  State<AccountsSettingsPage> createState() => _AccountsSettingsPageState();
}

class _AccountsSettingsPageState extends State<AccountsSettingsPage> {
  late final GoogleAccountStore _account =
      widget._account ?? AccountsScope.googleOf(context);
  late final GoogleCalendarStore _calendar =
      widget._calendar ?? AccountsScope.googleCalendarOf(context);
  late final GithubAccountStore _github =
      widget._github ?? AccountsScope.githubOf(context);
  late final ConfigStore _config = widget._config ?? ConfigStore.instance;

  String _accountIds = '';

  @override
  void initState() {
    super.initState();
    _account.load();
    _github.load();
    _account.addListener(_onAccount);
    _accountIds = _ids();
    if (_account.signedIn) _calendar.loadCalendars();
  }

  String _ids() => _account.accounts.map((a) => a.id).join('\n');

  /// The calendar lists are read when the page opens signed in, and again the
  /// moment an account is added on this page.
  void _onAccount() {
    final ids = _ids();
    if (ids == _accountIds) return;
    _accountIds = ids;
    if (_account.signedIn) _calendar.loadCalendars();
  }

  @override
  void dispose() {
    _account.removeListener(_onAccount);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accounts',
                style: TextStyle(
                  fontSize: ShellFontSizes.title,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Link a service once, and every module and desktop widget '
                'that reads it uses the same sign-in.',
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Google's settings hang off its card, so the card and what
                // it unlocks rebuild together; GitHub's card listens alone.
                ListenableBuilder(
                  listenable: _account,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GoogleAccountCard(account: _account),
                      if (_account.signedIn) ...[
                        const SizedBox(height: 20),
                        _GoogleCalendarsSection(
                          account: _account,
                          calendar: _calendar,
                          config: _config,
                        ),
                        const SizedBox(height: 20),
                        _GoogleUseSection(config: _config),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                GithubAccountCard(account: _github, copy: widget.copy),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The Google card: the accounts, the sign-in that adds one, and whatever went
/// wrong.
class _GoogleAccountCard extends StatelessWidget {
  const _GoogleAccountCard({required this.account});

  final GoogleAccountStore account;

  @override
  Widget build(BuildContext context) {
    final stage = account.stage;
    final error = account.error;
    final accounts = account.accounts;
    return AccountProviderCard(
      brand: AccountBrand.google,
      tagline: 'Calendars, events and meetings',
      state: switch (stage) {
        GoogleAuthStage.signedIn => AccountLinkState.linked,
        // Adding a second account while one is signed in is still linked.
        GoogleAuthStage.awaitingBrowser when accounts.isNotEmpty =>
          AccountLinkState.linked,
        GoogleAuthStage.awaitingBrowser => AccountLinkState.pending,
        GoogleAuthStage.signedOut ||
        GoogleAuthStage.unavailable => AccountLinkState.none,
      },
      info:
          'Sign in once for the whole shell, with as many accounts as you '
          'like. The Calendar tab shows all of their events, and the todo '
          "board can hold their meetings. Signing in opens Moonswing's Google "
          'app in your browser and asks for read-only access to your '
          'calendars, nothing else. The app is not verified by Google yet, so '
          'the consent page warns about it: choose Advanced, then Go to '
          'Moonswing. Your calendar goes straight from Google to this '
          'computer; the sign-ins are kept in ~/.local/state/moonswing, and '
          'Sign out revokes one.',
      // An add button goes at the top right of the collection it adds to.
      trailing: stage == GoogleAuthStage.signedIn
          ? SettingsAddButton(label: 'Add account', onTap: account.signIn)
          : null,
      usedBy: const [
        (FontAwesomeIcons.calendarDays, 'Calendar tab'),
        (FontAwesomeIcons.tableColumns, 'Todo board'),
      ],
      children: [
        if (error.isNotEmpty) ...[
          SettingsBanner(
            title: 'Google account',
            message: error,
            action: SettingsActionButton(
              label: 'Dismiss',
              compact: true,
              onTap: account.clearError,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final a in accounts)
          AccountIdentityRow(
            name: a.email.isEmpty ? 'Signed in' : a.email,
            detail: 'Read-only calendar access',
            actions: [
              SettingsActionButton(
                label: 'Sign out',
                compact: true,
                onTap: () => account.signOut(a.id),
              ),
            ],
          ),
        ?_status(context, stage),
      ],
    );
  }

  Widget? _status(BuildContext context, GoogleAuthStage stage) {
    switch (stage) {
      case GoogleAuthStage.unavailable:
        return const SettingsHint(
          'This build of Moonswing has no Google sign-in configured.',
        );
      case GoogleAuthStage.signedOut:
        return Row(
          children: [
            const Expanded(
              child: AccountBlurb(
                'Your browser opens at Google, where you choose an account '
                'and allow read-only access to its calendars.',
              ),
            ),
            const SizedBox(width: 16),
            BrandSignInButton(AccountBrand.google, onTap: account.signIn),
          ],
        );
      case GoogleAuthStage.awaitingBrowser:
        final waiting = SettingsRow(
          label: account.busy
              ? 'Finishing the sign-in…'
              : 'Waiting for you to finish in the browser…',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsActionButton(
                label: 'Open again',
                compact: true,
                enabled: !account.busy && account.authUrl != null,
                onTap: account.openConsentPage,
              ),
              const SizedBox(width: 8),
              SettingsActionButton(
                label: 'Cancel',
                compact: true,
                onTap: account.cancelSignIn,
              ),
            ],
          ),
        );
        // Said where the user is looking when Google says it, rather than
        // only behind the card's info tip: a warning page nobody expected
        // reads as a reason to stop.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (account.accounts.isNotEmpty) const SizedBox(height: 8),
            waiting,
            const SizedBox(height: 4),
            const SettingsHint(
              'Google will warn that Moonswing has not been verified yet. '
              'Choose Advanced, then Go to Moonswing, to continue.',
            ),
          ],
        );
      case GoogleAuthStage.signedIn:
        return null;
    }
  }
}

/// Which calendars are read, account by account.
class _GoogleCalendarsSection extends StatelessWidget {
  const _GoogleCalendarsSection({
    required this.account,
    required this.calendar,
    required this.config,
  });

  final GoogleAccountStore account;
  final GoogleCalendarStore calendar;
  final ConfigStore config;

  List<String> _selected() => GoogleConfig.fromMap(
    config.get<Map<String, dynamic>>(['google']),
  ).calendars;

  /// Every account's own calendar, by id — its list's primary, or its address
  /// while the list is unread.
  List<String> _primaries() => [
    for (final a in account.accounts)
      calendar
              .calendarsOf(a.id)
              .where((c) => c.primary)
              .map((c) => c.id)
              .firstOrNull ??
          a.email,
  ]..removeWhere((id) => id.isEmpty);

  void _toggle(GoogleCalendar c, bool on) {
    config.set(
      ['google', 'calendars'],
      toggleCalendar(
        _selected(),
        id: c.id,
        primary: c.primary,
        on: on,
        primaries: _primaries(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: calendar,
      builder: (context, _) {
        final accounts = account.accounts;
        final several = accounts.length > 1;
        return SettingsSection(
          label: SettingsCatalog.googleCalendars.label,
          info: SettingsCatalog.googleCalendars.description,
          trailing: SettingsRescanButton(
            label: 'Reload',
            onTap: calendar.loadCalendars,
          ),
          children: [
            for (final a in accounts) ...[
              if (several) SettingsSubLabel(a.label),
              ..._accountRows(a),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _accountRows(GoogleAccount a) {
    final calendars = calendar.calendarsOf(a.id);
    final error = calendar.calendarsErrorOf(a.id);
    return [
      if (error.isNotEmpty)
        SettingsBanner(
          title: 'Could not read the calendars of ${a.label}',
          message: error,
          action: SettingsActionButton(
            label: 'Retry',
            compact: true,
            onTap: calendar.loadCalendars,
          ),
        )
      else if (!calendar.hasCalendarsOf(a.id))
        const SettingsHint('Reading your calendars…'),
      for (final c in calendars)
        SettingsRow(
          label: c.primary ? '${c.summary} (primary)' : c.summary,
          // Per row and on a bool, not on the section: ConfigStore notifies
          // on every keystroke anywhere in settings.
          control: StoreSelector<bool>(
            listenable: config,
            selector: () =>
                isCalendarSelected(_selected(), id: c.id, primary: c.primary),
            builder: (context, on) =>
                SettingsToggle(value: on, onChanged: (v) => _toggle(c, v)),
          ),
        ),
    ];
  }
}

/// What the account is used for.
class _GoogleUseSection extends StatelessWidget {
  const _GoogleUseSection({required this.config});

  final ConfigStore config;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Use it for',
      children: [
        SettingsRow.field(
          SettingsCatalog.googleShowInCalendar,
          info: SettingsCatalog.googleShowInCalendar.description,
          control: ConfigValue<bool>(
            store: config,
            path: const ['google', 'show_in_calendar'],
            fallback: true,
            builder: (context, value) => SettingsToggle(
              value: value!,
              onChanged: (v) => config.set(['google', 'show_in_calendar'], v),
            ),
          ),
        ),
        SettingsRow.field(
          SettingsCatalog.googleTodoSync,
          info: SettingsCatalog.googleTodoSync.description,
          control: ConfigValue<bool>(
            store: config,
            path: const ['google', 'todo_sync'],
            fallback: false,
            builder: (context, value) => SettingsToggle(
              value: value!,
              onChanged: (v) => config.set(['google', 'todo_sync'], v),
            ),
          ),
        ),
        SettingsRow.field(
          SettingsCatalog.googleRefreshMinutes,
          control: ConfigValue<num>(
            store: config,
            path: const ['google', 'refresh_minutes'],
            fallback: 5,
            builder: (context, value) => SettingsNumberField(
              value: value!,
              isInt: true,
              onChanged: (v) => config.set(
                ['google', 'refresh_minutes'],
                v.toInt().clamp(
                  GoogleConfig.minRefreshMinutes,
                  GoogleConfig.maxRefreshMinutes,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
