// Settings › Accounts › CalDAV: the one place the shell signs in to CalDAV
// servers — Radicale, Baïkal, Nextcloud, Fastmail, iCloud — as many as the user
// has, whose calendars the Calendar tab can show and whose task lists the todo
// board can sync with.
//
// Unlike Google and GitHub there is no OAuth app and no browser: CalDAV is a
// password (ideally an app password) sent to a server the user names. So the
// card is a form, and Connect is the server being asked for the user's
// calendars — an account is only kept once that answers, and Cancel abandons
// a server that is slow to (a mistyped address may never). With an account
// already listed the form is behind **Add account**, the way Google's second
// sign-in is. `CalDavAccountStore` holds them; which calendars the Calendar tab
// shows is chosen under Shell › Calendar, and which list the board syncs with
// on the board itself, since linking one merges the two.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/overlay/settings/accounts/account_card.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/overlay/settings/settings_highlight.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The CalDAV card.
class CalDavAccountCard extends StatefulWidget {
  const CalDavAccountCard({super.key, required this.account});

  final CalDavAccountStore account;

  @override
  State<CalDavAccountCard> createState() => _CalDavAccountCardState();
}

class _CalDavAccountCardState extends State<CalDavAccountCard> {
  /// Whether the form is open for another account beside those listed.
  bool _adding = false;

  CalDavAccountStore get account => widget.account;

  void _closeForm() {
    account
      ..cancelSignIn()
      ..clearError();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final accounts = account.accounts;
        final error = account.error;
        final untrusted = account.untrustedCertificate;
        final formOpen = accounts.isEmpty || _adding;
        return AccountProviderCard(
          brand: AccountBrand.caldav,
          tagline: 'Calendars and task lists on your own server',
          state: accounts.isNotEmpty
              ? AccountLinkState.linked
              : account.signingIn
              ? AccountLinkState.pending
              : AccountLinkState.none,
          info:
              'Any CalDAV server: Radicale, Baïkal, Nextcloud, ownCloud, '
              'Fastmail, iCloud and others, as many as you like. Give the '
              'address of the server (or of one calendar), your user name, and '
              'a password — an app password, where the server offers them. '
              'They are kept in ~/.local/state/moonswing, readable only by you. '
              'Which calendars the Calendar tab shows is chosen under Shell › '
              'Calendar; which task list the todo board syncs with is chosen on '
              'the board, under Backups…',
          // An add button goes at the top right of the collection it adds to.
          trailing: accounts.isNotEmpty && !_adding
              ? SettingsAddButton(
                  label: 'Add account',
                  onTap: () => setState(() => _adding = true),
                )
              : null,
          usedBy: const [
            (FontAwesomeIcons.calendarDays, 'Calendar tab'),
            (FontAwesomeIcons.tableColumns, 'Todo board'),
          ],
          children: [
            for (final a in accounts) ...[
              _AccountRow(store: account, account: a),
              const SizedBox(height: 8),
            ],
            if (formOpen) ...[
              if (accounts.isNotEmpty) const SizedBox(height: 4),
              if (error.isNotEmpty) ...[
                SettingsBanner(
                  title: untrusted == null
                      ? 'CalDAV account'
                      : 'Untrusted certificate',
                  message: untrusted == null
                      ? error
                      : '$error\n\n${_describe(untrusted)}',
                  // The form trusts it as it connects, since it holds the
                  // address and password to connect with.
                  action: SettingsActionButton(
                    label: 'Dismiss',
                    compact: true,
                    onTap: account.clearError,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _SignInForm(
                // A fresh form per account added, so the fields start empty.
                key: ValueKey(accounts.length),
                account: account,
                onCancel: accounts.isEmpty ? null : _closeForm,
                onSignedIn: () => setState(() => _adding = false),
              ),
            ],
            if (accounts.isNotEmpty && !formOpen) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(
                    child: AccountBlurb(
                      'Which calendars the Calendar tab shows is set with the '
                      'rest of the calendar. Open the todo board and choose '
                      'Backups… to link it to a task list.',
                    ),
                  ),
                  const SizedBox(width: 16),
                  SettingsActionButton(
                    label: 'Calendar settings',
                    icon: FontAwesomeIcons.calendarDays,
                    compact: true,
                    onTap: () => openSettingsAt(
                      context,
                      SettingsCatalog.caldavCalendars,
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

String _describe(CalDavCertificate c) {
  final expires = c.expires.toLocal().toIso8601String().split('T').first;
  return 'Subject: ${c.subject}\n'
      'Issuer: ${c.issuer}\n'
      'Expires: $expires\n'
      'SHA-256: ${c.fingerprint}\n\n'
      'On the server: openssl x509 -in cert.pem -noout -fingerprint -sha256';
}

/// What an account was found to hold, in a line.
String calDavAccountSummary(CalDavAccount a) {
  String names(String one, String many, List<CalDavCollection> list) =>
      '${list.length == 1 ? one : many}: ${list.map((c) => c.name).join(', ')}';
  // A collection that holds both is listed under each.
  final events = a.eventCalendars;
  final tasks = a.taskLists;
  if (events.isEmpty && tasks.isEmpty) return 'No calendars found';
  return [
    if (events.isNotEmpty) names('Calendar', 'Calendars', events),
    if (tasks.isNotEmpty) names('Task list', 'Task lists', tasks),
  ].join(' · ');
}

/// One signed-in account: who, what it holds, and what went wrong reading it.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.store, required this.account});

  final CalDavAccountStore store;
  final CalDavAccount account;

  @override
  Widget build(BuildContext context) {
    final id = account.id;
    final error = store.errorOf(id);
    final untrusted = store.untrustedCertificateOf(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountIdentityRow(
          name: account.label,
          detail: calDavAccountSummary(account),
          actions: [
            SettingsIconButton(
              icon: FontAwesomeIcons.arrowsRotate,
              tooltip: 'Look for calendars again',
              enabled: !store.refreshing(id),
              onTap: () => store.refresh(id),
            ),
            SettingsActionButton(
              label: 'Sign out',
              compact: true,
              onTap: () => store.signOut(id),
            ),
          ],
        ),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 8),
          SettingsBanner(
            title: untrusted == null
                ? 'Could not read ${account.label}'
                : 'Untrusted certificate',
            message: untrusted == null
                ? error
                : '$error\n\n${_describe(untrusted)}',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (untrusted != null) ...[
                  SettingsActionButton(
                    label: 'Trust',
                    compact: true,
                    onTap: () =>
                        store.trustCertificate(id, untrusted.fingerprint),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  SettingsActionButton(
                    label: 'Retry',
                    compact: true,
                    onTap: () => store.refresh(id),
                  ),
                  const SizedBox(width: 8),
                ],
                SettingsActionButton(
                  label: 'Dismiss',
                  compact: true,
                  onTap: () => store.clearErrorOf(id),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The server address, user name and password, and Connect.
class _SignInForm extends StatefulWidget {
  const _SignInForm({
    super.key,
    required this.account,
    this.onCancel,
    this.onSignedIn,
  });

  final CalDavAccountStore account;

  /// Closes the form, when there is somewhere to go back to: accounts are
  /// already listed. Null for the first account's form, which is the card.
  final VoidCallback? onCancel;

  /// Called when a sign-in from this form was kept.
  final VoidCallback? onSignedIn;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _url.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      calDavServerUri(_url.text) != null && !widget.account.signingIn;

  Future<void> _connect({String? trustedCertificate}) async {
    if (!_ready) return;
    final kept = await widget.account.signIn(
      url: _url.text,
      username: _user.text,
      password: _password.text,
      trustedCertificate: trustedCertificate,
    );
    if (kept && mounted) widget.onSignedIn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final text = _url.text.trim();
    final invalid = text.isNotEmpty && calDavServerUri(text) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccountBlurb(
          'The address of your server, or of one calendar on it. The shell '
          'asks it for your calendars and task lists before keeping anything.',
        ),
        const SizedBox(height: 10),
        const _Label('Server address'),
        SettingsTextField(
          controller: _url,
          hint: 'https://dav.example.com/',
          onChanged: (_) {},
          onSubmitted: (_) => _connect(),
        ),
        if (invalid || calDavIsInsecure(text)) ...[
          const SizedBox(height: 4),
          Text(
            invalid
                ? 'The address has to start with https:// (or http://).'
                : 'An http:// address sends the password unencrypted. Use '
                      'https:// unless the server is on a network you trust.',
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: kErrorColor,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('User name'),
                  SettingsTextField(controller: _user, onChanged: (_) {}),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('Password'),
                  SettingsTextField(
                    controller: _password,
                    obscureText: true,
                    hint: 'An app password, ideally',
                    onChanged: (_) {},
                    onSubmitted: (_) => _connect(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.account.signingIn || widget.onCancel != null) ...[
              SettingsActionButton(
                label: 'Cancel',
                compact: true,
                onTap: widget.account.signingIn
                    ? widget.account.cancelSignIn
                    : widget.onCancel!,
              ),
              const SizedBox(width: 8),
            ],
            if (widget.account.untrustedCertificate case final untrusted?
                when !widget.account.signingIn) ...[
              SettingsActionButton(
                label: 'Trust certificate and connect',
                compact: true,
                enabled: _ready,
                onTap: () =>
                    _connect(trustedCertificate: untrusted.fingerprint),
              ),
              const SizedBox(width: 8),
            ],
            SettingsActionButton(
              label: 'Connect',
              primary: true,
              compact: true,
              enabled: _ready,
              loading: widget.account.signingIn,
              onTap: _connect,
            ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          fontFamily: theme.fontFamily,
          fontWeight: FontWeight.w600,
          color: theme.popupForeground.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
