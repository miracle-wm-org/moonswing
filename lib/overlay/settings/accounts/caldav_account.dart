// Settings › Accounts › CalDAV: the one place the shell signs in to a CalDAV
// server — Radicale, Baïkal, Nextcloud, Fastmail, iCloud — whose task lists the
// todo board can sync with.
//
// Unlike Google and GitHub there is no OAuth app and no browser: CalDAV is a
// password (ideally an app password) sent to a server the user names. So the
// card is a form, and Connect is the server being asked for the user's task
// lists — an account is only kept once that answers, and Cancel abandons a
// server that is slow to (a mistyped address may never). `CalDavAccountStore`
// holds it; which list the board syncs with is chosen on the board itself,
// since linking one merges the two.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/caldav/caldav_client.dart';
import 'package:moonswing/overlay/settings/accounts/account_card.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The CalDAV card.
class CalDavAccountCard extends StatelessWidget {
  const CalDavAccountCard({super.key, required this.account});

  final CalDavAccountStore account;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final signedIn = account.account;
        final error = account.error;
        final untrusted = account.untrustedCertificate;
        return AccountProviderCard(
          brand: AccountBrand.caldav,
          tagline: 'Task lists on your own calendar server',
          state: signedIn == null
              ? AccountLinkState.none
              : AccountLinkState.linked,
          info:
              'Any CalDAV server: Radicale, Baïkal, Nextcloud, ownCloud, '
              'Fastmail, iCloud and others. Give the address of the server '
              '(or of one task list), your user name, and a password — an app '
              'password, where the server offers them. They are kept in '
              '~/.local/state/moonswing, readable only by you. Which task list '
              'the todo board syncs with is chosen on the board, under '
              'Backups…',
          usedBy: const [(FontAwesomeIcons.tableColumns, 'Todo board')],
          children: [
            if (error.isNotEmpty) ...[
              SettingsBanner(
                title: untrusted == null
                    ? 'CalDAV account'
                    : 'Untrusted certificate',
                message: untrusted == null
                    ? error
                    : '$error\n\n${_describe(untrusted)}',
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Signed out, the form trusts it as it connects, since
                    // it holds the address and password to connect with.
                    if (untrusted != null && signedIn != null) ...[
                      SettingsActionButton(
                        label: 'Trust',
                        compact: true,
                        onTap: () =>
                            account.trustCertificate(untrusted.fingerprint),
                      ),
                      const SizedBox(width: 8),
                    ],
                    SettingsActionButton(
                      label: 'Dismiss',
                      compact: true,
                      onTap: account.clearError,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (signedIn == null)
              _SignInForm(account: account)
            else
              _SignedIn(account: account, signedIn: signedIn),
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

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.account, required this.signedIn});

  final CalDavAccountStore account;
  final CalDavAccount signedIn;

  @override
  Widget build(BuildContext context) {
    final lists = account.taskLists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountIdentityRow(
          name: signedIn.label,
          detail: lists.isEmpty
              ? 'No task lists found'
              : lists.length == 1
              ? 'Task list: ${lists.single.name}'
              : '${lists.length} task lists: '
                    '${lists.map((l) => l.name).join(', ')}',
          actions: [
            SettingsIconButton(
              icon: FontAwesomeIcons.arrowsRotate,
              tooltip: 'Look for task lists again',
              onTap: account.refreshTaskLists,
            ),
            SettingsActionButton(
              label: 'Sign out',
              compact: true,
              onTap: account.signOut,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const AccountBlurb(
          'Open the todo board and choose Backups… to link it to one of '
          'these lists.',
        ),
      ],
    );
  }
}

/// The server address, user name and password, and Connect.
class _SignInForm extends StatefulWidget {
  const _SignInForm({required this.account});

  final CalDavAccountStore account;

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

  bool get _ready => calDavServerUri(_url.text) != null && !widget.account.busy;

  Future<void> _connect({String? trustedCertificate}) async {
    if (!_ready) return;
    await widget.account.signIn(
      url: _url.text,
      username: _user.text,
      password: _password.text,
      trustedCertificate: trustedCertificate,
    );
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
          'The address of your server, or of one task list on it. The shell '
          'asks it for your task lists before keeping anything.',
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
            if (widget.account.signingIn) ...[
              SettingsActionButton(
                label: 'Cancel',
                compact: true,
                onTap: widget.account.cancelSignIn,
              ),
              const SizedBox(width: 8),
            ],
            if (widget.account.untrustedCertificate case final untrusted?
                when !widget.account.busy) ...[
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
              loading: widget.account.busy,
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
