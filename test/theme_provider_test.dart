import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/theme_provider.dart';
import 'package:graceful_shell/theme/theme_store.dart';

/// The regression test for the guarantee the theming engine is built on: a
/// tree under a [ThemeProvider] restyles when the theme changes, *without* the
/// widget that opened it rebuilding.
///
/// That last part is what the shell's popups need. Popup content is built once
/// and captured in a `WindowEntry` builder, so the widget instance never comes
/// back — only the elements already mounted in that tree can respond. Here the
/// content is deliberately held in a `const` child so nothing above it can
/// rebuild it.
///
/// No [ConfigStore] is bound: the store's config-driven path is covered in
/// `theme_store_test.dart`, and its debounced disk write does real async I/O,
/// which does not mix with `testWidgets`' fake async.
void main() {
  late Directory tempDir;
  late ThemeStore themes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gs_theme_provider_test');
    themes = ThemeStore.forTesting(directory: '${tempDir.path}/themes');
    themes.start();
  });

  tearDown(() async {
    themes.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Color paintedColor(WidgetTester tester) =>
      (tester.widget<ColoredBox>(find.byType(ColoredBox))).color;

  /// Writes out anything the store is holding behind its debounce. The body
  /// runs synchronously, so the timer is gone before the framework's
  /// pending-timer check — no await needed, and none wanted under fake async.
  void settle() => themes.flush();

  testWidgets('a captured subtree restyles when the theme changes',
      (tester) async {
    await tester.pumpWidget(
      ThemeProvider(
        store: themes,
        child: const _AccentBox(),
      ),
    );
    expect(paintedColor(tester), const Color(0xFF853953)); // graceful

    themes.select('dracula');
    await tester.pump();
    expect(paintedColor(tester), const Color(0xFFBD93F9)); // dracula

    themes.select('glassy');
    await tester.pump();
    expect(paintedColor(tester), const Color(0xFF7FB6FF)); // glassy

    settle();
  });

  testWidgets("the theme's font size reaches text that sized itself",
      (tester) async {
    // The point of putting the scaler here rather than on a DefaultTextStyle:
    // nearly every string in the shell names its own size, and one that names
    // one has to move too or the setting appears to do nothing.
    themes.create('Mine');
    await tester.pumpWidget(
      ThemeProvider(store: themes, child: const _SizedText()),
    );
    final before = tester.getSize(find.byType(Text));
    expect(MediaQuery.textScalerOf(tester.element(find.byType(Text))),
        TextScaler.noScaling);

    themes.edit('font_size', 26.0);
    await tester.pump();

    // 26 is twice the body tier the sizes are quoted against.
    expect(MediaQuery.textScalerOf(tester.element(find.byType(Text))),
        TextScaler.linear(2.0));
    final after = tester.getSize(find.byType(Text));
    expect(after.height, greaterThan(before.height));
    expect(after.width, greaterThan(before.width));

    settle();
  });

  testWidgets('an edit to the active theme repaints too', (tester) async {
    themes.create('Mine');
    await tester.pumpWidget(
      ThemeProvider(store: themes, child: const _AccentBox()),
    );

    themes.edit('accent', '#00FF00');
    await tester.pump();
    expect(paintedColor(tester), const Color(0xFF00FF00));

    settle();
  });
}

/// A line of text that sizes itself, as nearly everything in the shell does.
/// `const` for the same reason as [_AccentBox]: nothing above it rebuilds it,
/// so what moves the text can only be the scaler it inherits.
class _SizedText extends StatelessWidget {
  const _SizedText();

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text('Ag', style: TextStyle(fontSize: 13)),
        ),
      );
}

/// Reads the accent from the enclosing scope. `const`, so the only thing that
/// can repaint it is the [ThemeScope] above it changing.
class _AccentBox extends StatelessWidget {
  const _AccentBox();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: ThemeScope.of(context).accent);
}
