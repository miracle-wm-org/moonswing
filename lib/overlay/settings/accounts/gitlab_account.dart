// Settings › Accounts › GitLab: the one place the shell signs in to GitLab —
// gitlab.com or a self-managed instance.
//
// A form, like CalDAV's, because the sign-in is a personal access token (see
// `gitlab/gitlab_api.dart` for why not OAuth): the instance's address, a button
// that opens its token page with the name and the read-only scope already
// filled in, a field to paste the token into, and Connect — which asks the
// instance who the token belongs to before anything is kept.

import 'package:flutter/widgets.dart';

import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/gitlab/gitlab_account_store.dart';
import 'package:moonswing/gitlab/gitlab_api.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/overlay/settings/accounts/account_card.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The GitLab card.
class GitlabAccountCard extends StatelessWidget {
  const GitlabAccountCard({super.key, required this.account});

  final GitlabAccountStore account;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final error = account.error;
        return AccountProviderCard(
          brand: AccountBrand.gitlab,
          tagline: 'Merge requests, issues and to-dos',
          state: switch (account.stage) {
            GitlabAuthStage.signedOut => AccountLinkState.none,
            GitlabAuthStage.connecting => AccountLinkState.pending,
            GitlabAuthStage.signedIn => AccountLinkState.linked,
          },
          info:
              'gitlab.com or your own instance. GitLab is linked with a '
              'personal access token: Create a token opens your instance\'s '
              'token page with the name and the read_api scope filled in — '
              'read-only access to the API, nothing else. Choose an expiry, '
              'create it, and paste it here. The token is kept in '
              '~/.local/state/moonswing at 0600. Marking to-dos done from the '
              'Code tab needs the api scope instead; with read_api they can '
              'still be opened. Signing out forgets the token here; revoking '
              'it is done on the same page it was made on.',
          usedBy: const [(ShellGlyph.code, 'Code tab')],
          children: [
            if (error.isNotEmpty) ...[
              SettingsBanner(
                title: 'GitLab account',
                message: error,
                action: SettingsActionButton(
                  label: 'Dismiss',
                  compact: true,
                  onTap: account.clearError,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (account.signedIn)
              AccountIdentityRow(
                name: account.label,
                detail: account.name.isEmpty
                    ? 'Personal access token'
                    : '${account.name} · personal access token',
                actions: [
                  SettingsIconButton(
                    icon: ShellGlyph.externalLink,
                    tooltip: 'Open your profile on ${account.host}',
                    onTap: account.openProfile,
                  ),
                  SettingsIconButton(
                    icon: ShellGlyph.key,
                    tooltip: 'Manage tokens on ${account.host}',
                    onTap: account.openTokenPage,
                  ),
                  SettingsActionButton(
                    label: 'Sign out',
                    compact: true,
                    onTap: account.signOut,
                  ),
                ],
              )
            else
              _ConnectForm(account: account),
          ],
        );
      },
    );
  }
}

/// The instance, the token, and Connect.
class _ConnectForm extends StatefulWidget {
  const _ConnectForm({required this.account});

  final GitlabAccountStore account;

  @override
  State<_ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends State<_ConnectForm> {
  final TextEditingController _host = TextEditingController(
    text: kGitlabDefaultHost,
  );
  final TextEditingController _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    _host.addListener(_changed);
    _token.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _host.dispose();
    _token.dispose();
    super.dispose();
  }

  GitlabAccountStore get _account => widget.account;

  bool get _ready =>
      gitlabInstanceUri(_host.text) != null &&
      _token.text.trim().isNotEmpty &&
      !_account.connecting;

  Future<void> _connect() async {
    if (!_ready) return;
    final kept = await _account.connect(host: _host.text, token: _token.text);
    // The token leaves the form once it is kept, rather than sitting in a
    // controller for as long as the page is open.
    if (kept && mounted) _token.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final host = _host.text.trim();
    final invalid = host.isNotEmpty && gitlabInstanceUri(host) == null;
    final instance = gitlabInstanceUri(host)?.host ?? 'your instance';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccountBlurb(
          'Create a read-only token on your GitLab, paste it here, and the '
          'shell asks GitLab who it belongs to before keeping anything.',
        ),
        const SizedBox(height: 10),
        const _Label('GitLab instance'),
        SettingsTextField(
          controller: _host,
          hint: kGitlabDefaultHost,
          onChanged: (_) {},
          onSubmitted: (_) => _connect(),
        ),
        if (invalid || gitlabIsInsecure(host)) ...[
          const SizedBox(height: 4),
          Text(
            invalid
                ? 'Give the address of a GitLab: gitlab.com, or '
                      'https://gitlab.example.com.'
                : 'An http:// address sends the token unencrypted. Use '
                      'https:// unless the instance is on a network you trust.',
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: kErrorColor,
            ),
          ),
        ],
        const SizedBox(height: 10),
        const _Label('Personal access token'),
        Row(
          children: [
            Expanded(
              child: SettingsTextField(
                controller: _token,
                obscureText: true,
                hint: 'glpat-…',
                onChanged: (_) {},
                onSubmitted: (_) => _connect(),
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Create a token',
              icon: ShellGlyph.externalLink,
              compact: true,
              enabled: !invalid,
              onTap: () => _account.openTokenPage(host),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Opens $instance with the read_api scope ticked.',
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_account.connecting) ...[
              SettingsActionButton(
                label: 'Cancel',
                compact: true,
                onTap: _account.cancelConnect,
              ),
              const SizedBox(width: 8),
            ],
            SettingsActionButton(
              label: 'Connect',
              primary: true,
              compact: true,
              enabled: _ready,
              loading: _account.connecting,
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
