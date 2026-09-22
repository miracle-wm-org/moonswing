import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/live_config_provider.dart';
import 'package:moonswing/scopes.dart';

/// The regression test for what the live-config scope is *for*.
///
/// `ConfigStore` notifies on every keystroke anywhere in the settings UI, and
/// `ConfigStore.appConfig` mints a fresh [AppConfig] on every read. The shell
/// root used to answer each of those with `setState`, which rebuilt every view
/// it owns — every panel on every monitor, the backgrounds, the OSD, all five
/// overlays — to deliver a value at most a handful of widgets read.
///
/// Two things have to hold for that to stop: the value has to compare equal
/// when nothing moved (which is why the config classes carry `==` at all), and
/// the scope has to refuse to notify when it does. The content is held in a
/// `const` child, the way `theme_provider_test.dart` does, so the only thing
/// that can rebuild it is the scope above it.
void main() {
  setUp(() => _Probe.builds = 0);

  AppConfig config({int padding = 8, String theme = 'moonswing'}) => AppConfig(
        themeName: theme,
        panels: {
          'top': PanelConfig(
            name: 'top',
            paddingHorizontal: padding,
            layout: const LayoutConfig(left: ['clock']),
          ),
        },
      );

  testWidgets('an equal-but-distinct config does not rebuild dependents',
      (tester) async {
    final live = ValueNotifier(config());
    addTearDown(live.dispose);

    await tester.pumpWidget(
      LiveConfigProvider(config: live, child: const _Probe()),
    );
    expect(_Probe.builds, 1);
    expect(_Probe.padding, 8);

    // What a keystroke in an unrelated settings field looks like from here: a
    // brand-new AppConfig object holding exactly the same values.
    final rebuilt = config();
    expect(identical(rebuilt, live.value), isFalse);
    live.value = rebuilt;
    await tester.pump();

    expect(_Probe.builds, 1, reason: 'nothing moved, so nothing rebuilds');
  });

  testWidgets('a moved value does rebuild them', (tester) async {
    final live = ValueNotifier(config());
    addTearDown(live.dispose);

    await tester.pumpWidget(
      LiveConfigProvider(config: live, child: const _Probe()),
    );
    expect(_Probe.builds, 1);

    live.value = config(padding: 20);
    await tester.pump();
    expect(_Probe.builds, 2);
    expect(_Probe.padding, 20);
  });

  testWidgets('a change elsewhere in the config still reaches the scope',
      (tester) async {
    // The scope hands out the whole AppConfig, so a dependent wakes for an
    // edit anywhere in it. That is the accepted cost of one scope rather than
    // one per section — the win is that the *windows* no longer rebuild.
    final live = ValueNotifier(config());
    addTearDown(live.dispose);

    await tester.pumpWidget(
      LiveConfigProvider(config: live, child: const _Probe()),
    );
    live.value = config(theme: 'dracula');
    await tester.pump();
    expect(_Probe.builds, 2);
  });

  test('ValueNotifier suppresses the notify itself when nothing moved', () {
    // The first line of defence, before the scope is even consulted: the
    // notifier's setter compares with `==`, so an unchanged config wakes no
    // window's LiveConfigProvider at all.
    final live = ValueNotifier(config());
    addTearDown(live.dispose);
    var notified = 0;
    live.addListener(() => notified++);

    live.value = config();
    expect(notified, 0);

    live.value = config(padding: 12);
    expect(notified, 1);
  });
}

/// Reads one live field out of the enclosing scope, and counts how often it is
/// asked to. `const`, so nothing above it can rebuild it on its own.
class _Probe extends StatelessWidget {
  const _Probe();

  static int builds = 0;
  static int? padding;

  @override
  Widget build(BuildContext context) {
    builds++;
    padding = LiveConfigScope.of(context).panels['top']?.paddingHorizontal;
    return const SizedBox.shrink();
  }
}
