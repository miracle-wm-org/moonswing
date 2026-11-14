// The quick settings panel: the bar popup behind the `quick_settings` module.
//
// Wi-Fi and Bluetooth as two switches, the power mode, the default output and
// input with their levels, and the backlight — the handful of things most
// visits to Settings are for, each with a way through to the page that does
// the rest — and the power menu.
//
// Two rules shape the layout, both from how a popup window works:
//
// * **The card never changes height.** GTK places a popup once, at map time,
//   from the size of its first frame, and never revisits it — a card that grew
//   under a bottom bar would grow off the screen. So every section has a fixed
//   height whatever state its store is in (loading, failed, empty), and the one
//   section that depends on the machine — the backlight — is decided in
//   `initState`, before the first layout, from a synchronous read.
// * **A list is a page, not an expansion.** Picking a network, a Bluetooth
//   device or a sound device swaps the card's content for a page of that list
//   over the same box, with a way back — the main page is kept laid out
//   underneath, invisibly, so it is still what sizes the card.
//
// Nothing here takes the keyboard. Joining a secured network nobody has saved
// needs a password typed, and that is Settings › Network's: the row says so and
// goes there.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/level_slider.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/modules/brightness.dart';
import 'package:moonswing/modules/network.dart';
import 'package:moonswing/overlay/settings/bluetooth.dart';
import 'package:moonswing/overlay/settings_route.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/power/power_menu_controller.dart';
import 'package:moonswing/power_profile/power_profile_store.dart';
import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/quick_panel/audio_devices_store.dart';
import 'package:moonswing/quick_panel/bluetooth_store.dart';
import 'package:moonswing/quick_panel/wifi_store.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/theme/tokens.dart';

/// The card's width. Fixed, for the reason the volume popup gives: a slider
/// has no intrinsic length, and a popup whose width followed its labels would
/// walk away from the bar as a device name changed under it.
const double kQuickSettingsWidth = 340;

/// Which page of the card is showing.
enum QuickSettingsPage { main, wifi, bluetooth, output, input }

/// The stores and controllers the panel reads and pokes. Defaults to the
/// process-wide ones; a widget test passes its own.
class QuickSettingsServices {
  QuickSettingsServices({
    WifiStore? wifi,
    NetworkStatusStore? network,
    BluetoothStore? bluetooth,
    PowerProfileStore? power,
    AudioDevicesStore? audio,
    BacklightStore? backlight,
    SettingsController? settings,
    PowerMenuController? powerMenu,
  }) : wifi = wifi ?? WifiStore.instance,
       network = network ?? NetworkStatusStore.instance,
       bluetooth = bluetooth ?? BluetoothStore.instance,
       power = power ?? PowerProfileStore.instance,
       audio = audio ?? AudioDevicesStore.instance,
       backlight = backlight ?? BacklightStore.instance,
       settings = settings ?? SettingsController.instance,
       powerMenu = powerMenu ?? PowerMenuController.instance;

  final WifiStore wifi;
  final NetworkStatusStore network;
  final BluetoothStore bluetooth;
  final PowerProfileStore power;
  final AudioDevicesStore audio;
  final BacklightStore backlight;
  final SettingsController settings;
  final PowerMenuController powerMenu;
}

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    super.key,
    required this.services,
    required this.onClose,
    this.output,
  });

  final QuickSettingsServices services;

  /// Closes the popup — after a link to Settings or the power menu, which
  /// both open a surface of their own.
  final VoidCallback onClose;

  /// The connector of the bar the panel was opened from, so Settings opens on
  /// that screen. Snapshotted by the button: popup content has no
  /// `DisplayScope` of its own.
  final String? output;

  @override
  State<QuickSettingsPanel> createState() => QuickSettingsPanelState();
}

class QuickSettingsPanelState extends State<QuickSettingsPanel> {
  QuickSettingsServices get _s => widget.services;

  QuickSettingsPage _page = QuickSettingsPage.main;

  /// The page showing, for tests.
  @visibleForTesting
  QuickSettingsPage get page => _page;

  /// Whether the machine had a backlight when the panel opened. Frozen there,
  /// because it decides the card's height — see the file comment.
  late final bool _hasBacklight;

  @override
  void initState() {
    super.initState();
    _s.wifi.acquire();
    _s.network.acquire();
    _s.bluetooth.acquire();
    _s.power.acquire();
    _s.audio.acquire();
    _s.backlight.acquire();
    _hasBacklight = _s.backlight.level != null;
  }

  @override
  void dispose() {
    _s.wifi.release();
    _s.network.release();
    _s.bluetooth.release();
    _s.power.release();
    _s.audio.release();
    _s.backlight.release();
    super.dispose();
  }

  void _show(QuickSettingsPage page) {
    setState(() => _page = page);
    if (page == QuickSettingsPage.wifi && _s.wifi.radio.enabled) {
      unawaited(_s.wifi.scan());
    }
  }

  /// Opens Settings at [route] on this panel's screen and closes the panel.
  void _openSettings(SettingsRoute route) {
    _s.settings.open(route, widget.output);
    widget.onClose();
  }

  void _openPowerMenu() {
    widget.onClose();
    _s.powerMenu.toggle();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final main = _MainPage(
      services: _s,
      hasBacklight: _hasBacklight,
      onShow: _show,
      onSettings: _openSettings,
      onPowerMenu: _openPowerMenu,
    );
    final Widget? sub = switch (_page) {
      QuickSettingsPage.main => null,
      QuickSettingsPage.wifi => _WifiPage(
        store: _s.wifi,
        network: _s.network,
        onBack: () => _show(QuickSettingsPage.main),
        onSettings: () =>
            _openSettings(const SettingsRoute(category: 'network')),
      ),
      QuickSettingsPage.bluetooth => _BluetoothPage(
        store: _s.bluetooth,
        onBack: () => _show(QuickSettingsPage.main),
        onSettings: () =>
            _openSettings(const SettingsRoute(category: 'bluetooth')),
      ),
      QuickSettingsPage.output => _DevicesPage(
        store: _s.audio,
        direction: AudioDirection.output,
        onBack: () => _show(QuickSettingsPage.main),
        onSettings: () => _openSettings(SettingsRoute.audioOutput),
      ),
      QuickSettingsPage.input => _DevicesPage(
        store: _s.audio,
        direction: AudioDirection.input,
        onBack: () => _show(QuickSettingsPage.main),
        onSettings: () => _openSettings(SettingsRoute.audioInput),
      ),
    };
    return ShellTextRoot(
      style: TextStyle(
        color: theme.popupForeground,
        fontSize: ShellFontSizes.body,
      ),
      child: PopupCard(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: kQuickSettingsWidth - 24,
          child: Stack(
            children: [
              // Laid out always, painted and hit only on the main page: it is
              // what sizes the card, so a list page cannot change its height.
              Visibility(
                visible: sub == null,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: main,
              ),
              if (sub != null) Positioned.fill(child: sub),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The main page
// ---------------------------------------------------------------------------

class _MainPage extends StatelessWidget {
  const _MainPage({
    required this.services,
    required this.hasBacklight,
    required this.onShow,
    required this.onSettings,
    required this.onPowerMenu,
  });

  final QuickSettingsServices services;
  final bool hasBacklight;
  final ValueChanged<QuickSettingsPage> onShow;
  final ValueChanged<SettingsRoute> onSettings;
  final VoidCallback onPowerMenu;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _WifiTile(
                store: services.wifi,
                network: services.network,
                onMore: () => onShow(QuickSettingsPage.wifi),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BluetoothTile(
                store: services.bluetooth,
                onMore: () => onShow(QuickSettingsPage.bluetooth),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _PowerModeSection(
          store: services.power,
          onSettings: () => onSettings(SettingsRoute.power),
        ),
        const SizedBox(height: 14),
        _AudioSection(
          store: services.audio,
          direction: AudioDirection.output,
          onDevices: () => onShow(QuickSettingsPage.output),
          onSettings: () => onSettings(SettingsRoute.audioOutput),
        ),
        const SizedBox(height: 10),
        _AudioSection(
          store: services.audio,
          direction: AudioDirection.input,
          onDevices: () => onShow(QuickSettingsPage.input),
          onSettings: () => onSettings(SettingsRoute.audioInput),
        ),
        if (hasBacklight) ...[
          const SizedBox(height: 10),
          _BrightnessSection(
            store: services.backlight,
            onSettings: () =>
                onSettings(const SettingsRoute(category: 'display')),
          ),
        ],
        const SizedBox(height: 12),
        Container(height: 1, color: theme.divider),
        const SizedBox(height: 8),
        Row(
          children: [
            _FooterButton(
              glyph: ShellGlyph.settings,
              onTap: () =>
                  onSettings(const SettingsRoute.tab(OverviewTab.settings)),
            ),
            const Spacer(),
            _FooterButton(glyph: ShellGlyph.power, onTap: onPowerMenu),
          ],
        ),
      ],
    );
  }
}

// --- switch tiles ----------------------------------------------------------

/// A switch with a way through to its list: the body flips it, the chevron
/// opens the page. Two targets side by side, each opaque over its own box.
class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.busy,
    required this.enabled,
    required this.onToggle,
    required this.onMore,
    this.error = false,
    bool? dimmed,
  }) : dimmed = dimmed ?? !enabled;

  final ShellGlyph glyph;
  final String title;
  final String subtitle;
  final bool on;
  final bool busy;
  final bool enabled;
  final bool error;

  /// Whether the glyph and title are drawn muted; by default, whenever the
  /// switch is [enabled] no more.
  final bool dimmed;
  final VoidCallback onToggle;
  final VoidCallback onMore;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final fg = on ? kOnAccent : theme.popupForeground;
    final sub = error
        ? kErrorColor
        : (on ? kOnAccent.withValues(alpha: 0.8) : theme.muted);
    return SizedBox(
      height: height,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: on ? theme.accent : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: HoverRegion(
                  enabled: enabled && !busy,
                  onTap: onToggle,
                  builder: (context, hovered) => Container(
                    color: hovered && enabled && !busy
                        ? theme.surfaceHover
                        : const Color(0x00000000),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: busy
                              ? LoadingIndicator(size: 14, color: fg)
                              : ShellIcon(
                                  glyph,
                                  size: ShellFontSizes.label,
                                  color: dimmed ? theme.muted : fg,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: dimmed ? theme.muted : fg,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: sub,
                                  fontSize: ShellFontSizes.caption,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              HoverRegion(
                onTap: onMore,
                builder: (context, hovered) => Container(
                  width: 30,
                  color: hovered ? theme.surfaceHover : const Color(0x00000000),
                  alignment: Alignment.center,
                  child: ShellIcon(
                    ShellGlyph.chevronRight,
                    size: ShellFontSizes.caption,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the Wi-Fi tile's second line says.
///
/// While the connection is wired the tile is the Ethernet tile instead (see
/// [networkTileIsEthernet]), and this line says so before it says what the
/// Wi-Fi radio is doing — the switch is still the radio's — because "Not
/// connected" over a working cable reads as being offline.
@visibleForTesting
String wifiTileSubtitle({
  required WifiStatus status,
  required WifiRadio radio,
  required bool toggling,
  required NetworkInfo connection,
}) {
  if (connection.type == NetworkType.ethernet) {
    if (status != WifiStatus.ready || !radio.hasDevice) return 'Connected';
    if (toggling) {
      return radio.enabled ? 'Turning Wi-Fi off…' : 'Turning Wi-Fi on…';
    }
    if (!radio.hardwareEnabled || !radio.enabled) {
      return 'Connected · Wi-Fi off';
    }
    return 'Connected · Wi-Fi on';
  }
  if (status == WifiStatus.unavailable) return 'Unavailable';
  if (status != WifiStatus.ready) return '…';
  if (!radio.hasDevice) return 'No Wi-Fi device';
  if (toggling) return radio.enabled ? 'Turning off…' : 'Turning on…';
  if (!radio.hardwareEnabled) return 'Off (hardware switch)';
  if (!radio.enabled) return 'Off';
  if (connection.type == NetworkType.wifi) return connection.name;
  return 'Not connected';
}

/// Whether the network tile shows the wired connection rather than Wi-Fi:
/// whenever NetworkManager's primary connection is Ethernet.
@visibleForTesting
bool networkTileIsEthernet(NetworkInfo connection) =>
    connection.type == NetworkType.ethernet;

class _WifiTile extends StatelessWidget {
  const _WifiTile({
    required this.store,
    required this.network,
    required this.onMore,
  });

  final WifiStore store;
  final NetworkStatusStore network;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, network]),
      builder: (context, _) {
        final radio = store.radio;
        final ready = store.status == WifiStatus.ready;
        final wired = networkTileIsEthernet(network.info);
        final canToggle = ready && radio.hasDevice && radio.hardwareEnabled;
        return _ToggleTile(
          glyph: wired ? ShellGlyph.ethernet : ShellGlyph.wifi,
          title: wired ? 'Ethernet' : 'Wi-Fi',
          subtitle: store.error.isNotEmpty && ready
              ? store.error
              : wifiTileSubtitle(
                  status: store.status,
                  radio: radio,
                  toggling: store.toggling,
                  connection: network.info,
                ),
          error: store.error.isNotEmpty,
          on: ready && radio.enabled && radio.hardwareEnabled,
          busy: store.toggling,
          enabled: canToggle,
          // A working cable is never drawn as a dead tile, even on a machine
          // with no Wi-Fi to switch.
          dimmed: !canToggle && !wired,
          onToggle: () => store.setEnabled(!radio.enabled),
          onMore: onMore,
        );
      },
    );
  }
}

/// What the Bluetooth tile's second line says.
@visibleForTesting
String bluetoothTileSubtitle(BluetoothStore store) {
  if (store.status == BluetoothStatus.unavailable) return 'Unavailable';
  if (store.status != BluetoothStatus.ready) return '…';
  if (!store.hasAdapter) return 'No adapter';
  if (store.toggling) return store.powered ? 'Turning off…' : 'Turning on…';
  if (!store.powered) return 'Off';
  final connected = store.paired.where((d) => d.connected).toList();
  if (connected.isEmpty) return 'On';
  if (connected.length == 1) return connected.single.name;
  return '${connected.first.name} +${connected.length - 1}';
}

class _BluetoothTile extends StatelessWidget {
  const _BluetoothTile({required this.store, required this.onMore});

  final BluetoothStore store;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final ready = store.status == BluetoothStatus.ready;
        return _ToggleTile(
          glyph: ShellGlyph.bluetooth,
          title: 'Bluetooth',
          subtitle: store.error.isNotEmpty && ready
              ? store.error
              : bluetoothTileSubtitle(store),
          error: store.error.isNotEmpty,
          on: ready && store.powered,
          busy: store.toggling,
          enabled: ready && store.hasAdapter,
          onToggle: () => store.setPowered(!store.powered),
          onMore: onMore,
        );
      },
    );
  }
}

// --- section chrome --------------------------------------------------------

/// A section's first line: what it is, what it is set to, and its way through
/// to Settings. One fixed height in every state.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.onSettings,
    this.detail,
    this.detailIsError = false,
    this.onDetail,
    this.action,
  });

  final String title;
  final String? detail;
  final bool detailIsError;

  /// Makes [detail] a link, with a chevron — the device name, which opens the
  /// list of devices.
  final VoidCallback? onDetail;

  /// A text action before the gear — a Retry.
  final Widget? action;
  final VoidCallback onSettings;

  static const double height = 22;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final detail = this.detail;
    final detailStyle = TextStyle(
      fontSize: ShellFontSizes.caption,
      color: detailIsError ? kErrorColor : theme.muted,
    );
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontWeight: FontWeight.w700,
              color: theme.popupForeground,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: onDetail == null
                  ? Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: detailStyle,
                    )
                  : HoverRegion(
                      onTap: onDetail,
                      builder: (context, hovered) => Container(
                        height: height,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: hovered
                              ? theme.surfaceHover
                              : const Color(0x00000000),
                          borderRadius: BorderRadius.circular(
                            ShellRadii.control,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: detailStyle.copyWith(
                                  color: hovered
                                      ? theme.popupForeground
                                      : detailStyle.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ShellIcon(
                              ShellGlyph.chevronRight,
                              size: 9,
                              color: theme.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
          const Spacer(),
          ?action,
          _IconAction(glyph: ShellGlyph.settings, onTap: onSettings),
        ],
      ),
    );
  }
}

/// A small square icon button: the way through to a page of Settings.
class _IconAction extends StatelessWidget {
  const _IconAction({required this.glyph, required this.onTap});

  final ShellGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: ShellSizes.minTapTarget,
        height: ShellSizes.minTapTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : const Color(0x00000000),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: ShellIcon(
          glyph,
          size: ShellFontSizes.secondary,
          color: hovered ? theme.accentText : theme.muted,
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        height: ShellSizes.minTapTarget,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : const Color(0x00000000),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            color: theme.accentText,
          ),
        ),
      ),
    );
  }
}

/// A footer action: a glyph and a label, or — with no [label] — a square
/// icon of the same height.
class _FooterButton extends StatelessWidget {
  const _FooterButton({required this.glyph, required this.onTap, this.label});

  final ShellGlyph glyph;
  final String? label;
  final VoidCallback onTap;

  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final label = this.label;
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) {
        final icon = ShellIcon(
          glyph,
          size: ShellFontSizes.secondary,
          color: hovered ? theme.accentText : theme.popupForeground,
        );
        return Container(
          height: height,
          width: label == null ? height : null,
          alignment: label == null ? Alignment.center : null,
          padding: label == null
              ? null
              : const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(ShellRadii.control),
          ),
          child: label == null
              ? icon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

// --- power mode ------------------------------------------------------------

class _PowerModeSection extends StatelessWidget {
  const _PowerModeSection({required this.store, required this.onSettings});

  final PowerProfileStore store;
  final VoidCallback onSettings;

  static const List<String> _fallback = [
    PowerProfileId.powerSaver,
    PowerProfileId.balanced,
    PowerProfileId.performance,
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = ThemeScope.of(context);
        final state = store.state;
        final unavailable =
            store.status == PowerProfilesStatus.unavailable && state == null;
        final ready = state != null;
        final profiles = state == null || state.profiles.isEmpty
            ? _fallback
            : [for (final p in state.profiles) p.profile];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Power mode',
              detail: store.error.isNotEmpty && !unavailable
                  ? store.error
                  : null,
              detailIsError: true,
              action: unavailable || store.error.isNotEmpty
                  ? _TextAction(label: 'Retry', onTap: store.retry)
                  : null,
              onSettings: onSettings,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: unavailable
                  ? Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: theme.controlSurface,
                        borderRadius: BorderRadius.circular(ShellRadii.card),
                      ),
                      child: Text(
                        'Power modes need power-profiles-daemon.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          color: theme.muted,
                        ),
                      ),
                    )
                  : Row(
                      spacing: 6,
                      children: [
                        for (final id in profiles)
                          Expanded(
                            child: _ModeChip(
                              label: powerProfileLabel(id),
                              selected: ready && state.active == id,
                              pending: store.pendingProfile == id,
                              enabled: ready && store.pendingProfile == null,
                              onTap: () => store.setProfile(id),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.pending,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool pending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final fg = selected
        ? kOnAccent
        : (enabled ? theme.popupForeground : theme.muted);
    return HoverRegion(
      enabled: enabled && !selected,
      onTap: onTap,
      builder: (context, hovered) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.accent
              : (hovered && enabled
                    ? theme.surfaceHover
                    : theme.controlSurface),
          borderRadius: BorderRadius.circular(ShellRadii.card),
        ),
        child: pending
            ? LoadingIndicator(size: 12, color: fg)
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: ShellFontSizes.secondary, color: fg),
              ),
      ),
    );
  }
}

// --- levels ----------------------------------------------------------------

/// An icon button, the slider and the percentage: one level's row. Holds the
/// value under a drag locally, so the thumb follows the pointer rather than
/// the store's last echo; the write is on release, as in every level popup.
class _LevelRow extends StatefulWidget {
  const _LevelRow({
    required this.glyph,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.dimmed = false,
    this.label,
    this.onGlyphTap,
  });

  final ShellGlyph glyph;
  final double value;
  final bool enabled;

  /// Drawn in the muted colour — a muted device, whose slider stays usable to
  /// set the level it comes back at.
  final bool dimmed;

  /// Replaces the percentage — `Muted`.
  final String? label;
  final ValueChanged<double> onChanged;
  final VoidCallback? onGlyphTap;

  static const double height = 28;

  @override
  State<_LevelRow> createState() => _LevelRowState();
}

class _LevelRowState extends State<_LevelRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final value = _dragging ?? widget.value;
    final glyphColor = widget.dimmed || !widget.enabled
        ? theme.muted
        : theme.popupForeground;
    final icon = widget.onGlyphTap == null
        ? SizedBox.square(
            dimension: ShellSizes.minTapTarget,
            child: Center(
              child: ShellIcon(
                widget.glyph,
                size: ShellFontSizes.label,
                color: glyphColor,
              ),
            ),
          )
        : HoverRegion(
            enabled: widget.enabled,
            onTap: widget.onGlyphTap,
            builder: (context, hovered) => Container(
              width: ShellSizes.minTapTarget,
              height: ShellSizes.minTapTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered && widget.enabled
                    ? theme.surfaceHover
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(ShellRadii.control),
              ),
              child: ShellIcon(
                widget.glyph,
                size: ShellFontSizes.label,
                color: hovered && widget.enabled
                    ? theme.accentText
                    : glyphColor,
              ),
            ),
          );
    return SizedBox(
      height: _LevelRow.height,
      child: RepaintBoundary(
        child: Row(
          children: [
            icon,
            const SizedBox(width: 8),
            Expanded(
              child: LevelSlider(
                value: value,
                enabled: widget.enabled,
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: (v) {
                  setState(() => _dragging = null);
                  widget.onChanged(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                widget.label ?? '${(value * 100).round()}%',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: widget.enabled ? theme.popupForeground : theme.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ShellGlyph _outputGlyph(AudioDevice? device) {
  if (device == null || device.muted) return ShellGlyph.volumeMuted;
  if (device.volume <= 0.0) return ShellGlyph.volumeOff;
  if (device.volume <= 0.5) return ShellGlyph.volumeLow;
  return ShellGlyph.volumeHigh;
}

class _AudioSection extends StatelessWidget {
  const _AudioSection({
    required this.store,
    required this.direction,
    required this.onDevices,
    required this.onSettings,
  });

  final AudioDevicesStore store;
  final AudioDirection direction;
  final VoidCallback onDevices;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final output = direction == AudioDirection.output;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final device = store.current(direction);
        final unavailable = store.status == AudioDevicesStatus.unavailable;
        final loading =
            store.status == AudioDevicesStatus.loading ||
            store.status == AudioDevicesStatus.idle;
        final String detail;
        if (unavailable) {
          detail = 'Sound server unavailable';
        } else if (loading && device == null) {
          detail = '…';
        } else if (device == null) {
          detail = output ? 'No output device' : 'No microphone';
        } else {
          detail = device.label;
        }
        final muted = device?.muted ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: output ? 'Output' : 'Input',
              detail: detail,
              detailIsError: unavailable,
              onDetail: unavailable || loading ? null : onDevices,
              action: unavailable
                  ? _TextAction(label: 'Retry', onTap: store.retry)
                  : null,
              onSettings: onSettings,
            ),
            const SizedBox(height: 2),
            _LevelRow(
              glyph: output
                  ? _outputGlyph(device)
                  : (muted
                        ? ShellGlyph.microphoneSlash
                        : ShellGlyph.microphone),
              value: device?.volume ?? 0.0,
              enabled: device != null,
              dimmed: muted,
              label: muted ? 'Muted' : null,
              onGlyphTap: () => store.setMuted(direction, !muted),
              onChanged: (v) => store.setVolume(direction, v),
            ),
          ],
        );
      },
    );
  }
}

class _BrightnessSection extends StatelessWidget {
  const _BrightnessSection({required this.store, required this.onSettings});

  final BacklightStore store;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final level = store.level;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Brightness',
              detail: store.error ?? (level == null ? 'No backlight' : null),
              detailIsError: store.error != null,
              onSettings: onSettings,
            ),
            const SizedBox(height: 2),
            _LevelRow(
              glyph: ShellGlyph.sun,
              value: level ?? 0.0,
              enabled: level != null,
              onChanged: store.setLevel,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// List pages
// ---------------------------------------------------------------------------

/// A list page's frame: back, title, the way to Settings, the list, and a
/// line under it naming what the list cannot do here.
class _ListPage extends StatelessWidget {
  const _ListPage({
    required this.title,
    required this.onBack,
    required this.onSettings,
    required this.settingsLabel,
    required this.body,
    this.headerAction,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final String settingsLabel;
  final Widget body;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              _IconAction(glyph: ShellGlyph.chevronLeft, onTap: onBack),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.label,
                    fontWeight: FontWeight.w600,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              ?headerAction,
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: theme.divider),
        Expanded(child: body),
        Container(height: 1, color: theme.divider),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _FooterButton(
            glyph: ShellGlyph.settings,
            label: settingsLabel,
            onTap: onSettings,
          ),
        ),
      ],
    );
  }
}

/// One row of a list page: a glyph, a name, a second line, and a trailing
/// state. Tappable or not, at one height.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.glyph,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.busy = false,
  });

  final ShellGlyph glyph;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool busy;
  final Widget? trailing;
  final VoidCallback? onTap;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final subtitle = this.subtitle;
    return HoverRegion(
      enabled: onTap != null,
      onTap: onTap,
      builder: (context, hovered) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovered && onTap != null
              ? theme.surfaceHover
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: ShellIcon(
                glyph,
                size: ShellFontSizes.secondary,
                color: selected ? theme.accentText : theme.popupForeground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? theme.accentText
                          : theme.popupForeground,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        color: theme.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (busy)
              const LoadingIndicator(size: 12)
            else if (selected)
              ShellIcon(
                ShellGlyph.check,
                size: ShellFontSizes.secondary,
                color: theme.accentText,
              )
            else
              ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The text in the middle of an empty or failed list.
class _ListMessage extends StatelessWidget {
  const _ListMessage(this.message, {this.error = false, this.action});

  final String message;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: error ? kErrorColor : theme.muted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 6), action!],
          ],
        ),
      ),
    );
  }
}

/// A fixed-extent list of [count] rows, scrolled when it does not fit.
Widget _rows(int count, IndexedWidgetBuilder builder) => ListView.builder(
  padding: const EdgeInsets.symmetric(vertical: 4),
  itemExtent: _ListRow.height,
  // A page is a few hundred pixels: one screen of rows either side is plenty.
  scrollCacheExtent: const ScrollCacheExtent.pixels(200),
  itemCount: count,
  itemBuilder: builder,
);

/// Where a network row sends a tap: joined here, or to Settings for a
/// password. Null for the network already joined.
@visibleForTesting
enum WifiRowAction { none, join, settings }

@visibleForTesting
WifiRowAction wifiRowAction(AvailableNetwork network) {
  if (network.isConnected) return WifiRowAction.none;
  return wifiJoinsInPlace(network)
      ? WifiRowAction.join
      : WifiRowAction.settings;
}

class _WifiPage extends StatelessWidget {
  const _WifiPage({
    required this.store,
    required this.network,
    required this.onBack,
    required this.onSettings,
  });

  final WifiStore store;
  final NetworkStatusStore network;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = ThemeScope.of(context);
        final radio = store.radio;
        final networks = store.networks;
        final Widget body;
        if (store.status == WifiStatus.unavailable) {
          body = _ListMessage(
            store.error,
            error: true,
            action: _TextAction(label: 'Retry', onTap: store.retry),
          );
        } else if (!radio.hasDevice) {
          body = const _ListMessage('This machine has no Wi-Fi device.');
        } else if (!radio.enabled || !radio.hardwareEnabled) {
          body = _ListMessage(
            radio.hardwareEnabled
                ? 'Wi-Fi is off.'
                : 'Wi-Fi is off at the hardware switch.',
          );
        } else if (networks == null) {
          body = store.scanError.isNotEmpty
              ? _ListMessage(
                  store.scanError,
                  error: true,
                  action: _TextAction(label: 'Retry', onTap: store.scan),
                )
              : const Center(child: LoadingIndicator(size: 18));
        } else if (networks.isEmpty) {
          body = const _ListMessage('No networks in range.');
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (store.connectError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    store.connectError,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: kErrorColor,
                    ),
                  ),
                ),
              Expanded(
                child: _rows(networks.length, (context, i) {
                  final n = networks[i];
                  final action = wifiRowAction(n);
                  return _ListRow(
                    glyph: ShellGlyph.wifi,
                    title: n.name,
                    subtitle: [
                      '${n.signal}%',
                      if (n.secured) 'secured',
                      if (n.savedConnectionPath != null && !n.isConnected)
                        'saved',
                      if (action == WifiRowAction.settings)
                        'password in Settings',
                    ].join(' · '),
                    selected: n.isConnected,
                    busy: store.connecting == n.name,
                    trailing: n.secured
                        ? ShellIcon(
                            ShellGlyph.lock,
                            size: ShellFontSizes.caption,
                            color: theme.muted,
                          )
                        : null,
                    onTap: switch (action) {
                      WifiRowAction.none => null,
                      WifiRowAction.join =>
                        store.connecting == null
                            ? () => store.connect(n)
                            : null,
                      WifiRowAction.settings => onSettings,
                    },
                  );
                }),
              ),
            ],
          );
        }
        final canScan =
            radio.enabled && radio.hardwareEnabled && radio.hasDevice;
        return _ListPage(
          title: 'Wi-Fi',
          onBack: onBack,
          onSettings: onSettings,
          settingsLabel: 'Network settings…',
          headerAction: !canScan
              ? null
              : store.scanning
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: LoadingIndicator(size: 12),
                )
              : _IconAction(glyph: ShellGlyph.refresh, onTap: store.scan),
          body: body,
        );
      },
    );
  }
}

class _BluetoothPage extends StatelessWidget {
  const _BluetoothPage({
    required this.store,
    required this.onBack,
    required this.onSettings,
  });

  final BluetoothStore store;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final Widget body;
        if (store.status == BluetoothStatus.unavailable) {
          body = _ListMessage(
            store.error,
            error: true,
            action: _TextAction(label: 'Retry', onTap: store.retry),
          );
        } else if (store.status != BluetoothStatus.ready) {
          body = const Center(child: LoadingIndicator(size: 18));
        } else if (!store.hasAdapter) {
          body = const _ListMessage('This machine has no Bluetooth adapter.');
        } else if (!store.powered) {
          body = const _ListMessage('Bluetooth is off.');
        } else if (store.paired.isEmpty) {
          body = const _ListMessage(
            'No paired devices. Pair one in Bluetooth settings.',
          );
        } else {
          final devices = store.paired;
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (store.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    store.error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: kErrorColor,
                    ),
                  ),
                ),
              Expanded(
                child: _rows(devices.length, (context, i) {
                  final BluetoothDevice d = devices[i];
                  final busy = store.busyAddress == d.address;
                  return _ListRow(
                    glyph: ShellGlyph.bluetooth,
                    title: d.name,
                    subtitle: busy
                        ? (d.connected ? 'Disconnecting…' : 'Connecting…')
                        : (d.connected
                              ? 'Connected · tap to disconnect'
                              : 'Tap to connect'),
                    selected: d.connected,
                    busy: busy,
                    onTap: store.busyAddress == null
                        ? () => store.toggleConnection(d)
                        : null,
                  );
                }),
              ),
            ],
          );
        }
        return _ListPage(
          title: 'Bluetooth',
          onBack: onBack,
          onSettings: onSettings,
          settingsLabel: 'Bluetooth settings…',
          body: body,
        );
      },
    );
  }
}

class _DevicesPage extends StatelessWidget {
  const _DevicesPage({
    required this.store,
    required this.direction,
    required this.onBack,
    required this.onSettings,
  });

  final AudioDevicesStore store;
  final AudioDirection direction;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final output = direction == AudioDirection.output;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final devices = store.devices(direction);
        final selected = store.defaultName(direction);
        final Widget body;
        if (store.status == AudioDevicesStatus.unavailable) {
          body = _ListMessage(
            store.error,
            error: true,
            action: _TextAction(label: 'Retry', onTap: store.retry),
          );
        } else if (devices.isEmpty) {
          body = _ListMessage(
            output ? 'No output devices.' : 'No microphones.',
          );
        } else {
          body = _rows(devices.length, (context, i) {
            final d = devices[i];
            return _ListRow(
              glyph: output ? ShellGlyph.volumeHigh : ShellGlyph.microphone,
              title: d.label,
              subtitle: d.muted ? 'Muted' : '${(d.volume * 100).round()}%',
              selected: d.name == selected,
              onTap: d.name == selected
                  ? null
                  : () => store.setDefault(direction, d.name),
            );
          });
        }
        return _ListPage(
          title: output ? 'Output device' : 'Input device',
          onBack: onBack,
          onSettings: onSettings,
          settingsLabel: output
              ? 'Sound output settings…'
              : 'Microphone settings…',
          body: body,
        );
      },
    );
  }
}
