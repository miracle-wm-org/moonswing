import 'package:flutter/foundation.dart';

import 'package:moonswing/request_controller.dart';

/// The seam between the bar's todo button and `_MoonswingRootState`, which owns
/// every window. [KeybindCheatsheetController]'s shape, plus the one thing the
/// cheat sheet does not need: which output the click came from.
///
/// The board opens on the display whose bar was clicked rather than wherever
/// the compositor's focus happens to be. It is a workspace the user is about to
/// spend time in, and it is asked for by pointing at one particular screen.
class TodoController extends SignalController {
  TodoController._();

  static final TodoController instance = TodoController._();

  @visibleForTesting
  factory TodoController.forTesting() => TodoController._();

  /// The connector name (`DP-1`) of the output the last [toggle] came from, or
  /// null when the caller did not know it yet. Read by the root on the notify.
  String? get output => _output;
  String? _output;

  /// Asks the shell to open the board on [output], or to close it if it is
  /// already up. The root decides which.
  void toggle({String? output}) {
    _output = output;
    signal();
  }
}
