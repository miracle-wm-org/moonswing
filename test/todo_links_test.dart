import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_links.dart';

List<String> _urls(String text) => [for (final l in findLinks(text)) l.url];

void main() {
  group('findLinks', () {
    test('finds http, https and ftp addresses where they sit', () {
      const text = 'See https://example.com/a?b=c#d and http://x.org';
      expect(findLinks(text), [
        const TodoLink(4, 31, 'https://example.com/a?b=c#d'),
        const TodoLink(36, 48, 'http://x.org'),
      ]);
      expect(_urls('ftp://files.example.net/pub'), [
        'ftp://files.example.net/pub',
      ]);
    });

    test('gives a bare www. address a scheme, but keeps its text range', () {
      expect(findLinks('go to www.example.com now'), [
        const TodoLink(6, 21, 'https://www.example.com'),
      ]);
    });

    test('leaves sentence punctuation out', () {
      expect(_urls('Read https://example.com/page.'), [
        'https://example.com/page',
      ]);
      expect(_urls('https://a.io, https://b.io; https://c.io!'), [
        'https://a.io',
        'https://b.io',
        'https://c.io',
      ]);
    });

    test('drops a closing bracket that opened outside the address', () {
      expect(_urls('(see https://example.com/x)'), ['https://example.com/x']);
      expect(_urls('https://en.wikipedia.org/wiki/Heat_(film)'), [
        'https://en.wikipedia.org/wiki/Heat_(film)',
      ]);
      expect(_urls('[https://en.wikipedia.org/wiki/Heat_(film)]'), [
        'https://en.wikipedia.org/wiki/Heat_(film)',
      ]);
    });

    test('stops at quotes and angle brackets', () {
      expect(_urls('<https://example.com>'), ['https://example.com']);
      expect(_urls('"https://example.com"'), ['https://example.com']);
    });

    test('ignores what is not an address', () {
      expect(findLinks(''), isEmpty);
      expect(findLinks('Buy milk'), isEmpty);
      expect(findLinks('https:// nothing'), isEmpty);
      expect(findLinks('www. nothing'), isEmpty);
      expect(findLinks('https://intranet'), isEmpty);
      expect(findLinks('mailto:someone@example.com'), isEmpty);
      expect(findLinks('notahttps://example.com'), isEmpty);
      expect(_urls('http://localhost:8080/x'), ['http://localhost:8080/x']);
    });
  });
}
