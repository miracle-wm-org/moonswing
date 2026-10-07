// The video camera in the bar, and the only thing in the shell with two
// completely different jobs depending on what it is already doing.
//
// Idle it is the screenshot module with a different verb: a menu of the three
// ways to choose what to record. Recording it stops being a menu at all — the
// icon becomes a red dot beside a running readout, and the popup's first row is
// Stop. That asymmetry is the point: a recording is the one thing the shell can
// be doing that the user cannot see, so the bar has to say so and ending it has
// to be one click away.
//
// One recording for the machine. The state is [CaptureStore]'s, so the icon on
// every monitor's bar shows the same clock and any of them stops the same
// recording.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/capture/capture_config.dart';
import 'package:moonswing/capture/capture_flow.dart';
import 'package:moonswing/capture/capture_menu.dart';
import 'package:moonswing/capture/capture_store.dart';
import 'package:moonswing/capture/selection_controller.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_provider.dart';
import 'package:moonswing/theme/tokens.dart';

export 'package:moonswing/capture/capture_config.dart' show RecorderConfig;

class ScreenRecorderButton extends StatefulWidget {
  const ScreenRecorderButton({super.key, this.store});

  final CaptureStore? store;

  @override
  State<ScreenRecorderButton> createState() => _ScreenRecorderButtonState();
}

class _ScreenRecorderButtonState extends State<ScreenRecorderButton>
    with PopupHost<ScreenRecorderButton> {
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
    // The bar's context: the popup's content is under a FlutterView of its
    // own, with no `MiracleScope` above it.
    final modes = offeredSelectionModes(context);
    openBarPopup(
      context,
      preferredConstraints: const BoxConstraints(maxWidth: 360, maxHeight: 400),
      child: ThemeProvider(
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) => CaptureMenuCard(
            actions: [
              if (_store.recording)
                CaptureMenuAction(
                  icon: FontAwesomeIcons.stop,
                  label: 'Stop recording',
                  emphasis: true,
                  onTap: _stop,
                )
              else
                for (final mode in modes)
                  CaptureMenuAction.mode(mode, () => _start(mode)),
            ],
            note: _note(),
            noteIsError: !_store.recording && _store.error != null,
          ),
        ),
      ),
    );
  }

  /// What the line under the rows says: what is being recorded and for how
  /// long, or why the last attempt did not work.
  String? _note() {
    if (_store.stopping) return 'Finishing the file…';
    if (_store.recording) {
      final target = _store.recordingTarget;
      final elapsed = formatRecordingElapsed(_store.recordingElapsed);
      return target == null ? elapsed : '${target.label} · $elapsed';
    }
    return _store.error;
  }

  void _start(SelectionMode mode) {
    closePopup();
    unawaited(runCaptureFlow(CaptureKind.video, mode, store: _store));
  }

  void _stop() {
    closePopup();
    unawaited(_store.stopRecording());
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final recording = _store.recording;
        final stopping = _store.stopping;
        return BarButton(
          active: isPopupOpen || recording,
          onTapDown: (_) => _togglePopup(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                recording ? FontAwesomeIcons.solidCircle : FontAwesomeIcons.video,
                // The dot is deliberately smaller than the camera it replaces:
                // filled at the icon's own size it is a blob, and this one has
                // a readout beside it doing the talking.
                size: recording
                    ? ShellFontSizes.caption - 2
                    : ShellFontSizes.secondary,
                color: recording
                    ? kErrorColor
                    : (stopping ? theme.muted : theme.foreground),
              ),
              if (recording) ...[
                const SizedBox(width: 6),
                Text(
                  formatRecordingElapsed(_store.recordingElapsed),
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.foreground,
                    // Tabular, so a bar module whose text changes every second
                    // does not re-lay the whole panel as the digits change
                    // width. `lib/timers/` states the same rule.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

final Module screenRecorderModule = Module.simple<RecorderConfig>(
  configKey: 'screen_recorder',
  fromMap: (map) {
    final config = RecorderConfig.fromMap(map);
    // The store owns it, not the widget: the recording outlives any rebuild of
    // this button and every bar on every monitor shares the one recorder.
    CaptureStore.instance.configureRecorder(config);
    return config;
  },
  builder: (context, config) => const ScreenRecorderButton(),
);
