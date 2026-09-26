// Settings › Accounts › Claude: where the shell is given a Claude API key.
//
// Not a browser sign-in like its neighbours. The account a program may use is
// a Claude Console key — a claude.ai Pro or Max subscription signs in to
// Anthropic's own apps only (`claude/claude_api.dart` says why) — so the card
// is a field to paste one into, checked against the API before it is kept,
// and a link to the Console page that makes one.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/claude/claude_account_store.dart';
import 'package:moonswing/overlay/settings/accounts/account_card.dart';
import 'package:moonswing/overlay/settings/controls.dart';

/// The Claude card.
class ClaudeAccountCard extends StatelessWidget {
  const ClaudeAccountCard({super.key, required this.account});

  final ClaudeAccountStore account;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final stage = account.stage;
        final error = account.error;
        return AccountProviderCard(
          brand: AccountBrand.claude,
          tagline: 'Questions and generated UI, from the panel',
          state: switch (stage) {
            ClaudeAuthStage.signedOut => AccountLinkState.none,
            ClaudeAuthStage.verifying => AccountLinkState.pending,
            ClaudeAuthStage.signedIn => AccountLinkState.linked,
          },
          info:
              'Link a Claude API key once for the whole shell. The Claude bar '
              'module sends your questions with it, and can answer with a '
              'small generated UI when a form or a few controls would help '
              'more than a paragraph. Keys are made in the Claude Console and '
              'billed to that Console account per use; a claude.ai Pro or Max '
              'subscription cannot be used by other apps. The key is checked '
              'before it is kept, and kept in ~/.local/state/moonswing at '
              '0600. Unlinking forgets it here; revoking it is done in the '
              'Console.',
          usedBy: const [(FontAwesomeIcons.wandMagicSparkles, 'Claude module')],
          children: [
            if (error.isNotEmpty) ...[
              SettingsBanner(
                title: 'Claude account',
                message: error,
                action: SettingsActionButton(
                  label: 'Dismiss',
                  compact: true,
                  onTap: account.clearError,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (stage == ClaudeAuthStage.signedIn)
              AccountIdentityRow(
                name: 'Claude API key',
                detail: account.keyHint,
                actions: [
                  SettingsIconButton(
                    icon: FontAwesomeIcons.chartColumn,
                    tooltip: 'See usage in the Claude Console',
                    onTap: account.openConsoleUsage,
                  ),
                  SettingsIconButton(
                    icon: FontAwesomeIcons.key,
                    tooltip: 'Manage or revoke keys in the Claude Console',
                    onTap: account.openConsoleKeys,
                  ),
                  SettingsActionButton(
                    label: 'Unlink',
                    compact: true,
                    onTap: account.signOut,
                  ),
                ],
              )
            else
              _KeyEntry(account: account),
          ],
        );
      },
    );
  }
}

/// The field a key is pasted into, and the two buttons beside it.
class _KeyEntry extends StatefulWidget {
  const _KeyEntry({required this.account});

  final ClaudeAccountStore account;

  @override
  State<_KeyEntry> createState() => _KeyEntryState();
}

class _KeyEntryState extends State<_KeyEntry> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    await widget.account.signIn(_controller.text);
    // The field is emptied once the key is taken; a rejected one stays, so a
    // stray space or a missing character can be fixed rather than re-pasted.
    if (mounted && widget.account.signedIn) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccountBlurb(
          'Paste an API key from the Claude Console. It is checked with '
          'Anthropic before it is kept, and never leaves this computer except '
          'to the Claude API.',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SettingsTextField(
                controller: _controller,
                hint: 'sk-ant-…',
                obscureText: true,
                onChanged: (_) {},
                onSubmitted: (_) => _link(),
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Link',
              primary: true,
              compact: true,
              loading: account.busy,
              enabled: !account.busy,
              onTap: _link,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SettingsActionButton(
              label: 'Get a key in the Console',
              icon: FontAwesomeIcons.arrowUpRightFromSquare,
              compact: true,
              onTap: account.openConsoleKeys,
            ),
          ],
        ),
      ],
    );
  }
}
