import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/theme/font_catalog.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');

void main() {
  group('parseFcListFamilies', () {
    test('deduplicates the one line fc-list emits per font file', () {
      final families = parseFcListFamilies(
        'Ubuntu Sans\nUbuntu Sans\nUbuntu Sans\nJetBrains Mono\n',
      );

      expect(families, ['JetBrains Mono', 'Ubuntu Sans']);
    });

    test('keeps only the first family of a comma-joined line', () {
      final families = parseFcListFamilies(
        'Ubuntu Nerd Font Propo,Ubuntu Nerd Font Propo Light\n',
      );

      expect(families, ['Ubuntu Nerd Font Propo']);
    });

    test('drops blank lines and trims surrounding whitespace', () {
      final families = parseFcListFamilies('\n  Cantarell  \n\n\n');

      expect(families, ['Cantarell']);
    });

    test('dedupes and sorts case-insensitively', () {
      // A case-sensitive sort would put every lowercase name after 'Zed'.
      final families = parseFcListFamilies(
        'zed mono\nUbuntu Sans\nUBUNTU SANS\nadobe Text\n',
      );

      expect(families, ['adobe Text', 'Ubuntu Sans', 'zed mono']);
    });

    test('is empty for empty output', () {
      expect(parseFcListFamilies(''), isEmpty);
    });
  });

  group('FontCatalog', () {
    test('runs fc-list with the primary-family format', () async {
      String? seenExecutable;
      List<String>? seenArgs;
      final catalog = FontCatalog(runner: (exe, args) async {
        seenExecutable = exe;
        seenArgs = args;
        return _ok('Cantarell\n');
      });

      expect(await catalog.list(), ['Cantarell']);
      expect(seenExecutable, 'fc-list');
      expect(seenArgs, ['--format', '%{family[0]}\n']);
    });

    test('is empty when fc-list exits non-zero', () async {
      final catalog = FontCatalog(
        runner: (_, _) async => ProcessResult(0, 1, '', 'boom'),
      );

      expect(await catalog.list(), isEmpty);
    });

    test('is empty when there is no fc-list at all', () async {
      final catalog = FontCatalog(
        runner: (_, _) async => throw const ProcessException('fc-list', []),
      );

      expect(await catalog.list(), isEmpty);
    });

    test('memoises, so concurrent callers share one fork', () async {
      var runs = 0;
      final catalog = FontCatalog(runner: (_, _) async {
        runs++;
        return _ok('Cantarell\n');
      });

      final results = await Future.wait([catalog.list(), catalog.list()]);
      await catalog.list();

      expect(runs, 1);
      expect(results.first, ['Cantarell']);
    });
  });
}
