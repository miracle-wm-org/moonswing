// A local stand-in for Flutter's `WindowManager`.
//
// The SDK widget is `@internal` and changed shape on master: it used to take a
// `child` and render it *plus* whatever windows had been registered into its
// `WindowRegistry` (via a `ViewAnchor` whenever a `View` was already ambient).
// It now takes `initialWindows` and renders only those, as a bare
// `ViewCollection` — so panel content nested inside it simply disappears.
//
// The shell needs the old behaviour: every panel is a layer-shell window whose
// tree hosts modules that open popups and further layer-shell windows at
// runtime, and those have to render as sibling views of the panel while the
// panel itself keeps drawing. This file is a port of the SDK's pre-rename
// implementation with its own registry scope, because Flutter's
// `_WindowRegistryScope` is private — nothing we write can satisfy
// `WindowRegistry.of`.
//
// The registry, its entries and the window widgets are still the SDK's; only
// the lookup and the child-rendering branch live here.

// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';

/// Hosts a [WindowRegistry] for one layer-shell window, rendering [child]
/// alongside every window registered into it.
///
/// Named for panels because they were the first users, but it is generic: the
/// background window wraps one too, so the desktop icon grid can open context
/// menus. Anything hosting a [PopupHost] or [LayerShellHost] needs one.
///
/// Descendants reach the registry with [registryOf] / [maybeRegistryOf] and
/// register a [WindowEntry] to open a window; unregistering closes it. See
/// `PopupHost` and `LayerShellHost` in `popup.dart`, which are the only two
/// callers.
class PanelWindowManager extends StatefulWidget {
  const PanelWindowManager({super.key, required this.child});

  /// The panel content. Rendered into the ambient [View] — the layer-shell
  /// window this manager sits inside — with any registered windows anchored
  /// beside it.
  final Widget child;

  /// The nearest enclosing [WindowRegistry], or null if there is none.
  static WindowRegistry? maybeRegistryOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_PanelWindowRegistryScope>()
        ?.registry;
  }

  /// The nearest enclosing [WindowRegistry].
  ///
  /// Throws if the caller is not inside a [PanelWindowManager].
  static WindowRegistry registryOf(BuildContext context) {
    final registry = maybeRegistryOf(context);
    assert(() {
      if (registry == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('No PanelWindowManager found in context.'),
          ErrorDescription(
            '${context.widget.runtimeType} widgets that open popups or '
            'layer-shell windows must be built inside a PanelWindowManager.',
          ),
          context.describeOwnershipChain(
              'The ownership chain for the affected widget is'),
        ]);
      }
      return true;
    }());
    return registry!;
  }

  @override
  State<PanelWindowManager> createState() => _PanelWindowManagerState();
}

class _PanelWindowManagerState extends State<PanelWindowManager> {
  final WindowRegistry _registry = WindowRegistry();

  @override
  Widget build(BuildContext context) {
    return _PanelWindowRegistryScope(
      registry: _registry,
      child: ListenableBuilder(
        listenable: _registry,
        builder: (BuildContext context, Widget? child) {
          final subViews = _registry.windows.map((entry) {
            return switch (entry.controller) {
              final DialogWindowController dialog => DialogWindow(
                  controller: dialog,
                  child: entry.builder(context),
                ),
              final WindowController regular => Window(
                  controller: regular,
                  child: entry.builder(context),
                ),
              final TooltipWindowController tooltip => TooltipWindow(
                  controller: tooltip,
                  child: entry.builder(context),
                ),
              final PopupWindowController popup => PopupWindow(
                  controller: popup,
                  child: entry.builder(context),
                ),
              final SatelliteWindowController satellite => SatelliteWindow(
                  controller: satellite,
                  child: entry.builder(context),
                ),
            };
          }).toList();

          // A ViewAnchor renders `child` into the ambient View and the anchored
          // views into their own. Without an ambient View there is nothing to
          // anchor to, so fall back to a plain collection — the same branch the
          // SDK took.
          if (View.maybeOf(context) == null) {
            return ViewCollection(views: subViews);
          }
          return ViewAnchor(
            view: subViews.isNotEmpty ? ViewCollection(views: subViews) : null,
            child: child!,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _PanelWindowRegistryScope extends InheritedWidget {
  const _PanelWindowRegistryScope({
    required this.registry,
    required super.child,
  });

  final WindowRegistry registry;

  @override
  bool updateShouldNotify(_PanelWindowRegistryScope oldWidget) =>
      registry != oldWidget.registry;
}
