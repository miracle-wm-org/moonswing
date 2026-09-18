// The camera in the bar: click, choose an area, a window or a screen, and the PNG
// is on the disk and on the clipboard.
//
// The module owns nothing. The selection surfaces belong to the root (a bar
// module cannot create a window), and the shutter and the file belong to
// [CaptureStore] — one shutter for the machine, however many bars draw this icon.
// What is left here is the button, the menu, and the two states the button has to
// show: busy, and last-attempt-failed.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/capture/capture_config.dart';
import 'package:graceful_shell/capture/capture_flow.dart';
import 'package:graceful_shell/capture/capture_menu.dart';
import 'package:graceful_shell/capture/capture_sound.dart';
import 'package:graceful_shell/capture/capture_store.dart';
import 'package:graceful_shell/capture/selection_controller.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/tokens.dart';

export 'package:graceful_shell/capture/capture_config.dart'
    show ScreenshotConfig;

class ScreenshotButton extends StatefulWidget {
  const ScreenshotButton({super.key, this.store});

  /// The store this drives. Defaults to the singleton; a widget test passes
  /// its own, which is what keeps this testable with no compositor behind it.
  final CaptureStore? store;

  @override
  State<ScreenshotButton> createState() => _ScreenshotButtonState();
}

class _ScreenshotButtonState extends State<ScreenshotButton>
    with PopupHost<ScreenshotButton> {
  CaptureStore get _store => widget.store ?? CaptureStore.instance;

  @override
  void dispose() {
    closePopup();
    super.dispose();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    final sound = ShutterSoundStore.instance;
    openBarPopup(
      context,
      preferredConstraints: const BoxConstraints(maxWidth: 360, maxHeight: 400),
      child: ThemeProvider(
        child: ListenableBuilder(
          // Both, because they fail separately: a capture that did not happen
          // and a shutter that made no noise over one that did.
          listenable: Listenable.merge([_store, sound]),
          builder: (context, _) {
            // The capture's own failure wins — it is the one that cost the
            // user a photograph. A shutter that made no noise is what the row
            // says when there is nothing worse to say, and it needs saying at
            // all because the file is on the disk either way: the silence is
            // the only sign that anything went wrong.
            final note = _store.error ?? sound.error;
            return CaptureMenuCard(
              actions: [
                for (final mode in SelectionMode.values)
                  CaptureMenuAction.mode(mode, () => _start(mode)),
              ],
              note: note,
              noteIsError: note != null,
            );
          },
        ),
      ),
    );
  }

  void _start(SelectionMode mode) {
    closePopup();
    // Not awaited: the flow outlives this popup by design — the selection
    // surface goes up, the user takes as long as they like over it, and the
    // shutter and its notification happen through the store. Awaiting it here
    // would tie the whole capture to a widget that is about to be rebuilt.
    unawaited(runCaptureFlow(CaptureKind.screenshot, mode, store: _store));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final busy = _store.busy;
        return BarButton(
          active: isPopupOpen,
          onTapDown: (_) => _togglePopup(context),
          child: FaIcon(
            FontAwesomeIcons.camera,
            size: ShellFontSizes.secondary,
            // Dimmed while a shot is in flight, which is the whole feedback
            // this button gives: the shutter is a compositor round trip plus a
            // PNG encode, and without it a slow one reads as a dead icon.
            color: busy ? theme.muted : theme.foreground,
          ),
        );
      },
    );
  }
}

final Module screenshotModule = Module.simple<ScreenshotConfig>(
  configKey: 'screenshot',
  fromMap: (map) {
    final config = ScreenshotConfig.fromMap(map);
    // A side effect in `fromMap`, the shape `system_monitor.dart` has and for its
    // reason: the store is where the shutter reads its settings, and there may be
    // no panel carrying this module on the monitor that fires it.
    // `Module.simple`'s signature guard stops this re-running per keystroke.
    CaptureStore.instance.configureScreenshot(config);
    // The sound is pushed to its own store for the same reason the chime's is,
    // and from here rather than from `CaptureStore`: a spelling is resolved
    // once per edit rather than once per photograph, and a store under test
    // stays out of the singleton the shell actually plays through.
    ShutterSoundStore.instance.configure(config.soundConfig);
    return config;
  },
  builder: (context, config) => const ScreenshotButton(),
);
