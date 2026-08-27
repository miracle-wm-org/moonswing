// The Weather group's location row: automatic, or a place the user searched
// for by name.
//
// A control of its own rather than another `_ModuleSetting` in the declarative
// table, because it is the one weather setting that is not a value the user can
// type: `[modules.weather] latitude`/`longitude` are what the forecast API
// wants and a place name is what the user knows, and the only thing that turns
// one into the other is a geocoding request. The three keys are written
// together for the reason `OsdAudioTracker.seed` commits a name and a level
// together — a location is the triple, and a half-written one is a config that
// names Berlin and fetches for the prime meridian.

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/search_list.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/weather/weather_api.dart';
import 'package:graceful_shell/weather/weather_config.dart';

/// The config path each half of the location lives at.
const List<String> kWeatherLocationPath = ['modules', 'weather', 'location'];
const List<String> kWeatherLatitudePath = ['modules', 'weather', 'latitude'];
const List<String> kWeatherLongitudePath = ['modules', 'weather', 'longitude'];

/// One row of the picker: a place, or the automatic entry.
///
/// A wrapper rather than a nullable [WeatherPlace] so "detect it from my IP
/// address" is a thing the user selects rather than a thing they clear — the
/// row is always at the top of the list, and picking it is how a chosen
/// location is undone.
class WeatherLocationChoice {
  const WeatherLocationChoice.automatic() : place = null;
  const WeatherLocationChoice.at(WeatherPlace this.place);

  final WeatherPlace? place;

  bool get isAutomatic => place == null;
}

/// Searches for places by name. Injected so a widget test never opens a socket.
typedef WeatherPlaceSearch = Future<List<WeatherPlace>> Function(String query);

/// The settings row that picks where the weather is read for.
class WeatherLocationField extends StatelessWidget {
  WeatherLocationField({
    super.key,
    required this.store,
    WeatherPlaceSearch? search,
  }) : search = search ?? const OpenMeteoClient().search;

  final ConfigStore store;
  final WeatherPlaceSearch search;

  /// What the trigger reads: the saved name, or the automatic label.
  ///
  /// A saved *name* with no coordinates behind it is shown as automatic, which
  /// is what it is: [WeatherConfig.place] refuses a half-written pair, so a
  /// trigger reading only the name would claim a location the store is not
  /// fetching for.
  String get _label {
    final config = WeatherConfig(
      locationName: store.get<String>(kWeatherLocationPath) ?? '',
      latitude: store.get<num>(kWeatherLatitudePath)?.toDouble(),
      longitude: store.get<num>(kWeatherLongitudePath)?.toDouble(),
    );
    final place = config.place;
    return place == null ? 'Automatic (from IP)' : place.name;
  }

  Future<List<WeatherLocationChoice>> _search(String query) async {
    // The automatic row is always first, whatever was typed: it is how a
    // chosen location is undone, and a user who has typed three letters of a
    // city they then think better of must not have to clear the field to find
    // it again.
    final places = await search(query);
    return [
      const WeatherLocationChoice.automatic(),
      for (final place in places) WeatherLocationChoice.at(place),
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
        // No synchronous half: there is no local list of places to rank, so the
        // list opens on the automatic row alone and fills in as the user types.
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
