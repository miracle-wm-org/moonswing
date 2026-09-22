import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/github/github_token_store.dart';

/// Where the access token lives, and who can read it.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-github-token');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('a saved token comes back, and a cleared one does not', () async {
    final store = GithubTokenStore(directory: '${tempDir.path}/state');

    expect(await store.read(), isNull);
    expect(await store.write('gho_secret'), isTrue);
    expect(await store.read(), 'gho_secret');

    await store.clear();
    expect(await store.read(), isNull);
    // Clearing what is not there is done, not an error.
    await store.clear();
  });

  test('the file is readable by nobody else', () async {
    final store = GithubTokenStore(directory: '${tempDir.path}/state');
    await store.write('gho_secret');

    // The whole reason `chmodPath` exists: `dart:io` cannot say this, and a
    // bearer token under the default umask is readable by every account on the
    // machine.
    final mode = File(store.path).statSync().mode & 0x1FF;
    expect(mode, 0x180, reason: '0600');
    final dirMode = Directory(store.directory).statSync().mode & 0x1FF;
    expect(dirMode, 0x1C0, reason: '0700');
  });

  test('a token file with trailing whitespace still reads', () async {
    final store = GithubTokenStore(directory: tempDir.path);
    File(store.path).writeAsStringSync('gho_secret\n\n');

    expect(await store.read(), 'gho_secret');
  });

  test('an empty file is no token at all', () async {
    final store = GithubTokenStore(directory: tempDir.path);
    File(store.path).writeAsStringSync('   \n');

    expect(await store.read(), isNull);
  });

  test('a directory that cannot be written costs the save, not a throw',
      () async {
    // A path under a *file*: creating the directory cannot succeed.
    final blocker = File('${tempDir.path}/blocker')..writeAsStringSync('x');
    final store = GithubTokenStore(directory: '${blocker.path}/state');

    expect(await store.write('gho_secret'), isFalse);
    expect(await store.read(), isNull);
  });

  test('the default location is the XDG state directory', () {
    const store = GithubTokenStore();

    // Not `~/.config`: that file is hand-edited and pasted into bug reports.
    expect(store.directory, endsWith('/moonswing'));
    expect(store.path, endsWith('/github-token'));
  });
}
