// The prompt polkit cannot draw for itself.
//
// One card in the middle of a full-output layer-shell surface, in the shell's own
// theme — the scaffold the power menu and the screencast consent picker sit on,
// because it is the same kind of question: something is asking for authority the
// user has to grant deliberately, and the surface has to be unmistakably the
// shell's rather than the application's.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_config.dart';
import 'package:graceful_shell/theme/tokens.dart';

import 'auth_session.dart';
import 'polkit_types.dart';

/// The card's width.
///
/// Fixed rather than a fraction of the output: what it holds is a sentence
/// polkit wrote and a single field, and a prompt that was half a screen wide
/// on one monitor and a third on another would read as two different dialogs.
const double kPolkitDialogWidth = 440;

/// The polkit prompt.
class PolkitAuthDialog extends StatefulWidget {
  const PolkitAuthDialog({
    super.key,
    required this.session,
    required this.closingNotifier,
    required this.onClosed,
  });

  final PolkitAuthSession session;

  /// Flipped by the owner to start the exit animation; [onClosed] follows and
  /// is what tears the native window down.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  @override
  State<PolkitAuthDialog> createState() => _PolkitAuthDialogState();
}

class _PolkitAuthDialogState extends State<PolkitAuthDialog> {
  final TextEditingController _response = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'polkit-response');

  /// The card's own node. Normally idle — the response field holds the focus
  /// — but it is what Escape arrives on once there is no field left to type
  /// in, which is the state a missing helper leaves the card in.
  final FocusNode _cardFocus = FocusNode(debugLabel: 'polkit-dialog');

  /// Which attempt the field's contents belong to. A retry (or an identity
  /// switch) empties it; nothing else does — an `info` line arriving while
  /// somebody is halfway through typing must not take what they have typed.
  int _shownAttempt = 0;

  /// False until `initState` has returned.
  ///
  /// [PolkitAuthSession.start] notifies synchronously — the helper is spawned
  /// from it and the card's first frame should already show an attempt under way
  /// — and `setState` from inside `initState` is a `markNeedsBuild` on an element
  /// that has not built once. The build that follows reads the session's fields
  /// anyway, so nothing is lost.
  bool _built = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    // The helper is started here and nowhere else: a request nobody is
    // showing must never spawn a setuid process. See [PolkitAuthController].
    widget.session.start();
    _shownAttempt = widget.session.attempt;
    _built = true;
  }

  @override
  void didUpdateWidget(PolkitAuthDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The root closes one prompt before it opens the next, so a session swap
    // under a live dialog is not a state it reaches today — but the widget
    // carries no key, so `canUpdate` would let one through, and a listener
    // left on the old session is a card that never updates again above a
    // helper nobody started.
    if (identical(oldWidget.session, widget.session)) return;
    oldWidget.session.removeListener(_onSessionChanged);
    widget.session.addListener(_onSessionChanged);
    widget.session.start();
    _shownAttempt = widget.session.attempt;
    _response.clear();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _response.dispose();
    _fieldFocus.dispose();
    _cardFocus.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final session = widget.session;
    if (session.attempt != _shownAttempt) {
      _shownAttempt = session.attempt;
      _response.clear();
    }
    if (session.isFinished) {
      if (_lingers(session.outcome!)) {
        // The field is about to be removed, and with it the focus Escape and
        // the Close button's keyboard route were arriving on.
        _cardFocus.requestFocus();
      } else {
        widget.closingNotifier.value = true;
      }
    }
    if (_built) setState(() {});
  }

  /// Whether a finished session stays on screen for the user to read.
  ///
  /// Only [PolkitAuthOutcome.unavailable] does. The other three are answers to
  /// something the user just did, and a card that had to be dismissed afterwards
  /// would be asking them to acknowledge their own action. "There is no polkit
  /// helper on this machine" is the opposite: it is news, nothing the user typed
  /// caused it, and a dialog that vanished while delivering it is the flash this
  /// state exists to prevent.
  bool _lingers(PolkitAuthOutcome outcome) =>
      outcome == PolkitAuthOutcome.unavailable;

  void _submit() {
    final session = widget.session;
    if (session.stage != PolkitAuthStage.prompting) return;
    session.submit(_response.text);
    _response.clear();
  }

  void _cancel() {
    if (widget.session.isFinished) {
      widget.closingNotifier.value = true;
      return;
    }
    widget.session.cancel();
  }

  void _retry() {
    _response.clear();
    widget.session.retry();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final session = widget.session;
    final answerable = session.canPrompt && !session.isFinished;
    // Its own text root, like the power menu and for its reason: every window
    // gets one from `_windowChrome`, but a widget test pumping this alone
    // must not have to supply a `Directionality` that release-mode `Text`
    // null-asserts on.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: ShellFontSizes.body,
          color: theme.popupForeground,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.normal,
        ),
        // No `autofocus` while there is a field below — the response field takes
        // it, and this node is its ancestor, so Escape still arrives by
        // propagation. Two autofocus nodes in one scope resolve in tree order, so
        // an ancestor asking for focus would take it *from* the field the user
        // has to type in. With no field there is nothing else to hold it.
        child: Focus(
          focusNode: _cardFocus,
          autofocus: !answerable,
          onKeyEvent: _onKey,
          child: FadeOverlayScaffold(
            closing: widget.closingNotifier,
            onClosed: widget.onClosed,
            // Dismissing *is* the denial, which is why the backdrop answers
            // it rather than doing nothing: the shell has no input-region
            // support, so this surface swallows every click on the monitor,
            // and a prompt with no way out for a mouse-only user is a prompt
            // that has taken the screen hostage.
            onBackdropTap: _cancel,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GestureDetector(
                // The card is not the backdrop: a click between two rows of
                // it must not answer the dialog.
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kPolkitDialogWidth,
                  ),
                  child: PopupCard(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    child: _body(theme, answerable),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeConfig theme, bool answerable) {
    final session = widget.session;
    final identity = session.identity;
    final busy = session.stage == PolkitAuthStage.checking ||
        session.stage == PolkitAuthStage.starting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme),
        const SizedBox(height: 14),
        Text(
          session.request.displayMessage,
          style: TextStyle(
            fontSize: ShellFontSizes.label,
            color: theme.popupForeground,
            height: 1.35,
          ),
        ),
        if (session.request.identities.length > 1) ...[
          const SizedBox(height: 14),
          _IdentityPicker(
            identities: session.request.identities,
            selected: session.selectedIndex,
            enabled: answerable,
            onSelected: session.selectIdentity,
          ),
        ] else if (identity != null) ...[
          const SizedBox(height: 8),
          Text(
            'Authenticating as ${identity.displayName}',
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              color: theme.muted,
            ),
          ),
        ],
        if (answerable) ...[
          const SizedBox(height: 16),
          Text(
            session.prompt,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              color: theme.muted,
            ),
          ),
          const SizedBox(height: 6),
          _ResponseField(
            controller: _response,
            focusNode: _fieldFocus,
            obscure: !session.echo,
            enabled: session.stage == PolkitAuthStage.prompting,
            hasError: session.error != null,
            onSubmitted: _submit,
          ),
        ],
        if (session.info case final info?) ...[
          const SizedBox(height: 10),
          _Notice(text: info, color: theme.muted),
        ],
        if (session.error case final error?) ...[
          const SizedBox(height: 10),
          _Notice(text: error, color: kErrorColor),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                session.request.actionId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: theme.muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _DialogButton(
              label: session.isFinished ? 'Close' : 'Cancel',
              onTap: _cancel,
            ),
            // Only over `unavailable`, and only because nothing was checked:
            // see [PolkitAuthSession.canRetry]. Without it the one outcome
            // whose cause is usually somewhere else on the machine is also
            // the one the user has to close and re-provoke the whole
            // privileged action to have another go at.
            if (session.canRetry) ...[
              const SizedBox(width: 8),
              _DialogButton(
                label: 'Try again',
                primary: true,
                onTap: _retry,
              ),
            ],
            if (answerable) ...[
              const SizedBox(width: 8),
              _DialogButton(
                label: busy ? 'Checking…' : 'Authenticate',
                primary: true,
                // Disabled rather than hidden while PAM has the answer:
                // `pam_unix` delays a refusal by seconds, and a button that
                // disappeared for those seconds would move everything under
                // it twice per attempt.
                enabled: session.stage == PolkitAuthStage.prompting,
                onTap: _submit,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _header(ThemeConfig theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.accent,
            borderRadius: BorderRadius.circular(ShellRadii.pill),
          ),
          // A padlock, drawn here rather than resolved from
          // `PolkitAuthRequest.iconName`: that is a themed icon name and this
          // path has no icon-theme lookup, and every one of these prompts
          // means the same thing however the action chose to illustrate it.
          child: const FaIcon(
            FontAwesomeIcons.lock,
            size: 16,
            color: kOnAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Authentication required',
            style: TextStyle(
              fontSize: ShellFontSizes.title,
              fontWeight: FontWeight.w600,
              color: theme.popupForeground,
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of coloured advice — a PAM error, or a `PAM_TEXT_INFO`.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: ShellFontSizes.secondary,
          color: color,
          height: 1.3,
        ),
      );
}

/// The field PAM's prompt is answered in.
class _ResponseField extends StatelessWidget {
  const _ResponseField({
    required this.controller,
    required this.focusNode,
    required this.obscure,
    required this.enabled,
    required this.hasError,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// False for `PAM_PROMPT_ECHO_ON` — a one-time code or a username is not a
  /// secret, and obscuring one makes it impossible to check before sending.
  final bool obscure;

  final bool enabled;
  final bool hasError;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(
          color: hasError ? kErrorColor : theme.accent.withValues(alpha: 0.8),
        ),
      ),
      child: EditableText(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: ShellFontSizes.label,
          color: theme.popupForeground,
        ),
        cursorColor: theme.accent,
        backgroundCursorColor: theme.muted,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        readOnly: !enabled,
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}

/// Which account is answering, when polkit named more than one.
///
/// A row of chips rather than a dropdown: there are two or three at most, the
/// choice changes what the password field means, and a control that has to be
/// opened to see the alternatives hides exactly that.
class _IdentityPicker extends StatelessWidget {
  const _IdentityPicker({
    required this.identities,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<PolkitIdentity> identities;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Authenticate as',
          style: TextStyle(
            fontSize: ShellFontSizes.secondary,
            color: theme.muted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, identity) in identities.indexed)
              HoverRegion(
                enabled: enabled,
                onTap: () => onSelected(index),
                builder: (context, hovered) {
                  final on = index == selected;
                  return Container(
                    constraints: const BoxConstraints(
                      minHeight: ShellSizes.minTapTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? theme.accent
                          : (hovered ? theme.surfaceHover : theme.surfacePressed),
                      borderRadius: BorderRadius.circular(ShellRadii.pill),
                      border: Border.all(
                        color: on ? theme.accent : theme.divider,
                      ),
                    ),
                    child: Text(
                      identity.displayName,
                      style: TextStyle(
                        fontSize: ShellFontSizes.secondary,
                        color: on ? kOnAccent : theme.popupForeground,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// The dialog's own button. Hand-rolled rather than borrowed from
/// `overlay/settings/controls.dart`: that library is the settings pane's, and
/// this surface is not under it — the power menu draws its own tiles for the
/// same reason.
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      enabled: enabled,
      onTap: onTap,
      builder: (context, hovered) {
        final lit = enabled && hovered;
        final background = primary
            ? (lit ? theme.accent.withValues(alpha: 0.85) : theme.accent)
            : (lit ? theme.surfaceHover : theme.surfacePressed);
        final foreground = primary ? kOnAccent : theme.popupForeground;
        return Opacity(
          opacity: enabled ? 1.0 : 0.55,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: ShellSizes.iconButton,
              minWidth: 88,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(ShellRadii.control),
              border: Border.all(
                color: primary ? theme.accent : theme.divider,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: ShellFontSizes.body,
                color: foreground,
              ),
            ),
          ),
        );
      },
    );
  }
}
