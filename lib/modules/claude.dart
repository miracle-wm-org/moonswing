// The bar's Claude strip: an AI mark, and a popup to ask it things in.
//
// Everything that is not rendering — the conversation, the request, the
// generated surfaces — is `lib/claude/`, one store for the machine, so closing
// the popup mid-answer loses nothing and two bars show one conversation. The
// account is Settings › Accounts', like every other service's; a popup with no
// key behind it sends the user there.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:genui/genui.dart' show Surface;
import 'package:material_symbols_icons/symbols.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/accounts/brand_marks.dart';
import 'package:moonswing/bar_button.dart';
import 'package:moonswing/claude/claude_account_store.dart';
import 'package:moonswing/claude/claude_chat_store.dart';
import 'package:moonswing/claude/claude_config.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

export 'package:moonswing/claude/claude_config.dart' show ClaudeConfig;

/// The popup's size — both axes fixed, for the reason `kGithubPopupHeight`
/// gives: a popup surface is measured once, and this one's content grows by
/// the token. The conversation scrolls inside it.
const double kClaudePopupWidth = 440;
const double kClaudePopupHeight = 560;

/// The bar module.
class ClaudeButton extends StatefulWidget {
  const ClaudeButton({super.key, this.chat});

  /// Injected by tests. Null reads the [AccountsScope].
  final ClaudeChatStore? chat;

  @override
  State<ClaudeButton> createState() => _ClaudeButtonState();
}

class _ClaudeButtonState extends State<ClaudeButton>
    with PopupHost<ClaudeButton> {
  late final ClaudeChatStore _chat =
      widget.chat ?? AccountsScope.claudeChatOf(context);

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChanged);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChanged);
    closePopup();
    super.dispose();
  }

  // Only the busy flag is drawn on the button, and a store notification that
  // did not move it rebuilds nothing.
  late bool _busy = _chat.busy;

  void _onChanged() {
    if (!mounted || _chat.busy == _busy) return;
    setState(() => _busy = _chat.busy);
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      preferredConstraints: const BoxConstraints(
        minWidth: kClaudePopupWidth,
        maxWidth: kClaudePopupWidth,
        minHeight: kClaudePopupHeight,
        maxHeight: kClaudePopupHeight,
      ),
      // The question field types, and so does any text field Claude builds;
      // a panel takes no keyboard focus unless a popup borrows it.
      needsKeyboard: true,
      child: ThemeProvider(
        child: ClaudePopup(chat: _chat, onClose: closePopup),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return BarButton(
      active: isPopupOpen,
      onTapDown: (_) => _togglePopup(context),
      child: Icon(
        Symbols.auto_awesome,
        size: ShellFontSizes.title + 2,
        // Filled while an answer streams: the popup may be closed, and the
        // mark is then the only thing saying one is on its way.
        fill: _busy ? 1 : 0,
        color: _busy ? theme.accentText : theme.foreground,
      ),
    );
  }
}

/// The card behind the mark.
class ClaudePopup extends StatelessWidget {
  const ClaudePopup({
    super.key,
    required this.chat,
    this.onClose,
    this.openAccounts,
  });

  final ClaudeChatStore chat;
  final VoidCallback? onClose;

  /// Opens Settings › Accounts. Injected by tests.
  final VoidCallback? openAccounts;

  void _openAccounts() {
    final open = openAccounts;
    if (open != null) {
      open();
    } else {
      SettingsController.instance.open(SettingsRoute.accounts);
    }
    onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // [ShellTextRoot] because popup content lays out under its own FlutterView.
    return ShellTextRoot(
      style: TextStyle(
        color: theme.popupForeground,
        fontSize: ShellFontSizes.body,
      ),
      child: PopupCard(
        child: ListenableBuilder(
          listenable: chat.account,
          builder: (context, _) {
            final signedIn = chat.account.signedIn;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  chat: chat,
                  signedIn: signedIn,
                  onAccounts: _openAccounts,
                ),
                Container(height: 1, color: theme.divider),
                Expanded(
                  child: signedIn
                      ? _Conversation(chat: chat, onAccounts: _openAccounts)
                      : _SignedOut(
                          account: chat.account,
                          onAccounts: _openAccounts,
                        ),
                ),
                if (signedIn) ...[
                  Container(height: 1, color: theme.divider),
                  _Composer(chat: chat),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.chat,
    required this.signedIn,
    required this.onAccounts,
  });

  final ClaudeChatStore chat;
  final bool signedIn;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          const BrandMark(AccountBrand.claude, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Claude',
              style: TextStyle(
                fontSize: ShellFontSizes.label,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
          ),
          if (signedIn) ...[
            ListenableBuilder(
              listenable: chat,
              builder: (context, _) => SettingsIconButton(
                icon: FontAwesomeIcons.penToSquare,
                tooltip: 'New conversation',
                enabled: !chat.isEmpty,
                onTap: chat.clear,
              ),
            ),
            SettingsIconButton(
              icon: FontAwesomeIcons.userGear,
              tooltip: 'Account settings',
              onTap: onAccounts,
            ),
          ],
        ],
      ),
    );
  }
}

/// No key yet: where to link one.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.account, required this.onAccounts});

  final ClaudeAccountStore account;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandMark(AccountBrand.claude, size: 48)),
            const SizedBox(height: 14),
            Text(
              'Connect Claude',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.title,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Link a Claude API key once under Settings › Accounts, then ask '
              'anything here — and have Claude build a small UI when a form '
              'would help more than an answer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                height: 1.45,
                color: theme.popupForeground.withValues(alpha: 0.65),
              ),
            ),
            if (account.error.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ErrorLine(account.error, center: true),
            ],
            const SizedBox(height: 16),
            SettingsActionButton(
              label: 'Open Accounts settings',
              icon: FontAwesomeIcons.userGear,
              primary: true,
              onTap: onAccounts,
            ),
          ],
        ),
      ),
    );
  }
}

/// The conversation, newest at the bottom.
class _Conversation extends StatelessWidget {
  const _Conversation({required this.chat, required this.onAccounts});

  final ClaudeChatStore chat;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final items = chat.items;
        if (items.isEmpty) return const _Empty();
        // Reversed, so the list is anchored at its bottom: a growing answer
        // pushes older ones up rather than running off the end of the card.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[items.length - 1 - i];
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: switch (item) {
                ClaudeQuestion() => _QuestionBubble(item: item),
                ClaudeAnswer() => _AnswerView(
                  answer: item,
                  chat: chat,
                  onAccounts: onAccounts,
                ),
              },
            );
          },
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.auto_awesome,
              size: 32,
              color: theme.popupForeground.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 12),
            Text(
              'Ask a quick question, or ask for a UI — "make me a packing '
              'checklist", "a tip calculator".',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                height: 1.45,
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.item});

  final ClaudeQuestion item;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (item.fromUi) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FaIcon(
            FontAwesomeIcons.arrowPointer,
            size: ShellFontSizes.caption,
            color: theme.popupForeground.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.text,
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.popupForeground.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kClaudePopupWidth * 0.8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: Text(item.text, style: const TextStyle(height: 1.4)),
        ),
      ),
    );
  }
}

/// One answer: its text, any surfaces in it, and how it ended.
///
/// Its own [RepaintBoundary] and its own listener: tokens arriving rebuild and
/// repaint this answer, not the conversation above it.
class _AnswerView extends StatelessWidget {
  const _AnswerView({
    required this.answer,
    required this.chat,
    required this.onAccounts,
  });

  final ClaudeAnswer answer;
  final ClaudeChatStore chat;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: answer,
        builder: (context, _) {
          final theme = ThemeScope.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final part in answer.parts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: switch (part) {
                    ClaudeAnswerText(:final text) => ClaudeRichText(text),
                    ClaudeAnswerSurface(:final surfaceId) => Surface(
                      key: ValueKey(surfaceId),
                      surfaceContext: chat.surfaceContext(surfaceId),
                    ),
                  },
                ),
              if (answer.streaming && answer.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: LoadingIndicator(
                    size: 14,
                    color: theme.popupForeground,
                  ),
                ),
              if (answer.servedBy.isNotEmpty)
                _Note('Answered by ${answer.servedBy}'),
              ..._ending(context),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _ending(BuildContext context) {
    switch (answer.state) {
      case ClaudeAnswerState.streaming:
      case ClaudeAnswerState.done:
        return const [];
      case ClaudeAnswerState.truncated:
        return const [_Note('The answer was cut off at its length limit.')];
      case ClaudeAnswerState.stopped:
        return const [_Note('Stopped.')];
      case ClaudeAnswerState.refused:
        return [_ErrorLine(answer.error)];
      case ClaudeAnswerState.failed:
        return [
          _ErrorLine(answer.error),
          const SizedBox(height: 6),
          Row(
            children: [
              if (answer.needsAccount)
                SettingsActionButton(
                  label: 'Open Accounts settings',
                  compact: true,
                  onTap: onAccounts,
                )
              else
                SettingsActionButton(
                  label: 'Retry',
                  compact: true,
                  onTap: chat.retry,
                ),
            ],
          ),
        ];
    }
  }
}

/// Text with fenced code blocks drawn as code. The one piece of Markdown the
/// persona allows, because a command is the answer to half of what gets
/// asked from a shell.
class ClaudeRichText extends StatelessWidget {
  const ClaudeRichText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final segments = splitCodeFences(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (code, body) in segments)
          if (code)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.popupForeground.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(ShellRadii.control),
              ),
              child: Text(
                body,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: ShellFontSizes.secondary,
                  height: 1.35,
                  color: theme.popupForeground,
                ),
              ),
            )
          else if (body.trim().isNotEmpty)
            Text(body.trim(), style: const TextStyle(height: 1.45)),
      ],
    );
  }
}

/// `(isCode, text)` runs of [text], split on ``` fences. An unclosed fence —
/// an answer still streaming — is code up to the end. The fence's language tag
/// is dropped.
List<(bool, String)> splitCodeFences(String text) {
  final out = <(bool, String)>[];
  var rest = text;
  while (rest.isNotEmpty) {
    final open = rest.indexOf('```');
    if (open < 0) {
      out.add((false, rest));
      break;
    }
    if (open > 0) out.add((false, rest.substring(0, open)));
    final afterOpen = rest.substring(open + 3);
    final newline = afterOpen.indexOf('\n');
    final body = newline < 0 ? '' : afterOpen.substring(newline + 1);
    final close = body.indexOf('```');
    if (close < 0) {
      out.add((true, body.trimRight()));
      break;
    }
    out.add((true, body.substring(0, close).trimRight()));
    rest = body.substring(close + 3);
  }
  return out;
}

/// The question field and the send (or stop) button.
class _Composer extends StatefulWidget {
  const _Composer({required this.chat});

  final ClaudeChatStore chat;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.chat.busy) return;
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    widget.chat.ask(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: SettingsTextField(
              controller: _controller,
              autofocus: true,
              hint: 'Ask Claude…',
              onChanged: (_) {},
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          ListenableBuilder(
            listenable: widget.chat,
            builder: (context, _) => widget.chat.busy
                ? SettingsIconButton(
                    icon: FontAwesomeIcons.stop,
                    tooltip: 'Stop',
                    onTap: widget.chat.stop,
                  )
                : SettingsIconButton(
                    icon: FontAwesomeIcons.paperPlane,
                    tooltip: 'Send',
                    onTap: _send,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: ShellFontSizes.caption,
        color: theme.popupForeground.withValues(alpha: 0.5),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message, {this.center = false});

  final String message;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: center ? TextAlign.center : null,
      style: const TextStyle(
        fontSize: ShellFontSizes.caption,
        color: kErrorColor,
      ),
    );
  }
}

final Module claudeModule = Module.simple<ClaudeConfig>(
  configKey: 'claude',
  fromMap: (map) {
    final config = ClaudeConfig.fromMap(map);
    // Pushed into the store, the shape `github.dart` has: the store reads it
    // per question, and `Module.simple`'s signature guard stops this re-running
    // per keystroke in settings.
    ClaudeChatStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => const ClaudeButton(),
);
