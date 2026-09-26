// Settings › Accounts › GitHub: the one place the shell signs in to GitHub.
//
// The device flow, drawn: a code appears here, github.com opens in the browser,
// the user types the code in, and the card turns into the account. The flow
// itself is `GithubAccountStore`'s, so closing the overlay half-way through
// loses nothing — reopening it shows the same code until it expires.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/accounts/account_card.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The GitHub card.
class GithubAccountCard extends StatelessWidget {
  const GithubAccountCard({
    super.key,
    required this.account,
    this.copy = copyTextToClipboard,
  });

  final GithubAccountStore account;

  /// How the user code reaches the clipboard. Injected by tests, which must not
  /// fork `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final stage = account.stage;
        final error = account.error;
        return AccountProviderCard(
          brand: AccountBrand.github,
          tagline: 'Notifications, reviews and mentions',
          state: switch (stage) {
            GithubAuthStage.signedOut => AccountLinkState.none,
            GithubAuthStage.requestingCode ||
            GithubAuthStage.awaitingAuthorization => AccountLinkState.pending,
            GithubAuthStage.signedIn => AccountLinkState.linked,
          },
          info:
              'Sign in once for the whole shell. The GitHub bar module shows '
              'your notification inbox from it, and any other module or '
              'desktop widget that reads GitHub uses the same account. The '
              'sign-in is GitHub\'s device flow: your password is typed into '
              'github.com, never into the shell, and the token it grants is '
              'kept in ~/.local/state/moonswing at 0600. Signing out forgets '
              'it here; revoking it is done on github.com.',
          usedBy: const [(FontAwesomeIcons.bell, 'GitHub notifications')],
          children: [
            if (error.isNotEmpty) ...[
              SettingsBanner(
                title: 'GitHub account',
                message: error,
                action: SettingsActionButton(
                  label: 'Dismiss',
                  compact: true,
                  onTap: account.clearError,
                ),
              ),
              const SizedBox(height: 12),
            ],
            switch (stage) {
              GithubAuthStage.signedOut ||
              GithubAuthStage.requestingCode => _SignedOut(account: account),
              GithubAuthStage.awaitingAuthorization => _DeviceCode(
                account: account,
                copy: copy,
              ),
              GithubAuthStage.signedIn => _SignedIn(account: account),
            },
          ],
        );
      },
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.account});

  final GithubAccountStore account;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: AccountBlurb(
            // Said before the button rather than after it: the user is about
            // to be sent to a browser, and what will happen there is the one
            // thing worth knowing first.
            'A code appears here and github.com opens in your browser, where '
            'you type it in. Your password never reaches the shell.',
          ),
        ),
        const SizedBox(width: 16),
        BrandSignInButton(
          AccountBrand.github,
          loading: account.busy,
          onTap: account.signIn,
        ),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.account});

  final GithubAccountStore account;

  @override
  Widget build(BuildContext context) {
    final login = account.login;
    return AccountIdentityRow(
      name: login.isEmpty ? 'Signed in' : login,
      detail: 'Access: ${account.scopes.split(RegExp(r'[\s,]+')).join(', ')}',
      actions: [
        if (login.isNotEmpty)
          SettingsIconButton(
            icon: FontAwesomeIcons.arrowUpRightFromSquare,
            tooltip: 'Open your profile on github.com',
            onTap: account.openProfile,
          ),
        SettingsIconButton(
          icon: FontAwesomeIcons.key,
          tooltip: 'Revoke access on github.com',
          onTap: account.openApplications,
        ),
        SettingsActionButton(
          label: 'Sign out',
          compact: true,
          onTap: account.signOut,
        ),
      ],
    );
  }
}

/// The user's half of the device flow: the code, and the two ways to get it to
/// GitHub.
class _DeviceCode extends StatelessWidget {
  const _DeviceCode({required this.account, required this.copy});

  final GithubAccountStore account;
  final Future<ClipboardResult> Function(String text) copy;

  /// `github.com/login/device` — the URL without its scheme, which is what a
  /// person reads out to themselves while typing it.
  static String _shortUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.hasAuthority) return uri;
    return '${parsed.host}${parsed.path}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final code = account.deviceCode;
    if (code == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountBlurb('Enter this code at ${_shortUri(code.verificationUri)}'),
        const SizedBox(height: 10),
        _UserCode(code: code.userCode, copy: copy),
        const SizedBox(height: 12),
        Row(
          children: [
            LoadingIndicator(size: 12, color: theme.popupForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Waiting for you to authorise the shell…',
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.55),
                ),
              ),
            ),
            SettingsActionButton(
              label: 'Open GitHub',
              icon: FontAwesomeIcons.arrowUpRightFromSquare,
              primary: true,
              compact: true,
              onTap: account.openVerificationPage,
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Cancel',
              compact: true,
              onTap: account.cancelSignIn,
            ),
          ],
        ),
      ],
    );
  }
}

/// The code itself: eight characters, spaced, and click-to-copy.
///
/// Through `wl-copy` rather than Flutter's own `Clipboard`, for the reason
/// `emoji/emoji_clipboard.dart` documents: a Wayland client cannot take the
/// selection without a seat and a serial, and every surface the shell owns is a
/// layer-shell one. `Clipboard.setData` from here is a silent no-op.
class _UserCode extends StatefulWidget {
  const _UserCode({required this.code, required this.copy});

  final String code;
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

  /// The line under the code, which is where a failed copy is reported. A
  /// missing helper names the *package*, never a package manager.
  String get _hint => switch (_result) {
    null => 'Click to copy',
    ClipboardResult.copied => 'Copied',
    ClipboardResult.unavailable =>
      'Install $kClipboardPackage to copy it, or type it in',
    ClipboardResult.failed => '$kClipboardCommand could not copy it',
  };

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return RepaintBoundary(
      child: HoverRegion(
        onTap: _copy,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: hovered
                ? theme.surfaceHover
                : theme.popupForeground.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(ShellRadii.control),
            border: Border.all(color: theme.divider),
          ),
          child: Column(
            children: [
              Text(
                widget.code,
                style: TextStyle(
                  fontSize: ShellFontSizes.heading,
                  fontWeight: FontWeight.w700,
                  // A string to be transcribed character by character, where a
                  // proportional face makes O and 0 the same picture.
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                  color: theme.popupForeground,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_result == null || _result == ClipboardResult.copied) ...[
                    FaIcon(
                      _result == null
                          ? FontAwesomeIcons.copy
                          : FontAwesomeIcons.check,
                      size: ShellFontSizes.caption,
                      color: theme.popupForeground.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    _hint,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      fontFamily: theme.fontFamily,
                      color:
                          _result == ClipboardResult.copied || _result == null
                          ? theme.popupForeground.withValues(alpha: 0.5)
                          : kErrorColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
