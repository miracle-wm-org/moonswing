import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between the bar's clipboard button and `_MoonswingRootState`, which
/// owns every window.
///
/// [NotificationPanelController]'s shape — a toggle, and an open flag the root
/// is the only writer of, so every button on every bar can draw itself pressed
/// while the panel is up — plus [TodoController]'s one addition: which output
/// the click came from, so the panel docks against the screen whose bar was
/// clicked.
class ClipboardPanelController extends SignalController {
  ClipboardPanelController._();

  static final ClipboardPanelController instance = ClipboardPanelController._();

  @visibleForTesting
  factory ClipboardPanelController.forTesting() => ClipboardPanelController._();

  final ValueNotifier<bool> _open = ValueNotifier(false);

  /// Whether the root currently has the panel up.
  ///
  /// Its own listenable, for [NotificationPanelController.isOpen]'s reason: the
  /// root listens to this controller for the toggle, and publishing the flag
  /// through the same notifier would bring the root's own write back in as a
  /// second toggle.
  ValueListenable<bool> get isOpen => _open;

  /// Root-only: set when the panel's window is created and cleared once it has
  /// been torn down.
  void setOpen(bool value) => _open.value = value;

  /// The connector name of the output the last [toggle] came from, or null
  /// when the caller did not know it yet.
  String? get output => _output;
  String? _output;

  /// Asks the shell to open the panel on [output], or to close it if it is
  /// already up. The root decides which.
  void toggle({String? output}) {
    _output = output;
    signal();
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }
}
