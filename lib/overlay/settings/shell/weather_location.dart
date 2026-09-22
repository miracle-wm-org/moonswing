// The Weather group's location row: automatic, or a place the user searched for
// by name.
//
// A control of its own rather than another `_ModuleSetting`, because it is the
// one weather setting that is not a value the user can type: latitude/longitude
// are what the API wants and a place name is what the user knows, and only a
// geocoding request turns one into the other. The three keys are written
// together — a location is the triple, and a half-written one is a config that
// names Berlin and fetches for the prime meridian.

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/config_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/search_list.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/weather/weather_api.dart';
import 'package:moonswing/weather/weather_config.dart';
import 'package:moonswing/world_cities.dart';

/// The config path each half of the location lives at.
const List<String> kWeatherLocationPath = ['modules', 'weather', 'location'];
const List<String> kWeatherLatitudePath = ['modules', 'weather', 'latitude'];
const List<String> kWeatherLongitudePath = ['modules', 'weather', 'longitude'];

/// One row of the picker: a place, or the automatic entry.
///
/// A wrapper rather than a nullable [WeatherPlace] so "detect it from my IP
/// address" is something the user selects rather than clears — the row is always
/// at the top, and picking it is how a chosen location is undone.
class WeatherLocationChoice {
  const WeatherLocationChoice.automatic() : place = null;
  const WeatherLocationChoice.at(WeatherPlace this.place);

  final WeatherPlace? place;

  bool get isAutomatic => place == null;
}

/// Searches for places by name. Injected so a widget test never opens a socket.
typedef WeatherPlaceSearch = Future<List<WeatherPlace>> Function(String query);

/// How many of the shell's own cities the list offers before the geocoder's
/// answers. Enough to fill the card, few enough that a real match for what was
/// typed is never pushed under the fold by places that merely also matched.
const int kWeatherCityLimit = 6;

/// The settings row that picks where the weather is read for.
class WeatherLocationField extends StatelessWidget {
  WeatherLocationField({
    super.key,
    required this.store,
    WeatherPlaceSearch? search,
    List<WorldCity>? cities,
  })  : search = search ?? const OpenMeteoClient().search,
        cities = cities ?? kWorldCities;

  final ConfigStore store;
  final WeatherPlaceSearch search;

  /// The shell's own gazetteer — the same table the world-clock picker offers.
  ///
  /// A parameter for the reason [AnchoredSearchDropdown] documents about every
  /// list it is given: a widget test asserting what the card shows must be able
  /// to say what is in it.
  final List<WorldCity> cities;

  /// What the trigger reads: the saved name, or the automatic label.
  ///
  /// A saved *name* with no coordinates behind it is shown as automatic, which is
  /// what it is: [WeatherConfig.place] refuses a half-written pair, so a trigger
  /// reading only the name would claim a location the store is not fetching for.
  String get _label {
    final config = WeatherConfig(
      locationName: store.get<String>(kWeatherLocationPath) ?? '',
      latitude: store.get<num>(kWeatherLatitudePath)?.toDouble(),
      longitude: store.get<num>(kWeatherLongitudePath)?.toDouble(),
    );
    final place = config.place;
    return place == null ? 'Automatic (from IP)' : place.name;
  }

  /// The rows to show without asking anybody: the automatic entry and whatever
  /// the shell's own table matches.
  ///
  /// The [AnchoredSearchDropdown.filter] half, which answers on the keystroke
  /// rather than after the debounce — so the card fills in as the user types
  /// instead of sitting on "Searching…" for a place the shell already knows.
  List<WeatherLocationChoice> _local(String query) {
    // The automatic row is always first, whatever was typed: it is how a
    // chosen location is undone, and a user who has typed three letters of a
    // city they then think better of must not have to clear the field to find
    // it again.
    return [
      const WeatherLocationChoice.automatic(),
      for (final city
          in rankWorldCities(cities, query, limit: kWeatherCityLimit))
        WeatherLocationChoice.at(_placeFor(city)),
    ];
  }

  /// The same rows with the geocoder's answers under them.
  ///
  /// Merged rather than swapped, and in that order: the table is the places
  /// somebody is most likely to mean and the geocoder is everywhere else, so a
  /// request that lands must not take New Delhi off a list it was already on. A
  /// place the geocoder repeats is dropped rather than listed twice.
  ///
  /// A failed lookup costs the geocoder's half alone: the table is local data, and
  /// a network that is down is no reason to stop offering it.
  Future<List<WeatherLocationChoice>> _search(String query) async {
    final local = _local(query);
    List<WeatherPlace> remote;
    try {
      remote = await search(query);
    } catch (_) {
      remote = const [];
    }
    final seen = <String>{
      for (final choice in local)
        if (choice.place != null) _dedupeKey(choice.place!),
    };
    return [
      ...local,
      for (final place in remote)
        if (seen.add(_dedupeKey(place))) WeatherLocationChoice.at(place),
    ];
  }

  void _select(WeatherLocationChoice choice) {
    final place = choice.place;
    if (place == null) {
      // Removed rather than blanked: an empty `location = ""` beside two live
      // coordinates is exactly the half-written state this row exists to
      // prevent, and `TomlReader` reads an absent key and an empty one the
      // same way anyway.
      store
        ..remove(kWeatherLocationPath)
        ..remove(kWeatherLatitudePath)
        ..remove(kWeatherLongitudePath);
      return;
    }
    store
      ..set(kWeatherLocationPath, place.description)
      ..set(kWeatherLatitudePath, place.latitude)
      ..set(kWeatherLongitudePath, place.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    // Three keys, one derived label, one subscription. This row used to rebuild
    // under the pane's own `ListenableBuilder`, so it re-read all three on
    // every keystroke anywhere in the settings UI; now it rebuilds only when
    // the label it renders actually moves. See [ConfigValue] — this is its
    // [StoreSelector] half, because there is no single key to select.
    return StoreSelector<String>(
      listenable: store,
      selector: () => _label,
      builder: (context, label) => AnchoredSearchDropdown<WeatherLocationChoice>(
        // Both halves: [_local] answers the keystroke out of the shell's own
        // table, and [_search] replaces it with the same rows plus whatever the
        // geocoder found once the request lands.
        filter: _local,
        search: _search,
        width: 280,
        rowHeight: 40,
        emptyText: 'Type a town or city',
        loadingText: 'Searching…',
        alignRight: true,
        itemBuilder: (context, choice, highlighted) =>
            _ChoiceRow(choice: choice, theme: theme),
        onSelected: _select,
        // Closes the open list when the saved location changes underneath it, the
        // guard the font field takes against a stale pick: `ConfigStore` notifies
        // every listener on every keystroke anywhere in the settings UI, and this
        // row rebuilds with them.
        closeKey: label,
        triggerBuilder: (context, open, toggle) =>
            _Trigger(label: label, open: open, onTap: toggle, theme: theme),
      ),
    );
  }
}

/// A city from the shell's table, as the coordinates the forecast API wants.
///
/// The conversion lives here rather than on [WorldCity] so `world_cities.dart`
/// stays a table the weather layer merely reads — the world-clock picker takes
/// the other half of the same row and must not drag `weather_api.dart` in.
WeatherPlace _placeFor(WorldCity city) => WeatherPlace(
      name: city.name,
      latitude: city.latitude,
      longitude: city.longitude,
      admin: city.admin,
      country: city.country,
    );

/// What makes two answers for one place the same place. The name and the
/// country, folded — not the coordinates, which differ in the third decimal
/// between two gazetteers naming the same city centre.
String _dedupeKey(WeatherPlace place) =>
    '${place.name.toLowerCase()}\u0000${place.country.toLowerCase()}';

class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.label,
    required this.open,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.controlSurface,
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(
            color: open || hovered ? theme.accent : theme.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(Symbols.location_on, size: 14, color: theme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.foreground,
                ),
              ),
            ),
            Icon(
              open ? Symbols.expand_less : Symbols.expand_more,
              size: 14,
              color: theme.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.choice, required this.theme});

  final WeatherLocationChoice choice;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    final place = choice.place;
    return Row(
      children: [
        Icon(
          place == null ? Symbols.my_location : Symbols.location_on,
          size: 14,
          color: theme.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place == null ? 'Automatic (from IP)' : place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground,
                ),
              ),
              // The disambiguating half — there are thirty Springfields, and a
              // list of them under one another with nothing to tell them apart
              // is a list of thirty identical rows.
              Text(
                place == null
                    ? 'Wherever this machine is'
                    : place.qualifier.isEmpty
                    ? ' '
                    : place.qualifier,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontFamily: theme.fontFamily,
                  color: theme.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
