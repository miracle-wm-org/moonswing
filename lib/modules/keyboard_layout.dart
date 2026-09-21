// The keyboard layout indicator: which input source is live, and a popup to
// change it.
//
// `sound_control.dart`'s `PopupHost` half over `battery.dart`'s lease half. All
// the mechanism is in `lib/keyboard/`; this file draws it.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/bar_button.dart';
import 'package:graceful_shell/config_reader.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/keyboard/keyboard_short_codes.dart';
import 'package:graceful_shell/keyboard/keyboard_store.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/module.dart';
import 'package:graceful_shell/overlay/settings_route.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_text_root.dart';
import 'package:graceful_shell/theme/theme_config.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// `[modules.keyboard_layout]`.
@immutable
class KeyboardLayoutConfig {
  const KeyboardLayoutConfig({
    this.hideWhenSingle = true,
    this.uppercase = false,
  });

  /// Hide the badge when there is only one input source to choose from.
  ///
  /// GNOME's behaviour, and the default. A setting rather than a hard-coded rule
  /// because a user who wants to see the layout on a single-source machine has
  /// nowhere else to look. It never hides a badge that has something to *report*.
  final bool hideWhenSingle;

  /// Draw the badge as `EN` rather than `en`.
  final bool uppercase;

  factory KeyboardLayoutConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const KeyboardLayoutConfig();
    return KeyboardLayoutConfig(
      hideWhenSingle: map.boolOr('hide_when_single', true),
      uppercase: map.boolOr('uppercase', false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeyboardLayoutConfig &&
      other.hideWhenSingle == hideWhenSingle &&
      other.uppercase == uppercase;

  @override
  int get hashCode => Object.hash(hideWhenSingle, uppercase);
}

class KeyboardLayout extends StatefulWidget {
  const KeyboardLayout({
    super.key,
    this.config = const KeyboardLayoutConfig(),
    KeyboardStore? store,
  }) : _store = store;

  final KeyboardLayoutConfig config;

  /// Injected by widget tests, so nothing here touches the system bus.
  final KeyboardStore? _store;

  @override
  State<KeyboardLayout> createState() => _KeyboardLayoutState();
}

class _KeyboardLayoutState extends State<KeyboardLayout>
    with PopupHost<KeyboardLayout> {
  late final KeyboardStore _store = widget._store ?? KeyboardStore.instance;

  @override
  void initState() {
    super.initState();
    _store.acquire();
  }

  @override
  void dispose() {
    closePopup();
    _store.release();
    super.dispose();
  }

  void _togglePopup(BuildContext context) {
    if (isPopupOpen) {
      closePopup();
      return;
    }
    openBarPopup(
      context,
      preferredConstraints: const BoxConstraints(
        minWidth: 230,
        maxWidth: 300,
        maxHeight: 360,
      ),
      // The store, not a snapshot: locale1 can move while the popup is up, and
      // a popup's content is built once into a `WindowEntry` builder, so the
      // parent never rebuilds it. `WeatherForecastPopup`'s rule.
      child: ThemeProvider(
        child: KeyboardLayoutPopup(store: _store, onClose: closePopup),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final broken = _store.error.isNotEmpty;
        final unlisted = _store.unlistedActive != null;
        // Hidden only when there is genuinely nothing to say. A module with a
        // failure to report may not hide itself — `WeatherStore.error`'s rule —
        // and a machine sitting in a layout the user never configured is exactly
        // what they need to see.
        if (_store.sources.length < 2 &&
            widget.config.hideWhenSingle &&
            !broken &&
            !unlisted) {
          return const SizedBox.shrink();
        }

        final theme = ThemeScope.of(context);
        var code = _store.activeShortCode;
        if (code.isEmpty) code = '--';
        if (widget.config.uppercase) code = code.toUpperCase();

        return BarButton(
          active: isPopupOpen,
          // Tap-*down*, like every other popup toggle in the shell:
          // `PopupDismissArea`'s ancestor `Listener` fires before any
          // descendant recognizer, and the coordinator's reopen guard is armed
          // and consumed inside that one pointer-down.
          onTapDown: (_) => _togglePopup(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: TextStyle(
                  fontSize: ShellFontSizes.body,
                  color: broken ? kErrorColor : theme.foreground,
                ),
              ),
              if (broken) ...[
                const SizedBox(width: 4),
                const FaIcon(
                  FontAwesomeIcons.triangleExclamation,
                  size: ShellFontSizes.caption,
                  color: kErrorColor,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The card the bar module opens.
///
/// Public because in its one real home it is inside a layer-shell window no
/// widget test can pump — `NotificationPanel`'s reason.
class KeyboardLayoutPopup extends StatelessWidget {
  const KeyboardLayoutPopup({super.key, required this.store, this.onClose});

  final KeyboardStore store;

  /// Called after the footer opens the settings overlay.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // `ShellTextRoot`, not a bare `Directionality`: a popup's child lays out
    // directly under its own FlutterView, nothing above it supplies one, and
    // `Directionality.of` is a null-assert rather than an assert — so the
    // window maps and the card comes up empty.
    return ShellTextRoot(
      style: TextStyle(
        color: theme.popupForeground,
        fontSize: ShellFontSizes.secondary,
      ),
      child: PopupCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => _buildBody(context, theme),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeConfig theme) {
    final busy = store.pending != null;
    final activeIndex = store.activeIndex;
    final unlisted = store.unlistedActive;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Above the list, not below it: with the write refused the list is
        // still the user's own and says nothing about why nothing happened.
        if (store.error.isNotEmpty) _KeyboardErrorStrip(store: store),
        if (store.sources.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Text(
              'No input sources yet.',
              style: TextStyle(
                color: theme.popupForeground.withValues(alpha: 0.6),
              ),
            ),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < store.sources.length; i++)
                    _SourceRow(
                      code: i < store.shortCodes.length
                          ? store.shortCodes[i]
                          : '',
                      label: store.describe(store.sources[i]),
                      active: i == activeIndex,
                      loading: store.pending == store.sources[i],
                      enabled: !busy,
                      onTap: () => store.activate(store.sources[i]),
                    ),
                ],
              ),
            ),
          ),
        if (unlisted != null) ...[
          _Divider(theme: theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
            child: Text(
              'Not in your list',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
            ),
          ),
          _SourceRow(
            code: shortCodeFor(unlisted.layout),
            label: store.describe(unlisted),
            active: true,
            loading: false,
            // Not tappable: it is already what the machine is applying, and
            // there is nothing to switch to.
            enabled: false,
            onTap: null,
          ),
        ],
        _Divider(theme: theme),
        HoverRegion(
          onTap: () {
            SettingsController.instance.open(SettingsRoute.keyboard);
            onClose?.call();
          },
          builder: (context, hovered) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: hovered ? theme.surfaceHover : null,
            child: Text(
              'Keyboard settings…',
              style: TextStyle(
                color: theme.popupForeground.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});

  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Container(height: 1, color: theme.divider),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.code,
    required this.label,
    required this.active,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final String code;
  final String label;
  final bool active;
  final bool loading;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      enabled: enabled && onTap != null,
      onTap: onTap,
      builder: (context, hovered) => Container(
        constraints: const BoxConstraints(minHeight: ShellSizes.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        color: active
            ? theme.surfacePressed
            : (hovered ? theme.surfaceHover : null),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                code,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  color: theme.accentText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.popupForeground),
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              const LoadingIndicator(size: 12)
            else if (active)
              FaIcon(
                FontAwesomeIcons.check,
                size: ShellFontSizes.caption,
                color: theme.accentText,
              )
            else
              const SizedBox(width: ShellFontSizes.caption),
          ],
        ),
      ),
    );
  }
}

/// The failure strip, `NotificationDaemonBanner`'s shape at popup scale.
class _KeyboardErrorStrip extends StatelessWidget {
  const _KeyboardErrorStrip({required this.store});

  final KeyboardStore store;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final busy = store.pending != null;
    return Container(
      color: kErrorColor.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: FaIcon(
                  FontAwesomeIcons.triangleExclamation,
                  size: 12,
                  color: kErrorColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Could not change the layout',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            store.error,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              height: 1.4,
              color: theme.popupForeground.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: busy
                ? const SizedBox(
                    height: ShellSizes.minTapTarget,
                    width: 64,
                    child: Center(
                      child: LoadingIndicator(size: 12, color: kErrorColor),
                    ),
                  )
                : HoverRegion(
                    onTap: () => store.retry(),
                    builder: (context, hovered) => Container(
                      width: 64,
                      height: ShellSizes.minTapTarget,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hovered
                            ? kErrorColor.withValues(alpha: 0.18)
                            : null,
                        border: Border.all(
                          color: kErrorColor.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(ShellRadii.control),
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          color: kErrorColor,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

final Module keyboardLayoutModule = Module.simple<KeyboardLayoutConfig>(
  configKey: 'keyboard_layout',
  fromMap: KeyboardLayoutConfig.fromMap,
  builder: (context, config) => KeyboardLayout(config: config),
);
