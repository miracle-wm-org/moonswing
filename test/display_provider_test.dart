import 'dart:ffi' as ffi;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layer_shell/layer_shell.dart';
import 'package:wayland/wayland.dart';

import 'package:graceful_shell/display_provider.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_services.dart';

/// The regression test for the rule the panels' workspace lists depend on: a bar
/// learns which physical display it is on *after* it has painted, and it must
/// never be handed the wrong one in the meantime.
///
/// The content is deliberately held in a `const` child, so the only thing that
/// can update it is the [DisplayScope] above it changing.
void main() {
  late WaylandClient client;
  late OutputTracker outputs;
  late ShellServices services;
  var nextId = 2;

  setUp(() {
    client = WaylandClient();
    outputs = OutputTracker();
    services = ShellServices();
    nextId = 2;
  });

  tearDown(() {
    outputs.dispose();
    services.dispose();
  });

  /// An output as the compositor would have described it after its `done`.
  WaylandOutput output({
    required String name,
    required String make,
    required String model,
    int x = 0,
    int y = 0,
  }) =>
      WaylandOutput(client, nextId++)
        ..name = name
        ..make = make
        ..model = model
        ..x = x
        ..y = y;

  MonitorInfo monitor({
    String connector = 'DP-1',
    String manufacturer = 'Acme',
    String model = 'X1',
    Offset position = Offset.zero,
  }) =>
      MonitorInfo(
        connector: connector,
        model: model,
        manufacturer: manufacturer,
        gdkMonitor: ffi.nullptr,
        position: position,
      );

  Future<void> build(WidgetTester tester, MonitorInfo m) => tester.pumpWidget(
        ShellServicesScope(
          services: services,
          child: DisplayProvider(
            monitor: m,
            outputs: outputs,
            child: const _OutputName(),
          ),
        ),
      );

  String shown(WidgetTester tester) =>
      (tester.widget<SizedBox>(find.byType(SizedBox)).key as ValueKey<String>)
          .value;

  testWidgets('an exact match wins even while enumeration is in flight',
      (tester) async {
    // An exact make/model/position match is trustworthy at any point — it is
    // only the first-output fallback that has to wait.
    outputs.add(1, output(name: 'DP-1', make: 'Acme', model: 'X1'));
    await build(tester, monitor());

    expect(services.isLoading(ShellService.displays), isTrue);
    expect(shown(tester), 'DP-1');
  });

  testWidgets('the first-output fallback is refused while enumeration is in '
      'flight, and taken once it settles', (tester) async {
    // Nothing here matches the monitor, so only the fallback could answer.
    outputs.add(1, output(name: 'HDMI-A-1', make: 'Other', model: 'Z9'));
    await build(tester, monitor());

    // An output is tracked as soon as its global is advertised but carries no
    // name or geometry until its `done`, so mid-enumeration `outputs.first` is
    // simply whichever arrived first — the wrong display means the wrong
    // workspaces.
    expect(shown(tester), '<none>');

    services.skip(ShellService.displays);
    await tester.pump();
    expect(shown(tester), 'HDMI-A-1');
  });

  testWidgets('no outputs at all resolves to none, settled or not',
      (tester) async {
    services.skip(ShellService.displays);
    await build(tester, monitor());
    expect(shown(tester), '<none>');
  });

  testWidgets('a captured subtree re-resolves as outputs arrive and go',
      (tester) async {
    await build(tester, monitor(manufacturer: 'Acme', model: 'X1'));
    expect(shown(tester), '<none>');

    // An output is tracked as soon as its global is advertised, carrying
    // nothing but defaults — so it matches no monitor, and because enumeration
    // is still in flight the fallback cannot answer for it either. This is the
    // state the whole `enumerating` gate exists for.
    final added = WaylandOutput(client, nextId++);
    outputs.add(1, added);
    await tester.pump();
    expect(shown(tester), '<none>');

    // Its `done` delivers the properties, and `markChanged` is how the tracker
    // says so without the set itself having changed.
    added
      ..name = 'DP-1'
      ..make = 'Acme'
      ..model = 'X1'
      ..x = 0
      ..y = 0;
    outputs.markChanged();
    await tester.pump();
    expect(shown(tester), 'DP-1');

    // Every output has now reported, which is what settles the service.
    services.skip(ShellService.displays);
    await tester.pump();
    expect(shown(tester), 'DP-1');

    // Unplugged.
    outputs.remove(1);
    await tester.pump();
    expect(shown(tester), '<none>');
  });

  testWidgets('a monitor is matched on position, not just make and model',
      (tester) async {
    // The geometry pass, which is what answers for a GDK build that reports no
    // connector at all — hence the empty one here. With a connector present
    // that name is the answer, and this pair of identical panels is exactly the
    // case it would otherwise have to be told apart by position.
    services.skip(ShellService.displays);
    final left = output(name: 'DP-1', make: 'Acme', model: 'X1');
    final right = output(name: 'DP-2', make: 'Acme', model: 'X1', x: 1920);
    outputs.add(1, left);
    outputs.add(2, right);

    await build(
        tester, monitor(connector: '', position: const Offset(1920, 0)));
    expect(shown(tester), 'DP-2');
  });

  testWidgets('a repositioned display keeps its own output', (tester) async {
    // The regression this matcher exists for. `MonitorInfo` is a snapshot taken
    // when the panel's surface was created, so after the user swaps the displays
    // around its position is stale — while the outputs report their new geometry
    // immediately. Matching on position alone left *both* panels unmatched, and
    // both then took the same `outputs.first`.
    services.skip(ShellService.displays);
    final left = output(name: 'DP-1', make: 'Acme', model: 'X1');
    final right = output(name: 'DP-2', make: 'Acme', model: 'X1', x: 1920);
    outputs.add(1, left);
    outputs.add(2, right);

    await build(
        tester, monitor(connector: 'DP-2', position: const Offset(1920, 0)));
    expect(shown(tester), 'DP-2');

    // The displays swap sides. Nothing tells the shell's `MonitorInfo` about it.
    left.x = 1920;
    right.x = 0;
    outputs.markChanged();
    await tester.pump();
    expect(shown(tester), 'DP-2');

    // ...and the other panel is unmoved too, rather than joining it.
    await build(tester, monitor(connector: 'DP-1', position: Offset.zero));
    expect(shown(tester), 'DP-1');
  });

  testWidgets('the connector name beats another output matching on geometry',
      (tester) async {
    services.skip(ShellService.displays);
    // Two identical panels, and the stale position now describes the *other*
    // one — the swap above, seen from one panel.
    outputs.add(1, output(name: 'DP-1', make: 'Acme', model: 'X1', x: 1920));
    outputs.add(2, output(name: 'DP-2', make: 'Acme', model: 'X1'));

    await build(tester, monitor(connector: 'DP-1', position: Offset.zero));
    expect(shown(tester), 'DP-1');
  });

  testWidgets('the fallback is refused when there is more than one output',
      (tester) async {
    // With several displays an unmatched panel has no honest answer, and
    // handing every one of them `outputs.first` is what put one monitor's
    // workspaces on all the bars. The module renders its loader instead.
    services.skip(ShellService.displays);
    outputs.add(1, output(name: 'HDMI-A-1', make: 'Other', model: 'Z9'));
    outputs.add(
        2, output(name: 'HDMI-A-2', make: 'Other', model: 'Z9', x: 1920));

    await build(tester, monitor(connector: 'DP-9'));
    expect(shown(tester), '<none>');
  });

  group('resolveOutput', () {
    test('returns null for an empty set whether or not it is enumerating', () {
      final m = monitor();
      expect(resolveOutput(m, const [], enumerating: true), isNull);
      expect(resolveOutput(m, const [], enumerating: false), isNull);
    });
  });

  group('OutputTracker', () {
    test('a global re-advertised without a remove replaces its entry', () {
      final first = output(name: 'DP-1', make: 'Acme', model: 'X1');
      final second = output(name: 'DP-2', make: 'Acme', model: 'X1', x: 1920);
      outputs.add(1, first);
      outputs.add(1, second);

      // The stale one would otherwise sit *ahead* of its replacement, which is
      // where every by-order read finds it.
      expect(outputs.outputs, [second]);
    });
  });
}

/// Reads the output from the enclosing scope. `const`, so the only thing that
/// can update it is the [DisplayScope] above it changing.
class _OutputName extends StatelessWidget {
  const _OutputName();

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 1,
        key: ValueKey(DisplayScope.of(context)?.name ?? '<none>'),
      );
}
