import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/overlay/file_picker.dart';
import 'package:moonswing/overlay/file_picker_controller.dart';

const FilePickerRequest _request = FilePickerRequest(
  filters: [FilePickerFilter.all],
);

void main() {
  group('FilePickerController', () {
    // The same rule ScreencastPickerController follows: a request nothing can
    // answer is declined immediately rather than left hanging, so a headless
    // run never awaits a window that will not appear.
    test('declines immediately when nothing is listening', () async {
      final controller = FilePickerController.forTesting();
      addTearDown(controller.dispose);
      expect(await controller.pick(_request), isNull);
      expect(controller.pending, isNull);
    });

    test('holds the request and resolves on complete', () async {
      final controller = FilePickerController.forTesting();
      addTearDown(controller.dispose);
      controller.addListener(() {});

      final future = controller.pick(_request);
      expect(controller.pending, isNotNull);
      expect(controller.pending?.allowDirectories, isFalse);

      controller.complete(['/tmp/a.txt']);
      expect(await future, ['/tmp/a.txt']);
      expect(controller.pending, isNull);
    });

    test('a cancel resolves to null', () async {
      final controller = FilePickerController.forTesting();
      addTearDown(controller.dispose);
      controller.addListener(() {});

      final future = controller.pick(_request);
      controller.complete(null);
      expect(await future, isNull);
    });

    test('a second complete is a no-op', () async {
      final controller = FilePickerController.forTesting();
      addTearDown(controller.dispose);
      controller.addListener(() {});

      final future = controller.pick(_request);
      controller.complete(['/tmp/a.txt']);
      controller.complete(['/tmp/b.txt']);
      expect(await future, ['/tmp/a.txt']);
    });

    // No caller may be left awaiting a window that has been replaced.
    test('a second request supersedes the first, cancelling it', () async {
      final controller = FilePickerController.forTesting();
      addTearDown(controller.dispose);
      controller.addListener(() {});

      final first = controller.pick(_request);
      final second = controller.pick(const FilePickerRequest(
        filters: [FilePickerFilter.all],
        allowDirectories: true,
      ));

      expect(await first, isNull);
      expect(controller.pending?.allowDirectories, isTrue);

      controller.complete(['/tmp/dir']);
      expect(await second, ['/tmp/dir']);
    });

    // A shell tearing down still owes every awaiting caller an answer.
    test('dispose resolves an outstanding request as cancelled', () async {
      final controller = FilePickerController.forTesting();
      controller.addListener(() {});
      final future = controller.pick(_request);
      controller.dispose();
      expect(await future, isNull);
    });
  });

  group('FilePickerFilter.desktopEntries', () {
    test('matches .desktop files only, case-insensitively', () {
      expect(FilePickerFilter.desktopEntries.matches('/a/firefox.desktop'),
          isTrue);
      expect(FilePickerFilter.desktopEntries.matches('/a/Foo.DESKTOP'), isTrue);
      expect(FilePickerFilter.desktopEntries.matches('/a/notes.txt'), isFalse);
    });
  });
}
