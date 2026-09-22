import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/overlay/settings/shell/weather_location.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_config.dart';
import 'package:moonswing/world_cities.dart';

const _berlin = WeatherPlace(
  name: 'Berlin',
  latitude: 52.52,
  longitude: 13.405,
  country: 'Germany',
);
const _springfield = WeatherPlace(
  name: 'Springfield',
  latitude: 39.8,
  longitude: -89.65,
  admin: 'Illinois',
  country: 'United States',
);

/// A store over a temp file, so no test touches the user's real config.toml.
///
/// Through [WidgetTester.runAsync], because writing and parsing the file is real
/// I/O and a `testWidgets` fake-async zone never pumps it.
Future<ConfigStore> _store(WidgetTester tester, String toml) async {
  final store = await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('weather_location_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/config.toml';
    await File(path).writeAsString(toml);
    return ConfigStore.loadFrom(path);
  });
  addTearDown(store!.dispose);
  return store;
}

/// The shell's own table, as a widget test can state it.
///
/// Injected rather than taken from `kWorldCities` for the reason
/// `AnchoredSearchDropdown` documents: a test asserting what the card shows has
/// to be able to say what is in it. Most cases pass `const []` and are about the
/// geocoder's half alone.
final _cities = [
  WorldCity(
    name: 'New Delhi',
    admin: 'Delhi',
    country: 'India',
    zone: 'Asia/Kolkata',
    latitude: 28.61,
    longitude: 77.21,
  ),
  WorldCity(
    name: 'Berlin',
    country: 'Germany',
    zone: 'Europe/Berlin',
    latitude: 52.52,
    longitude: 13.405,
  ),
];

Future<void> _pumpField(
  WidgetTester tester,
  ConfigStore store, {
  required WeatherPlaceSearch search,
  List<WorldCity> cities = const [],
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                // Right-aligned, where the control actually sits: the field
                // passes `alignRight`, so its list grows leftwards out of a
                // trigger at the right edge of the pane. Pumped at the left edge
                // the card hangs off the screen and nothing in it is tappable.
                builder: (_) => Align(
                  alignment: Alignment.topRight,
                  child: ListenableBuilder(
                    listenable: store,
                    builder: (_, _) => WeatherLocationField(
                      store: store,
                      search: search,
                      cities: cities,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('reads Automatic when no location is set', (tester) async {
    final store = await _store(tester, '');
    await _pumpField(tester, store, search: (_) async => const []);
    expect(find.text('Automatic (from IP)'), findsOneWidget);
  });

  testWidgets('reads the saved location', (tester) async {
    final store = await _store(tester, '''
[modules.weather]
location = "Berlin, Germany"
latitude = 52.52
longitude = 13.405
''');
    await _pumpField(tester, store, search: (_) async => const []);
    expect(find.text('Berlin, Germany'), findsOneWidget);
  });

  testWidgets('a name with no coordinates behind it still reads as Automatic',
      (tester) async {
    // WeatherConfig.place refuses a half-written pair, so a trigger reading
    // only the name would claim a location the store is not fetching for.
    final store = await _store(tester, '''
[modules.weather]
location = "Berlin, Germany"
latitude = 52.52
''');
    await _pumpField(tester, store, search: (_) async => const []);
    expect(find.text('Automatic (from IP)'), findsOneWidget);
    expect(find.text('Berlin, Germany'), findsNothing);
  });

  testWidgets('the automatic row is offered before anything is typed',
      (tester) async {
    final store = await _store(tester, '');
    await _pumpField(tester, store, search: (_) async => const []);

    await tester.tap(find.text('Automatic (from IP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Wherever this machine is'), findsOneWidget);
  });

  testWidgets('typing searches, and picking writes all three keys',
      (tester) async {
    final queries = <String>[];
    final store = await _store(tester, '');
    await _pumpField(
      tester,
      store,
      search: (query) async {
        queries.add(query);
        return query.isEmpty ? const [] : const [_berlin, _springfield];
      },
    );

    await tester.tap(find.text('Automatic (from IP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(EditableText), 'berlin');
    // Past the debounce: a request per keystroke is a request per keystroke
    // against somebody else's API.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(queries, contains('berlin'));
    expect(find.text('Berlin'), findsOneWidget);
    expect(find.text('Germany'), findsOneWidget);
    // The disambiguating half, without which thirty Springfields are thirty
    // identical rows.
    expect(find.text('Illinois, United States'), findsOneWidget);

    await tester.tap(find.text('Berlin'));
    // Past ConfigStore's save debounce, or the fake-async zone ends holding a
    // pending timer.
    await tester.pump(const Duration(milliseconds: 500));

    expect(store.get<String>(kWeatherLocationPath), 'Berlin, Germany');
    expect(store.get<num>(kWeatherLatitudePath), 52.52);
    expect(store.get<num>(kWeatherLongitudePath), 13.405);
    // And the config the store reads it back through agrees.
    final config = WeatherConfig.fromMap(
        store.get<Map<String, dynamic>>(const ['modules', 'weather']));
    expect(config.place?.latitude, 52.52);
  });

  testWidgets('picking Automatic removes all three keys', (tester) async {
    // Removed rather than blanked: an empty `location = ""` beside two live
    // coordinates is exactly the half-written state this row prevents.
    final store = await _store(tester, '''
[modules.weather]
location = "Berlin, Germany"
latitude = 52.52
longitude = 13.405
''');
    await _pumpField(tester, store, search: (_) async => const [_berlin]);

    await tester.tap(find.text('Berlin, Germany'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Automatic (from IP)').last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(store.get<String>(kWeatherLocationPath), isNull);
    expect(store.get<num>(kWeatherLatitudePath), isNull);
    expect(store.get<num>(kWeatherLongitudePath), isNull);
  });

  testWidgets('a failed lookup costs the geocoder, not the shell\'s own list',
      (tester) async {
    // The dropdown is not the place to explain a failed HTTP request — but the
    // table is local data, and a network that is down is no reason to stop
    // offering it.
    final store = await _store(tester, '');
    await _pumpField(
      tester,
      store,
      cities: _cities,
      search: (_) async => throw const WeatherException('offline'),
    );

    await tester.tap(find.text('Automatic (from IP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('New Delhi'), findsOneWidget);
    expect(find.text('Wherever this machine is'), findsOneWidget);
  });

  testWidgets('the shell\'s own cities are offered without a request',
      (tester) async {
    // The list the world clock picker offers, in the weather row too — and
    // answered on the keystroke rather than after the debounce, because these
    // are places the shell has known about since it was compiled.
    var requests = 0;
    final store = await _store(tester, '');
    await _pumpField(
      tester,
      store,
      cities: _cities,
      search: (_) async {
        requests++;
        return const [];
      },
    );

    await tester.tap(find.text('Automatic (from IP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(EditableText), 'new delhi');
    // No debounce waited out: this is the synchronous half.
    await tester.pump();

    expect(find.text('New Delhi'), findsOneWidget);
    expect(find.text('Delhi, India'), findsOneWidget);
    expect(requests, 1); // The one made when the list opened, and no other.

    await tester.tap(find.text('New Delhi'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(store.get<String>(kWeatherLocationPath), 'New Delhi, Delhi, India');
    expect(store.get<num>(kWeatherLatitudePath), 28.61);
    expect(store.get<num>(kWeatherLongitudePath), 77.21);
  });

  testWidgets('the geocoder fills in under them, without repeating one',
      (tester) async {
    final store = await _store(tester, '');
    await _pumpField(
      tester,
      store,
      cities: _cities,
      // Berlin is in the table already; Springfield is not.
      search: (_) async => const [_berlin, _springfield],
    );

    await tester.tap(find.text('Automatic (from IP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(EditableText), 'berlin');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // One row, not two: the geocoder's answer for a place already listed is
    // the same row with coordinates a fraction apart.
    expect(find.text('Berlin'), findsOneWidget);
    expect(find.text('Springfield'), findsOneWidget);
  });

  testWidgets('a slow answer for an earlier query never lands on a later one',
      (tester) async {
    // "lon" must not overwrite "london" because it was slower.
    final store = await _store(tester, '');
    await _pumpField(
      tester,
      store,
      search: (query) async {
        if (query == 'lon') {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          return const [_springfield];
        }
        return const [_berlin];
      },
    );

    await tester.tap(find.text('Automatic (from IP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(EditableText), 'lon');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(EditableText), 'london');
    await tester.pump(const Duration(milliseconds: 400));
    // Long enough for the stale answer to arrive.
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Berlin'), findsOneWidget);
    expect(find.text('Springfield'), findsNothing);
  });
}
