import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/news/news_client.dart';
import 'package:moonswing/news/news_config.dart';
import 'package:moonswing/news/news_source.dart';
import 'package:moonswing/news/news_store.dart';

import 'news_fakes.dart';

void main() {
  group('NewsConfig', () {
    test('an absent table is the two wire services every fifteen minutes', () {
      final config = NewsConfig.fromMap(null);
      expect(config.sources, ['ap', 'reuters']);
      expect(config.refreshMinutes, 15);
      expect(config.feeds.map((f) => f.name), ['AP', 'Reuters']);
      expect(NewsConfig.fromMap(const {}), config);
    });

    test('an explicit empty list is no sources, not the default', () {
      expect(
        NewsConfig.fromMap(const {'sources': <String>[]}).sources,
        isEmpty,
      );
    });

    test('entries are normalized, de-duplicated, and dropped when they name '
        'nothing', () {
      final config = NewsConfig.fromMap(const {
        'sources': [
          'AP',
          'ap',
          ' npr ',
          'apn',
          42,
          'ftp://example.com/feed',
          'https://example.com/feed.xml',
        ],
      });
      expect(config.sources, ['ap', 'npr', 'https://example.com/feed.xml']);
      final custom = config.feeds.last;
      expect(custom.name, 'example.com');
      expect(custom.preset, isFalse);
    });

    test('the period is clamped, a wrong type costs the key', () {
      expect(
        NewsConfig.fromMap(const {'refresh_minutes': 0}).refreshMinutes,
        5,
      );
      expect(
        NewsConfig.fromMap(const {'refresh_minutes': 99999}).refreshMinutes,
        1440,
      );
      expect(
        NewsConfig.fromMap(const {'refresh_minutes': 30.0}).refreshMinutes,
        30,
      );
      final wrong = NewsConfig.fromMap(const {
        'refresh_minutes': 'often',
        'sources': 'ap',
      });
      expect(wrong, const NewsConfig());
    });

    test(
      'the presets are the wire services and broadcasters, by stable id',
      () {
        expect(kNewsPresets.map((p) => p.id), [
          'ap',
          'reuters',
          'npr',
          'bbc',
          'pbs',
        ]);
        final ap = newsPreset('ap')!.url;
        expect(ap.host, 'news.google.com');
        expect(ap.queryParameters['q'], 'site:apnews.com when:1d');
        for (final preset in kNewsPresets) {
          expect(preset.url.scheme, 'https', reason: preset.id);
        }
      },
    );
  });

  group('NewsStore', () {
    late FakeNewsClient client;
    late DateTime now;

    setUp(() {
      client = FakeNewsClient({
        newsPreset('ap')!.url: rssDocument([
          ('Quake hits coast', 'https://ap.example/1', '14 Oct 2026 10:00 GMT'),
          ('Budget passes', 'https://ap.example/2', '14 Oct 2026 08:00 GMT'),
        ]),
        newsPreset('reuters')!.url: rssDocument([
          (
            'Rates held - Reuters',
            'https://r.example/1',
            '14 Oct 2026 09:00 GMT',
          ),
          ('Quake Hits Coast', 'https://r.example/2', '14 Oct 2026 09:30 GMT'),
        ], itemSource: 'Reuters'),
      });
      now = DateTime.utc(2026, 10, 14, 12);
    });

    NewsStore store({NewsConfig config = const NewsConfig()}) {
      final s = NewsStore.forTesting(
        client: client,
        config: config,
        clock: () => now,
      );
      addTearDown(s.dispose);
      return s;
    }

    test('merges every feed, newest first, a shared story once', () async {
      final s = store();
      await s.refresh();
      expect(s.loading, isFalse);
      expect(s.headlines.map((h) => '${h.source}: ${h.title}'), [
        'AP: Quake hits coast',
        'Reuters: Rates held',
        'AP: Budget passes',
      ]);
      expect(s.error, isEmpty);
      expect(s.updatedAt, now);
    });

    test('one feed failing keeps its last good stories and is named', () async {
      final s = store();
      await s.refresh();
      client.failures[newsPreset('reuters')!.url] = const NewsException(
        'Couldn’t reach news.google.com',
      );
      await s.refresh();
      expect(s.headlines, hasLength(3), reason: 'last good stories stay');
      expect(s.failures.single.source, 'Reuters');
      expect(s.error, 'Reuters: Couldn’t reach news.google.com');
      expect(s.allFailed, isFalse);
    });

    test(
      'every feed failing with nothing to show is a visible state',
      () async {
        client.failures[newsPreset('ap')!.url] = const NewsException('down');
        client.documents[newsPreset('reuters')!.url] = '<html>consent</html>';
        final s = store();
        await s.refresh();
        expect(s.hasHeadlines, isFalse);
        expect(s.allFailed, isTrue);
        expect(s.error, 'No news source could be reached');
      },
    );

    test('a read that changed nothing does not notify', () async {
      final s = store();
      await s.refresh();
      var notified = 0;
      s.addListener(() => notified++);
      await s.refresh();
      expect(notified, 0);
      client.documents[newsPreset('ap')!.url] = rssDocument([
        ('Fresh story', 'https://ap.example/3', '14 Oct 2026 11:00 GMT'),
      ]);
      await s.refresh();
      expect(notified, 1);
    });

    test('changing the sources drops what left and reads what came', () async {
      final s = store();
      await s.refresh();
      s.configure(const NewsConfig(sources: ['ap']));
      expect(s.headlines.every((h) => h.source == 'AP'), isTrue);
      expect(s.feeds.map((f) => f.id), ['ap']);
    });

    test('no sources reads nothing and says so', () async {
      final s = store(config: const NewsConfig(sources: []));
      await s.refresh();
      expect(client.fetches, isEmpty);
      expect(s.hasHeadlines, isFalse);
      expect(s.error, isEmpty);
      expect(s.loading, isFalse);
    });

    testWidgets('the period is timed from the last read, and a lease after '
        'a long absence reads at once', (tester) async {
      final s = NewsStore.forTesting(client: client, clock: () => now);
      s.acquire();
      await tester.pump();
      expect(client.fetches, hasLength(2), reason: 'first lease reads');
      expect(s.polling, isTrue);

      // Ten minutes on, a second card comes and goes: no read.
      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 10));
      s.release();
      expect(s.polling, isFalse);
      s.acquire();
      await tester.pump();
      expect(client.fetches, hasLength(2), reason: 'not yet due');

      // The remaining five minutes of the period, then a read.
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      expect(client.fetches, hasLength(4));

      // Off screen for an hour: the next lease reads straight away.
      s.release();
      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      expect(client.fetches, hasLength(4), reason: 'no lease, no read');
      s.acquire();
      await tester.pump();
      expect(client.fetches, hasLength(6));

      // A suspend the timer did not count is caught up on waking.
      now = now.add(const Duration(hours: 2));
      s.resumed();
      await tester.pump();
      expect(client.fetches, hasLength(8));

      s.release();
      s.dispose();
    });

    testWidgets('a failure everywhere retries sooner than a long period', (
      tester,
    ) async {
      client.failures[newsPreset('ap')!.url] = const NewsException('down');
      client.failures[newsPreset('reuters')!.url] = const NewsException('x');
      final s = NewsStore.forTesting(
        client: client,
        config: const NewsConfig(refreshMinutes: 120),
        clock: () => now,
      );
      s.acquire();
      await tester.pump();
      expect(client.fetches, hasLength(2));
      client.failures.clear();
      now = now.add(kNewsRetryDelay);
      await tester.pump(kNewsRetryDelay);
      expect(client.fetches, hasLength(4));
      expect(s.hasHeadlines, isTrue);
      s.release();
      s.dispose();
    });

    test('acquire does not notify synchronously', () {
      final s = store();
      var notified = 0;
      s.addListener(() => notified++);
      s.acquire();
      expect(notified, 0);
      s.release();
      // Let the microtask's read land before the store is disposed.
      return Future<void>.delayed(Duration.zero);
    });
  });
}
