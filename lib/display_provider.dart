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
    // A global re-advertised without a preceding remove replaces its entry
    // rather than joining it: the stale [WaylandOutput] would otherwise stay
    // *ahead* of its replacement in [outputs], keeping its old name and
    // geometry where every by-order read would find it first.
    final previous = _byGlobal[global];
    if (previous != null) outputs.remove(previous);
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
/// The connector name is tried first and is the answer in every ordinary case:
/// GDK's connector and `wl_output.name` are the same string, and unlike geometry
/// it survives a display being repositioned. That matters because [MonitorInfo]
/// is a *snapshot* — the position in it is whatever GDK reported when the surface
/// was created, while an output's `x`/`y` are updated on every
/// `wl_output.geometry`. Matching on the pair meant that after a reposition *no*
/// panel matched and every one took the fallback, so every bar showed one
/// monitor's workspaces. The make/model/position tuple stays as the second pass,
/// for a GDK build that reports no connector.
///
/// [enumerating] is whether [ShellService.displays] is still loading, and it gates
/// the *fallback only*: an output is tracked as soon as its global is advertised
/// but carries no name until its `done`, so mid-enumeration `outputs.first` is
/// whichever arrived first.
///
/// The fallback is taken **only when there is exactly one output** — with several,
/// guessing hands every unmatched panel the same one, which is the failure this
/// exists to avoid.
WaylandOutput? resolveOutput(
  MonitorInfo monitor,
  List<WaylandOutput> outputs, {
  required bool enumerating,
}) {
  if (monitor.connector.isNotEmpty) {
    for (final output in outputs) {
      // An output that has not delivered its `name` yet holds '', which matches
      // no connector — so this cannot fire mid-enumeration.
      if (output.name == monitor.connector) return output;
    }
  }
  for (final output in outputs) {
    if (output.make == monitor.manufacturer &&
        output.model == monitor.model &&
        output.x == monitor.position.dx.toInt() &&
        output.y == monitor.position.dy.toInt()) {
      return output;
    }
  }
  if (outputs.length != 1 || enumerating) return null;
  return outputs.first;
}

/// Provides the live [WaylandOutput] for one panel's monitor.
///
/// **This is the only thing in the shell that should construct a
/// [DisplayScope]** — the [ThemeProvider] rule, for its reason. An
/// `InheritedWidget` cannot span FlutterViews, so every panel window is given its
/// output separately; resolving it in the root's own `build` instead meant the
/// root rebuilt *every* view it owns whenever any output changed.
///
/// Only [OutputTracker] is listened to. Whether enumeration has finished comes
/// from the [ShellServicesScope] the window chrome installs, read from this
/// builder's own context — a `Listenable.merge` of the two would have to be built
/// in `build`, and `_MergingListenable` defines no `==`, so [ListenableBuilder]
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
