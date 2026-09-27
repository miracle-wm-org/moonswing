// Shell › Calendar: the month grid, and every linked Google account's calendars
// beside it.
//
// The sign-in itself is Settings › Accounts, which is the one place a sign-in
// runs; what the shell *does* with an account is ordinary `[google]` config, and
// it lives here with the rest of the calendar so it is all in one place — one
// section per linked account, each listing that account's calendars.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/google/google_account_store.dart';
import 'package:moonswing/google/google_api.dart';
import 'package:moonswing/google/google_calendar_store.dart';
import 'package:moonswing/google/google_config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';

/// The Calendar category: the month grid's own settings, then Google's.
class CalendarSection extends StatelessWidget {
  const CalendarSection({
    super.key,
    required this.store,
    GoogleAccountStore? account,
    GoogleCalendarStore? calendar,
  }) : _account = account,
       _calendar = calendar;

  final ConfigStore store;

  /// Injected by widget tests, so nothing here touches the network. Null reads
  /// the [AccountsScope].
  final GoogleAccountStore? _account;
  final GoogleCalendarStore? _calendar;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Calendar',
          children: [
            SettingsRow.field(
              SettingsCatalog.calendarWeekStart,
              // Subscribed per key rather than under a page-level
              // `ListenableBuilder`: [ConfigStore] notifies on every keystroke
              // anywhere in the settings UI. See [ConfigValue].
              control: ConfigValue<String>(
                store: store,
                path: const ['calendar', 'week_start'],
                fallback: 'sunday',
                builder: (context, value) => SettingsSegmented(
                  options: const ['sunday', 'monday'],
                  value: value!,
                  onChanged: (v) => store.set(['calendar', 'week_start'], v),
                ),
              ),
            ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        GoogleCalendarSettings(
          config: store,
          account: _account,
          calendar: _calendar,
        ),
      ],
    );
  }
}

/// Every linked Google account's calendars, one section each, and what the
/// shell uses them for. A sliver.
///
/// Signed out, it says where the sign-in is and links there.
class GoogleCalendarSettings extends StatefulWidget {
  const GoogleCalendarSettings({
    super.key,
    required this.config,
    GoogleAccountStore? account,
    GoogleCalendarStore? calendar,
  }) : _account = account,
       _calendar = calendar;

  final ConfigStore config;
  final GoogleAccountStore? _account;
  final GoogleCalendarStore? _calendar;

  @override
  State<GoogleCalendarSettings> createState() => _GoogleCalendarSettingsState();
}

class _GoogleCalendarSettingsState extends State<GoogleCalendarSettings> {
  late final GoogleAccountStore _account =
      widget._account ?? AccountsScope.googleOf(context);
  late final GoogleCalendarStore _calendar =
      widget._calendar ?? AccountsScope.googleCalendarOf(context);

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
  /// moment an account is linked or unlinked while it is open.
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
    return ListenableBuilder(
      listenable: _account,
      builder: (context, _) {
        if (!_account.signedIn) return const _GoogleSignedOutSection();
        return SliverMainAxisGroup(
          slivers: [
            _GoogleCalendarsSections(
              account: _account,
              calendar: _calendar,
              config: widget.config,
            ),
            _GoogleUseSection(config: widget.config),
          ],
        );
      },
    );
  }
}

/// No account linked: what would be here, and the way to the sign-in.
class _GoogleSignedOutSection extends StatelessWidget {
  const _GoogleSignedOutSection();

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'Google Calendar',
      info: SettingsCatalog.googleCalendars.description,
      children: [
        const SettingsHint(
          'Link a Google account to show its events here and put its '
          'meetings on the todo board.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SettingsActionButton(
            label: 'Link an account in Accounts',
            icon: FontAwesomeIcons.userPlus,
            compact: true,
            onTap: () => openSettingsAt(context, SettingsCatalog.googleAccount),
          ),
        ),
      ],
    );
  }
}

/// Which calendars are read, one section per linked account.
class _GoogleCalendarsSections extends StatelessWidget {
  const _GoogleCalendarsSections({
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
      builder: (context, _) => SliverMainAxisGroup(
        slivers: [
          for (final a in account.accounts) ...[
            SliverSettingsSection(
              label: a.email.isEmpty ? 'Google calendars' : a.email,
              info: SettingsCatalog.googleCalendars.description,
              trailing: SettingsRescanButton(
                label: 'Reload',
                onTap: calendar.loadCalendars,
              ),
              children: _accountRows(a),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ],
      ),
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

/// What the accounts' calendars are used for.
class _GoogleUseSection extends StatelessWidget {
  const _GoogleUseSection({required this.config});

  final ConfigStore config;

  @override
  Widget build(BuildContext context) {
    return SliverSettingsSection(
      label: 'Use Google calendars for',
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
