import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/polkit/agent_helper.dart';

void main() {
  group('parseHelperLine', () {
    test("reads the two prompt kinds and keeps PAM's own wording", () {
      final off = parseHelperLine('PAM_PROMPT_ECHO_OFF Password: ');
      expect(off, isA<PolkitHelperPrompt>());
      final offPrompt = off! as PolkitHelperPrompt;
      expect(offPrompt.echo, isFalse);
      expect(offPrompt.text, 'Password:');

      final on = parseHelperLine('PAM_PROMPT_ECHO_ON One-time code: ') as
          PolkitHelperPrompt;
      expect(on.echo, isTrue);
      expect(on.text, 'One-time code:');
    });

    test('reads the two message kinds', () {
      final error =
          parseHelperLine('PAM_ERROR_MSG Account locked') as PolkitHelperError;
      expect(error.text, 'Account locked');
      final info = parseHelperLine('PAM_TEXT_INFO Password expires in 3 days')
          as PolkitHelperInfo;
      expect(info.text, 'Password expires in 3 days');
    });

    test('reads the result tokens', () {
      final ok = parseHelperLine('SUCCESS') as PolkitHelperResult;
      expect(ok.authenticated, isTrue);
      final no = parseHelperLine('FAILURE') as PolkitHelperResult;
      expect(no.authenticated, isFalse);
    });

    // The helper prints the prefix and its trailing space before it has looked
    // at the PAM message, so a module with no prompt text still asks a
    // question — and one answered as "unknown line" would leave the helper
    // blocked on a read forever.
    test('a prompt with no words is still a prompt', () {
      expect(parseHelperLine('PAM_PROMPT_ECHO_OFF'), isA<PolkitHelperPrompt>());
      final bare =
          parseHelperLine('PAM_PROMPT_ECHO_OFF ') as PolkitHelperPrompt;
      expect(bare.text, isEmpty);
    });

    // The helper is a program on the host, not something this repo ships: a
    // version that grows a sixth token must cost that line and nothing else.
    test('anything else is dropped rather than thrown for', () {
      expect(parseHelperLine(''), isNull);
      expect(parseHelperLine('   '), isNull);
      expect(parseHelperLine('PAM_SOMETHING_NEW hello'), isNull);
      expect(parseHelperLine('SUCCESSFUL'), isNull);
      expect(parseHelperLine('PAM_PROMPT_ECHO_OFFISH x'), isNull);
    });
  });

  group('ProcessPolkitHelperRunner', () {
    // The helper is a setuid binary in a libexec directory and is on no
    // PATH — which one depends on the distribution's layout, not on its
    // polkit version. `lib/fortune/fortune_reader.dart` states the same rule
    // about /usr/games: a program present but unreachable must not be
    // reported as missing.
    test('looks in every layout the helper actually ships in', () {
      const candidates = ProcessPolkitHelperRunner.helperCandidates;
      expect(candidates, contains('/usr/lib/polkit-1/polkit-agent-helper-1'));
      expect(
        candidates,
        contains('/usr/lib/policykit-1/polkit-agent-helper-1'),
      );
      expect(candidates, contains('/usr/libexec/polkit-agent-helper-1'));
      expect(candidates.every((path) => path.startsWith('/')), isTrue);
    });
  });
}
