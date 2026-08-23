import 'package:flutter/widgets.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:wayland/wayland.dart';

import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_services.dart';

/// Live set of Wayland outputs, kept in sync with the compositor's `wl_output`
/// globals. Panels match against this to resolve which physical display they
/// render on. Notifies listeners when outputs are added, removed, or their
/// details (name / geometry) change, so the shell can re-match after a hotplug.
class OutputTracker extends ChangeNotifier {
  final List<WaylandOutput> outputs = [];
  final Map<int, WaylandOutput> _byGlobal = {};

  void add(int global, WaylandOutput output) {
    _byGlobal[global] = output;
    outputs.add(output);
    notifyListeners();
  }

  void remove(int global) {
    final output = _byGlobal.remove(global);
    if (output == null) return;
    outputs.remove(output);
    notifyListeners();
  }

  /// Signals that an existing output's properties changed (e.g. its `done`
  /// event delivered a new name or geometry) without the set itself changing.
  void markChanged() => notifyListeners();
}

/// Resolves the [WaylandOutput] backing [monitor], or null while the shell does
/// not (yet) know which one it is.
///
/// [enumerating] is whether [ShellService.displays] is still loading, and it
/// gates the *fallback only*. An exact make/model/position match is
/// trustworthy at any point; the fallback is not, because an output is tracked
/// as soon as its global is advertised but carries no name or geometry until
/// its `done` — so mid-enumeration `outputs.first` is simply whichever one
/// arrived first, and handing a bar the wrong display would show it another
/// monitor's workspaces. Until then it gets none, and the modules that need one
/// show a loader.
///
/// The fallback itself covers a monitor that GDK and Wayland describe
/// differently.
WaylandOutput? resolveOutput(
  MonitorInfo monitor,
  List<WaylandOutput> outputs, {
  required bool enumerating,
}) {
  for (final output in outputs) {
    if (output.make == monitor.manufacturer &&
        output.model == monitor.model &&
        output.x == monitor.position.dx.toInt() &&
        output.y == monitor.position.dy.toInt()) {
      return output;
    }
  }
  if (outputs.isEmpty || enumerating) return null;
  return outputs.first;
}

/// Provides the live [WaylandOutput] for one panel's monitor.
///
/// **This is the only thing in the shell that should construct a
/// [DisplayScope]** — the [ThemeProvider] rule, for the same reason. An
/// `InheritedWidget` cannot span FlutterViews, so every panel window has to be
/// given its output separately; doing that by resolving it in the root's own
/// `build` meant the root had to rebuild *every* view — every panel on every
/// monitor, the backgrounds, the OSD, the overlays — whenever any output
/// changed or finished reporting its properties.
///
/// Only [OutputTracker] is listened to. The other half of the answer — whether
/// enumeration has finished — comes from the [ShellServicesScope] the window
/// chrome already installs, read from this builder's own context. That is
/// deliberate: a `Listenable.merge` of the two would have to be built in
/// `build`, and `_MergingListenable` defines no `==`, so [ListenableBuilder]
/// would tear down and re-add its listener on every rebuild.
class DisplayProvider extends StatelessWidget {
  const DisplayProvider({
    super.key,
    required this.monitor,
    required this.outputs,
    required this.child,
  });

  final MonitorInfo monitor;
  final OutputTracker outputs;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: outputs,
        // `child` is passed through rather than rebuilt: descendants that need
        // the output depend on the DisplayScope above them, exactly as under
        // ThemeProvider, so rebuilding the subtree here would be pure waste.
        builder: (context, child) => DisplayScope(
          output: resolveOutput(
            monitor,
            outputs.outputs,
            enumerating:
                ShellServicesScope.isLoading(context, ShellService.displays),
          ),
          child: child!,
        ),
        child: child,
      );
}
