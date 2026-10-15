// The bar's clipboard button: opens the clipboard history panel against the
// configured edge of the output it was clicked on, or closes it again.
//
// Like `todo.dart` it creates no window of its own — it pokes
// [ClipboardPanelController] and the root owns the panel, which is what keeps a
// shell with four bars from docking four panels. What it does own is a lease on
// the history: the watcher runs while some bar carries this button, which is
// what "the clipboard module is enabled" means, and never otherwise.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/bar_button.dart';
import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/clipboard/clipboard_panel_controller.dart';
import 'package:moonswing/clipboard/clipboard_store.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The bar's clipboard icon.
class ClipboardButton extends StatefulWidget {
  const ClipboardButton({super.key, this.controller, this.store});

  /// Defaults to the singletons the root listens to; a widget test passes its
  /// own.
  final ClipboardPanelController? controller;
  final ClipboardHistoryStore? store;

  @override
  State<ClipboardButton> createState() => _ClipboardButtonState();
}

class _ClipboardButtonState extends State<ClipboardButton> {
  late final ClipboardHistoryStore _store =
      widget.store ?? ClipboardHistoryStore.instance;

  ClipboardPanelController get _controller =>
      widget.controller ?? ClipboardPanelController.instance;

  @override
  void initState() {
    super.initState();
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.isOpen,
      builder: (context, open, child) => BarButton(
        // Pressed while the panel is up, on every bar: it is one panel.
        active: open,
        // Tap-*down*, for the reason `KeybindsButton` gives.
        onTapDown: (_) => _controller.toggle(
          // The connector, the root's key for this output's surfaces; null
          // while outputs are still being enumerated, and the compositor then
          // picks the focused output — where the click just happened.
          output: DisplayScope.of(context)?.name,
        ),
        child: child!,
      ),
      // The icon dims while the history is not being recorded, the button's
      // half of saying so; the panel says why.
      child: StoreSelector<bool>(
        listenable: _store,
        selector: () => _store.error == null,
        builder: (context, recording) => FaIcon(
          FontAwesomeIcons.clipboard,
          size: ShellFontSizes.label,
          color: recording ? theme.foreground : theme.muted,
        ),
      ),
    );
  }
}

final Module clipboardModule = Module.simple<ClipboardConfig>(
  configKey: 'clipboard',
  fromMap: (map) {
    final config = ClipboardConfig.fromMap(map);
    // The store, not the widget, owns the config: the root reads the side and
    // width when it creates the panel, which no bar button is an ancestor of.
    ClipboardHistoryStore.instance.configure(config);
    return config;
  },
  builder: (context, config) => const ClipboardButton(),
);
