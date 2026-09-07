import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/host_process.dart';

/// The environment the classic snap's launcher actually leaves behind, minus
/// the entries that do not matter here. `LD_LIBRARY_PATH` is verbatim from
/// `snap/snapcraft.yaml`, with a host entry appended the way `$LD_LIBRARY_PATH`
/// at its tail would leave one.
Map<String, String> _snapEnvironment({String? libraryPath}) => {
  'SNAP': '/snap/graceful-shell/42',
  'SNAP_NAME': 'graceful-shell',
  'LD_LIBRARY_PATH': libraryPath ??
      '/snap/graceful-shell/42/usr/lib/x86_64-linux-gnu:'
          '/snap/graceful-shell/42/usr/lib/x86_64-linux-gnu/blas:'
          '/snap/graceful-shell/42/usr/lib/x86_64-linux-gnu/lapack:'
          '/snap/graceful-shell/42/usr/lib/x86_64-linux-gnu/pulseaudio:'
          '/snap/graceful-shell/42/lib:'
          '/home/user/.local/lib',
};

void main() {
  group('hostLibraryPath', () {
    test('drops every staged entry and keeps the host\'s own', () {
      // The bug: ffmpeg inheriting the first five of these resolves
      // libva.so.2 to core22's, and dies on `undefined symbol: vaMapBuffer2`.
      expect(
        hostLibraryPath(_snapEnvironment()),
        '/home/user/.local/lib',
      );
    });

    test('answers the empty string when every entry was ours', () {
      // Not null: null means "leave it alone", and leaving it alone is the
      // bug. An empty LD_LIBRARY_PATH is what the loader treats as unset, and
      // unsetting is not something the process API can express.
      expect(
        hostLibraryPath(_snapEnvironment(
          libraryPath: '/snap/graceful-shell/42/lib:'
              '/snap/graceful-shell/42/usr/lib/x86_64-linux-gnu',
        )),
        '',
      );
    });

    test('leaves a path with nothing of ours in it alone', () {
      expect(
        hostLibraryPath(_snapEnvironment(libraryPath: '/opt/vendor/lib')),
        isNull,
      );
    });

    test('changes nothing outside a snap', () {
      // A `make install` build owns none of the path, so every entry on it was
      // put there by the user or their session.
      expect(
        hostLibraryPath(const {'LD_LIBRARY_PATH': '/home/user/.local/lib'}),
        isNull,
      );
    });

    test('is a no-op when there is no library path at all', () {
      expect(hostLibraryPath(const {}), isNull);
      expect(hostLibraryPath(const {'SNAP': '/snap/graceful-shell/42'}), isNull);
      expect(
        hostLibraryPath(const {
          'SNAP': '/snap/graceful-shell/42',
          'LD_LIBRARY_PATH': '',
        }),
        isNull,
      );
    });

    test('matches the current symlink and snapd\'s other mount point', () {
      // Neither spelling is what snapcraft writes, but either is what a
      // launcher or a user adding a path by hand would use — and both are the
      // same directory as $SNAP.
      expect(
        hostLibraryPath(_snapEnvironment(
          libraryPath: '/snap/graceful-shell/current/lib:'
              '/var/lib/snapd/snap/graceful-shell/42/lib:'
              '/usr/local/lib',
        )),
        '/usr/local/lib',
      );
    });

    test('does not match a sibling whose name merely starts the same', () {
      expect(
        hostLibraryPath(_snapEnvironment(
          libraryPath: '/snap/graceful-shell-extras/9/lib:'
              '/snap/graceful-shell/42/lib',
        )),
        '/snap/graceful-shell-extras/9/lib',
      );
    });

    test('ignores a trailing slash on either side of the match', () {
      expect(
        hostLibraryPath(_snapEnvironment(
          libraryPath: '/snap/graceful-shell/42/lib/:/usr/lib/oss',
        )),
        '/usr/lib/oss',
      );
    });
  });
}
