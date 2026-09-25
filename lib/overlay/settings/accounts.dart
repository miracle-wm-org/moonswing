// Settings › Accounts: the Google accounts the whole shell signs in with once.
// Any number can be added; everything that reads Google reads all of them.
//
// The account is not config. The sign-in runs as the project's own OAuth client
// (`google/google_client.dart`), so there is nothing to set up before it, and
// the grant it earns lives in the XDG state directory
// (`google/google_account_file.dart`), behind `GoogleAccountStore`. What the shell *does* with the account is ordinary
// `[google]` config and goes through `ConfigStore` like every other row.

import 'package:flutter/widgets.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

class AccountsSettingsPage extends StatefulWidget {
  const AccountsSettingsPage({
    super.key,
    GoogleAccountStore? account,
    GoogleCalendarStore? calendar,
    ConfigStore? config,
  }) : _account = account,
       _calendar = calendar,
       _config = config;

  /// Injected by widget tests, so nothing here touches the network.
  final GoogleAccountStore? _account;
  final GoogleCalendarStore? _calendar;
  final ConfigStore? _config;

  @override
  State<AccountsSettingsPage> createState() => _AccountsSettingsPageState();
}

class _AccountsSettingsPageState extends State<AccountsSettingsPage> {
  late final GoogleAccountStore _account =
      widget._account ?? GoogleAccountStore.instance;
  late final GoogleCalendarStore _calendar =
      widget._calendar ?? GoogleCalendarStore.instance;
  late final ConfigStore _config = widget._config ?? ConfigStore.instance;

  String _accountIds = '';

  @override
  void initState() {
    super.initState();
    _account.load();
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
          child: Text(
            'Accounts',
            style: TextStyle(
              fontSize: ShellFontSizes.title,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ListenableBuilder(
              listenable: _account,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GoogleAccountSection(account: _account),
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
          ),
        ),
      ],
    );
  }
}

/// The accounts, the sign-in that adds one, and whatever went wrong.
class _GoogleAccountSection extends StatelessWidget {
  const _GoogleAccountSection({required this.account});

  final GoogleAccountStore account;

  @override
  Widget build(BuildContext context) {
    final stage = account.stage;
    final error = account.error;
    final accounts = account.accounts;
    return SettingsSection(
      label: 'Google',
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
          SettingsRow(
            label: a.email.isEmpty ? 'Signed in' : a.email,
            control: SettingsActionButton(
              label: 'Sign out',
              compact: true,
              onTap: () => account.signOut(a.id),
            ),
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
        return SettingsRow(
          label: 'Not signed in',
          control: SettingsActionButton(
            label: 'Sign in with Google',
            primary: true,
            compact: true,
            onTap: account.signIn,
          ),
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
        // only behind the section's info tip: a warning page nobody expected
        // reads as a reason to stop.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
