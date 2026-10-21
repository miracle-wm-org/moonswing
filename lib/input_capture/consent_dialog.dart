// The input-capture consent prompt: an application (DeskFlow, Input Leap) asks
// to take this machine's keyboard and mouse whenever the pointer is pushed off a
// screen edge, and the user says yes or no.
//
// Modal, like the screencast picker and for its reason: dismissing it — Escape, a
// click outside, Deny — is the refusal, and only its controller may answer.
// There is deliberately no keyboard shortcut for *Allow*: the prompt takes focus
// as it appears, and an Enter meant for whatever the user was typing into must
// not hand that keyboard to another program.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

import 'consent_types.dart';

const double kInputCaptureDialogWidth = 460;

/// The chord that always takes input back — kept beside the prompt that
/// promises it.
const String kInputCaptureEscapeChord = 'Super+Shift+Escape';

class InputCaptureConsentDialog extends StatefulWidget {
  const InputCaptureConsentDialog({
    super.key,
    required this.request,
    required this.closingNotifier,
    required this.onClosed,
    required this.onAllow,
    required this.onDeny,
  });

  final InputCaptureConsentRequest request;

  /// Flipped by the owner to start the exit animation; [onClosed] follows.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  final VoidCallback onAllow;
  final VoidCallback onDeny;

  @override
  State<InputCaptureConsentDialog> createState() =>
      _InputCaptureConsentDialogState();
}

class _InputCaptureConsentDialogState extends State<InputCaptureConsentDialog> {
  bool _answered = false;

  void _allow() {
    if (_answered) return;
    _answered = true;
    widget.onAllow();
    widget.closingNotifier.value = true;
  }

  void _deny() {
    if (_answered) return;
    _answered = true;
    widget.onDeny();
    widget.closingNotifier.value = true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _deny();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Its own text root, like the polkit prompt: a widget test pumping this
    // alone must not have to supply the `Directionality` every window gets
    // from `_windowChrome`.
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
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: FadeOverlayScaffold(
            closing: widget.closingNotifier,
            onClosed: widget.onClosed,
            // Dismissing is the denial; see the polkit prompt for why the
            // backdrop must answer rather than do nothing.
            onBackdropTap: _deny,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GestureDetector(
                // The card is not the backdrop.
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kInputCaptureDialogWidth,
                  ),
                  child: PopupCard(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    child: _body(theme),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeConfig theme) {
    final request = widget.request;
    final app = request.appId.isEmpty ? 'An application' : request.appId;
    final devices = [
      if (request.keyboard) 'keyboard',
      if (request.pointer) 'mouse',
    ].join(' and ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(ShellRadii.pill),
              ),
              child: const ShellIcon(
                ShellGlyph.mouse,
                size: 16,
                color: kOnAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Share your $devices?',
                style: TextStyle(
                  fontSize: ShellFontSizes.title,
                  fontWeight: FontWeight.w600,
                  color: theme.popupForeground,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '$app wants to use this computer\'s $devices. When you push the '
          'pointer past the edge of the screen, your $devices will control '
          'another computer through it until it hands them back.',
          style: TextStyle(
            fontSize: ShellFontSizes.label,
            color: theme.popupForeground,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Press $kInputCaptureEscapeChord at any time to take them back.',
          style: TextStyle(
            fontSize: ShellFontSizes.secondary,
            color: theme.muted,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ConsentButton(label: 'Deny', onTap: _deny),
            const SizedBox(width: 8),
            _ConsentButton(label: 'Allow', primary: true, onTap: _allow),
          ],
        ),
      ],
    );
  }
}

/// The dialog's own button, hand-rolled for the polkit prompt's reason: the
/// settings controls library is the settings pane's, and this surface is not
/// under it.
class _ConsentButton extends StatelessWidget {
  const _ConsentButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final background = primary
            ? (hovered ? theme.accent.withValues(alpha: 0.85) : theme.accent)
            : (hovered ? theme.surfaceHover : theme.surfacePressed);
        return Container(
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
              color: primary ? kOnAccent : theme.popupForeground,
            ),
          ),
        );
      },
    );
  }
}
