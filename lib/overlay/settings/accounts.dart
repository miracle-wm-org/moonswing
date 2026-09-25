// Settings › Accounts: the Google account the whole shell signs in with once.
//
// The account is not config. The client and the grant live in the XDG state
// directory (`google/google_account_file.dart`) and go through
// `GoogleAccountStore`. What the shell *does* with the account is ordinary
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

/// What the "how do I get a client" tip says. Kept in one place: it is the one
/// step a user cannot skip, and the wiki page repeats it at length.
const String _kClientHelp =
    'Google needs an OAuth client to show its consent screen. In Google Cloud '
    'Console: create a project, enable the Google Calendar API, set up the '
    'OAuth consent screen (External, and add yourself as a test user), then '
    'create credentials › OAuth client ID › Desktop app, and paste its ID and '
    'secret here. The secret is stored beside the sign-in, in '
    '~/.local/state/moonswing, never in config.toml.';

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

  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _account.load();
    _account.addListener(_onAccount);
    _wasSignedIn = _account.signedIn;
    if (_wasSignedIn) _calendar.loadCalendars();
  }

  /// The calendar list is read when the page opens signed in, and again the
  /// moment a sign-in on this page lands.
  void _onAccount() {
    final signedIn = _account.signedIn;
    if (signedIn && !_wasSignedIn) _calendar.loadCalendars();
    _wasSignedIn = signedIn;
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

/// The client, the sign-in, and whatever went wrong with either.
class _GoogleAccountSection extends StatelessWidget {
  const _GoogleAccountSection({required this.account});

  final GoogleAccountStore account;

  @override
  Widget build(BuildContext context) {
    final stage = account.stage;
    final error = account.error;
    return SettingsSection(
      label: 'Google',
      info:
          'One sign-in for the whole shell. The Calendar tab shows its '
          'events, and the todo board can hold its meetings. The shell asks '
          'for read-only access to your calendars and nothing else.',
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
        _status(context, stage),
        const SizedBox(height: 8),
        SettingsRow.field(
          SettingsCatalog.googleClientId,
          info: _kClientHelp,
          control: SettingsCommitField(
            initial: account.clientId,
            width: 280,
            hint: '….apps.googleusercontent.com',
            onCommitted: (text) => account.setClient(id: text),
          ),
        ),
        SettingsRow.field(
          SettingsCatalog.googleClientSecret,
          control: SettingsCommitField(
            // Never shown back once saved; an empty commit keeps the saved one.
            initial: '',
            width: 280,
            hint: account.hasClientSecret ? 'Saved — paste to replace' : '',
            onCommitted: (text) {
              if (text.trim().isNotEmpty) account.setClient(secret: text);
            },
          ),
        ),
      ],
    );
  }

  Widget _status(BuildContext context, GoogleAuthStage stage) {
    switch (stage) {
      case GoogleAuthStage.needsClient:
        return const SettingsHint(
          'Paste an OAuth client ID and secret below to connect a Google '
          'account.',
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
        return SettingsRow(
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
      case GoogleAuthStage.signedIn:
        final email = account.email;
        return SettingsRow(
          label: email.isEmpty ? 'Signed in' : 'Signed in as $email',
          control: SettingsActionButton(
            label: 'Sign out',
            compact: true,
            onTap: account.signOut,
          ),
        );
    }
  }
}

/// Which of the account's calendars are read.
class _GoogleCalendarsSection extends StatelessWidget {
  const _GoogleCalendarsSection({required this.calendar, required this.config});

  final GoogleCalendarStore calendar;
  final ConfigStore config;

  List<String> _selected() => GoogleConfig.fromMap(
    config.get<Map<String, dynamic>>(['google']),
  ).calendars;

  /// `primary` is Google's alias for the account's main calendar and is what
  /// the default config says, so a primary calendar counts as selected under
  /// either spelling.
  static bool _isSelected(GoogleCalendar c, List<String> selected) =>
      selected.contains(c.id) || (c.primary && selected.contains('primary'));

  void _toggle(GoogleCalendar c, bool on) {
    final selected = _selected();
    final next = [
      for (final id in selected)
        if (id != c.id && !(c.primary && id == 'primary')) id,
      if (on) c.primary ? 'primary' : c.id,
    ];
    config.set(['google', 'calendars'], next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: calendar,
      builder: (context, _) {
        final calendars = calendar.calendars;
        return SettingsSection(
          label: SettingsCatalog.googleCalendars.label,
          info: SettingsCatalog.googleCalendars.description,
          trailing: SettingsRescanButton(
            label: 'Reload',
            onTap: calendar.loadCalendars,
          ),
          children: [
            if (calendar.calendarsError.isNotEmpty)
              SettingsBanner(
                title: 'Could not read your calendars',
                message: calendar.calendarsError,
                action: SettingsActionButton(
                  label: 'Retry',
                  compact: true,
                  onTap: calendar.loadCalendars,
                ),
              )
            else if (calendars.isEmpty)
              const SettingsHint('Reading your calendars…'),
            for (final c in calendars)
              SettingsRow(
                label: c.primary ? '${c.summary} (primary)' : c.summary,
                // Per row and on a bool, not on the section: ConfigStore
                // notifies on every keystroke anywhere in settings.
                control: StoreSelector<bool>(
                  listenable: config,
                  selector: () => _isSelected(c, _selected()),
                  builder: (context, on) => SettingsToggle(
                    value: on,
                    onChanged: (v) => _toggle(c, v),
                  ),
                ),
              ),
          ],
        );
      },
    );
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
