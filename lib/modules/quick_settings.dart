// The bar's quick settings button: the network, Bluetooth and volume at a
// glance, and a click away from switching any of them — see
// `lib/quick_panel/quick_settings_panel.dart` for the panel it opens.
//
// The button itself reads three stores — the connection, the adapter and the
// default output — so it holds their leases for as long as it is in a bar.
// None of them polls except the connection, which is the network module's one
// shared poller; the rest are woken by the system's own signals.

import 'package:flutter/widgets.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/level_slider.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/modules/network.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/quick_panel/audio_devices_store.dart';
import 'package:moonswing/quick_panel/bluetooth_store.dart';
import 'package:moonswing/quick_panel/quick_settings_panel.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/scroll_steps.dart';
import 'package:moonswing/theme/theme_provider.dart';

/// The glyphs the button shows, in bar order, worked out from what the three
/// stores report. Pure, so a test can pin it without a bus.
///
/// The connection is always there — dimmed when there is none, so the button
/// never collapses to nothing; Bluetooth only while the adapter is on, which is
/// when it is worth a glance; the volume once the sound server has named a
/// default output.
@visibleForTesting
List<({ShellGlyph glyph, bool dim})> quickSettingsGlyphs({
  required NetworkInfo connection,
  required bool bluetoothOn,
  required AudioDevice? output,
}) => [
  (
    glyph: connection.type == NetworkType.ethernet
        ? ShellGlyph.ethernet
        : ShellGlyph.wifi,
    dim: connection.type == NetworkType.none,
  ),
  if (bluetoothOn) (glyph: ShellGlyph.bluetooth, dim: false),
  if (output != null)
    (
      glyph: output.muted
          ? ShellGlyph.volumeMuted
          : output.volume <= 0.0
          ? ShellGlyph.volumeOff
          : output.volume <= 0.5
          ? ShellGlyph.volumeLow
          : ShellGlyph.volumeHigh,
      dim: output.muted,
    ),
];

class QuickSettingsButton extends StatefulWidget {
  const QuickSettingsButton({super.key, this.services});

  /// Defaults to the process-wide stores; a widget test passes its own.
  final QuickSettingsServices? services;

  @override
  State<QuickSettingsButton> createState() => QuickSettingsButtonState();
}

class QuickSettingsButtonState extends State<QuickSettingsButton>
    with PopupHost<QuickSettingsButton> {
  late final QuickSettingsServices _services =
      widget.services ?? QuickSettingsServices();

  @override
  void initState() {
    super.initState();
    _services.network.acquire();
    _services.bluetooth.acquire();
    _services.audio.acquire();
  }

  @override
  void dispose() {
    closePopup();
    _services.network.release();
    _services.bluetooth.release();
    _services.audio.release();
    super.dispose();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      // Width pinned, height the card's own — which the panel keeps constant
      // for as long as it is open. The maximum is a runaway guard.
      preferredConstraints: const BoxConstraints(
        minWidth: kQuickSettingsWidth,
        maxWidth: kQuickSettingsWidth,
        maxHeight: 600,
      ),
      child: ThemeProvider(
        child: QuickSettingsPanel(
          services: _services,
          onClose: closePopup,
          // Snapshotted: popup content has no DisplayScope of its own, and a
          // panel does not change screens while it is open.
          output: DisplayScope.of(context)?.name,
        ),
      ),
    );
  }

  /// Scrolling over the button steps the output volume, as it does over the
  /// sound module.
  void _scrollVolume(int steps) {
    final audio = _services.audio;
    final output = audio.current(AudioDirection.output);
    if (output == null) return;
    final next = scrolledLevel(output.volume, steps);
    if (next == output.volume) return;
    audio.setVolume(AudioDirection.output, next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ScrollSteps(
      onSteps: _scrollVolume,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _services.network,
          _services.bluetooth,
          _services.audio,
        ]),
        builder: (context, _) {
          final glyphs = quickSettingsGlyphs(
            connection: _services.network.info,
            bluetoothOn:
                _services.bluetooth.status == BluetoothStatus.ready &&
                _services.bluetooth.powered,
            output: _services.audio.current(AudioDirection.output),
          );
          return BarButton(
            active: isPopupOpen,
            // Tap-*down*, like every bar button that opens a surface: the
            // coordinator's reopen guard is armed and consumed inside the one
            // pointer-down.
            onTapDown: (_) => _togglePopup(context),
            child: BarFlex(
              spacing: 8,
              verticalSpacing: 6,
              children: [
                for (final g in glyphs)
                  ShellIcon(
                    g.glyph,
                    size: 12,
                    color: g.dim
                        ? theme.foreground.withValues(alpha: 0.4)
                        : theme.foreground,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

final Module quickSettingsModule = Module.plain(
  configKey: 'quick_settings',
  builder: (_) => const QuickSettingsButton(),
);
