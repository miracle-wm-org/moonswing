import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/desktop/widgets/news_widget.dart';
import 'package:moonswing/news/news_client.dart';
import 'package:moonswing/news/news_config.dart';
import 'package:moonswing/news/news_feed.dart';
import 'package:moonswing/news/news_source.dart';
import 'package:moonswing/news/news_store.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';

import 'news_fakes.dart';

/// The news card, pumped on the theme's own card the way the desktop frame
/// draws it.
void main() {
  final now = DateTime(2026, 10, 14, 15);
  late FakeNewsClient client;

  final headlines = [
    NewsHeadline(
      title: 'Central bank holds rates steady for a third month',
      link: 'https://example.com/rates',
      source: 'Reuters',
      published: DateTime(2026, 10, 14, 13, 5),
    ),
    NewsHeadline(
      title: 'Storm makes landfall',
      link: 'https://example.com/storm',
      source: 'AP',
      published: DateTime(2026, 10, 13, 9),
    ),
  ];

  setUp(() {
    client = FakeNewsClient({
      newsPreset('ap')!.url: rssDocument([
        (
          'Storm makes landfall',
          'https://example.com/storm',
          'Tue, 13 Oct 2026 09:00:00 GMT',
        ),
      ]),
      newsPreset('reuters')!.url: rssDocument([]),
    });
  });

  NewsStore seeded({
    NewsConfig config = const NewsConfig(),
    List<NewsHeadline>? items,
    Map<String, String> failures = const {},
  }) {
    final store = NewsStore.forTesting(client: client, config: config)
      ..seed(headlines: items ?? headlines, failures: failures);
    addTearDown(store.dispose);
    return store;
  }

  Future<void> pumpCard(
    WidgetTester tester,
    NewsStore store, {
    Size size = const Size(312, 312),
    VoidCallback? openSettings,
    List<String>? opened,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: PopupCard(
                child: NewsWidget(
                  span: (columns: 3, rows: 3),
                  store: store,
                  now: () => now,
                  openSettings: openSettings,
                  openUrl: (url) {
                    opened?.add(url);
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Nothing on the card animates, so it settles.
    await tester.pumpAndSettle();
  }

  testWidgets('a row per story: the headline, its outlet and when', (
    tester,
  ) async {
    final store = seeded();
    await pumpCard(tester, store);

    expect(tester.takeException(), isNull);
    expect(find.text('Headlines'), findsOneWidget);
    expect(
      find.text('Central bank holds rates steady for a third month'),
      findsOneWidget,
    );
    expect(find.text('Reuters · 13:05'), findsOneWidget);
    expect(find.text('AP · Yesterday'), findsOneWidget);
    expect(store.leaseCount, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a card one row tall drops the header and gives each story a '
      'line', (tester) async {
    final store = seeded();
    await pumpCard(tester, store, size: const Size(204, 84));
    expect(tester.takeException(), isNull);
    expect(find.text('Headlines'), findsNothing);
    final title = tester.widget<Text>(find.text('Storm makes landfall'));
    expect(title.maxLines, 1);
  });

  testWidgets('a large font_size grows the rows rather than clipping them', (
    tester,
  ) async {
    final store = seeded();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeScope(
            theme: const ThemeConfig(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 312,
                height: 312,
                child: NewsWidget(
                  span: (columns: 3, rows: 3),
                  store: store,
                  now: () => now,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking a story opens it, from the corner of its row too', (
    tester,
  ) async {
    final store = seeded();
    final opened = <String>[];
    await pumpCard(tester, store, opened: opened);
    await tester.tap(find.text('Storm makes landfall'));
    await tester.pump();
    expect(opened, ['https://example.com/storm']);

    // A corner, not the text: the row is the target, not the glyphs.
    final row = find
        .ancestor(
          of: find.text('Reuters · 13:05'),
          matching: find.byType(Container),
        )
        .first;
    await tester.tapAt(tester.getTopRight(row) + const Offset(-2, 2));
    await tester.pump();
    expect(opened.last, 'https://example.com/rates');
  });

  testWidgets('no sources sends the user to choose some', (tester) async {
    final store = seeded(
      config: const NewsConfig(sources: []),
      items: [],
    );
    var settings = 0;
    await pumpCard(tester, store, openSettings: () => settings++);
    expect(find.text('No news sources chosen'), findsOneWidget);
    await tester.tap(find.text('Choose sources'));
    await tester.pump();
    expect(settings, 1);
  });

  testWidgets('every feed failing with nothing to show offers a retry', (
    tester,
  ) async {
    client.failures[newsPreset('ap')!.url] = const NewsException(
      'Couldn’t reach news.google.com',
    );
    client.failures[newsPreset('reuters')!.url] = const NewsException(
      'Couldn’t reach news.google.com',
    );
    final store = NewsStore.forTesting(client: client);
    addTearDown(store.dispose);

    await pumpCard(tester, store);
    expect(find.text('No news source could be reached'), findsOneWidget);

    client.failures.clear();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Storm makes landfall'), findsOneWidget);
    expect(store.polling, isTrue);
    // Unmount, releasing the lease, so no timer outlives the test.
    await tester.pumpWidget(const SizedBox());
    expect(store.polling, isFalse);
  });

  testWidgets(
    'one feed failing keeps the stories, with the reason under them',
    (tester) async {
      final store = seeded(
        failures: const {'reuters': 'Reuters: news.google.com answered 503'},
      );
      await pumpCard(tester, store);
      expect(find.text('Storm makes landfall'), findsOneWidget);
      expect(
        find.text('Reuters: news.google.com answered 503'),
        findsOneWidget,
      );
    },
  );

  test('registers as a desktop widget a user can add', () {
    expect(newsDesktopWidget.type, 'news');
    expect(newsDesktopWidget.name, 'News');
    expect(newsDesktopWidget.minSpan, (columns: 2, rows: 1));
    expect(newsDesktopWidget.defaultSpan, (columns: 3, rows: 3));
    DesktopWidgetRegistry.register(newsDesktopWidget);
    addTearDown(DesktopWidgetRegistry.clear);
    expect(DesktopWidgetRegistry.lookup('news'), newsDesktopWidget);
  });
}
