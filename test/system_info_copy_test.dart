import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/overlay/system_info/system_info_tab.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/system/input_devices.dart';
import 'package:moonswing/system/system_info.dart';

/// System Info's "Copy all": what it puts on the clipboard, and what it says
/// when that does not work.
void main() {
  const info = SystemInfo(
    cpuModel: 'AMD Ryzen 7 7840U',
    cpuCores: '16',
    totalMemory: '32.0 GB',
    kernel: '6.8.0-generic',
    hostname: 'gracebox',
    inputDevices: [
      InputDevice(kind: InputDeviceKind.keyboard, name: 'AT Keyboard'),
    ],
  );

  group('systemInfoPlainText', () {
    test('lists every section and row of the page, in its order', () {
      final text = systemInfoPlainText(info);
      final lines = text.split('\n');

      expect(lines.first, 'Hardware');
      for (final section in systemInfoSections(info)) {
        expect(lines, contains(section.title));
        for (final row in section.rows) {
          expect(
            lines.any(
              (line) =>
                  line.trimLeft().startsWith('${row.label}:') &&
                  line.endsWith(row.value ?? '—'),
            ),
            isTrue,
            reason: '${row.label} is missing',
          );
        }
      }
      expect(
        text.indexOf('Hardware') < text.indexOf('Input devices') &&
            text.indexOf('Input devices') < text.indexOf('Software') &&
            text.indexOf('Software') < text.indexOf('Environment'),
        isTrue,
      );
    });

    test('lines every value up in one column', () {
      final text = systemInfoPlainText(info);
      final valueColumns = {
        for (final section in systemInfoSections(info))
          for (final row in section.rows)
            if (row.value case final value?)
              text
                  .split('\n')
                  .firstWhere((line) => line.endsWith(value))
                  .indexOf(value),
      };
      expect(valueColumns, hasLength(1));
    });

    test('says what was not reported, rather than leaving it blank', () {
      final text = systemInfoPlainText(const SystemInfo());
      expect(text, contains(RegExp(r'Swap: +—')));
      expect(text, contains(RegExp(r'Devices: +—')));
    });
  });

  group('SystemInfoTab', () {
    Future<List<String>> pump(
      WidgetTester tester, {
      ClipboardResult result = ClipboardResult.copied,
    }) async {
      final copied = <String>[];
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: SystemInfoTab(
              read: () async => info,
              copy: (text) async {
                copied.add(text);
                return result;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return copied;
    }

    testWidgets('copies the page as plain text and says so', (tester) async {
      final copied = await pump(tester);

      await tester.tap(find.text('Copy all'));
      await tester.pumpAndSettle();

      expect(copied, [systemInfoPlainText(info)]);
      expect(find.text('Copied to the clipboard.'), findsOneWidget);
    });

    testWidgets('names the package when wl-copy is missing', (tester) async {
      await pump(tester, result: ClipboardResult.unavailable);

      await tester.tap(find.text('Copy all'));
      await tester.pumpAndSettle();

      expect(
        find.text('Install $kClipboardPackage to copy it.'),
        findsOneWidget,
      );
    });

    testWidgets('copies nothing before the machine has been read', (
      tester,
    ) async {
      final copied = <String>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: SystemInfoTab(
              // Never resolves: the page stays on its placeholders.
              read: () => Completer<SystemInfo>().future,
              copy: (text) async {
                copied.add(text);
                return ClipboardResult.copied;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Copy all'));
      await tester.pump();

      expect(copied, isEmpty);
    });
  });
}
