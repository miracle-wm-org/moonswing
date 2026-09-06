// The shell's own gazetteer: the major cities the two place pickers offer.
//
// Both pickers had a list already and neither was one a user recognises. The
// world clock's came from the IANA database, whose names are *zones* rather than
// places, so New Delhi, Mumbai, San Francisco and Boston are simply not in it.
// The weather's came from a geocoding request, which knows every one of them and
// answers none until the network does.
//
// So the table is here once, and each picker adds it to what it had.
//
// Flutter-free and I/O-free, so it is a plain unit test and `weather_api`'s own
// Flutter-free property survives importing it.
//
// Three things a change here has to keep true:
//
// - **A city carries its zone *and* its coordinates**, because the two pickers
//   want different halves of the same row. `test/world_cities_test.dart` checks
//   every zone against the live IANA database, which is the only thing standing
//   between a typo here and a city that silently never appears.
// - **A wrong row costs that row**: the clock picker drops a city whose zone the
//   database does not know rather than throwing.
// - **[aliases] is what makes a renamed city findable.** Bombay, Madras, Saigon,
//   Peking and Rangoon are what a good many people still type, and answering "no
//   matches" to a name printed on every map before 1996 reads as a broken search.

/// One place: what it is called, where it is, and which zone it keeps time in.
///
/// Not `const`-constructed, so the searchable text is folded to lower case
/// once when the table is first touched rather than on every keystroke across
/// three hundred rows — `TimeZoneName`'s trick, which is `SearchableApp`'s.
class WorldCity {
  WorldCity({
    required this.name,
    required this.country,
    required this.zone,
    required this.latitude,
    required this.longitude,
    this.admin = '',
    this.aliases = const <String>[],
  })  : _name = name.toLowerCase(),
        _aliases = [for (final alias in aliases) alias.toLowerCase()],
        _where = [admin, country]
            .where((part) => part.isNotEmpty)
            .join(' ')
            .toLowerCase();

  /// What the city is called today, in English.
  final String name;

  /// The state, province or region, where one disambiguates — Portland,
  /// Oregon from Portland, Maine. Empty everywhere a country is enough.
  final String admin;

  final String country;

  /// The IANA zone the city keeps time in, e.g. `Asia/Kolkata` for New Delhi.
  final String zone;

  final double latitude;
  final double longitude;

  /// Names the city has been widely known by. Searchable, never displayed:
  /// the row says what the place is called now.
  final List<String> aliases;

  final String _name;
  final List<String> _aliases;
  final String _where;

  /// "Springfield, Illinois, United States" — as much of it as there is.
  ///
  /// The same shape `WeatherPlace.description` writes, because this is what
  /// gets stored in `[modules.weather] location` when a city is picked here.
  String get description =>
      [name, admin, country].where((part) => part.isNotEmpty).join(', ');

  /// "Illinois, United States" — the disambiguating half, for the second line
  /// of a picker row where [name] is already the first.
  String get qualifier =>
      [admin, country].where((part) => part.isNotEmpty).join(', ');

  @override
  String toString() => 'WorldCity($description, $zone)';
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// How well a field matched, low is better — the `app_search.dart` convention
/// `time_zones.dart` also follows.
const int _kNoMatch = 1 << 30;

int _scoreField(String field, String query) {
  if (field.isEmpty) return _kNoMatch;
  if (field == query) return 0;
  if (field.startsWith(query)) return 1;
  // A word-boundary hit ("delhi" in "New Delhi") beats one mid-word ("elhi").
  if (field.contains(' $query')) return 2;
  if (field.contains(query)) return 3;
  return _kNoMatch;
}

int _scoreCity(WorldCity city, String query) {
  var best = _scoreField(city._name, query);
  // Each later field is offset so it can never beat an earlier one: a
  // substring hit on the name still ranks above an exact hit on the country,
  // or every Indian city would outrank New Delhi for "india".
  const step = 4;
  for (final alias in city._aliases) {
    final score = _scoreField(alias, query);
    if (score != _kNoMatch && score + step < best) best = score + step;
  }
  final where = _scoreField(city._where, query);
  if (where != _kNoMatch && where + step * 2 < best) best = where + step * 2;
  return best;
}

/// The cities matching [query], best first, at most [limit] of them.
///
/// An empty query answers the head of the table, ordered by how likely a row is
/// to be the one wanted rather than alphabetically: a list opening on Abu Dhabi,
/// Abidjan and Accra is a list nobody scrolls.
///
/// Ties keep table order — [List.sort] is not stable, so the index is carried
/// through the comparison rather than assumed.
List<WorldCity> rankWorldCities(
  List<WorldCity> cities,
  String query, {
  int limit = 8,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return cities.take(limit).toList();

  final scored = <(int, int, WorldCity)>[];
  for (var i = 0; i < cities.length; i++) {
    final score = _scoreCity(cities[i], normalized);
    if (score != _kNoMatch) scored.add((score, i, cities[i]));
  }

  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    if (byScore != 0) return byScore;
    return a.$2.compareTo(b.$2);
  });

  return [for (final (_, _, city) in scored.take(limit)) city];
}

// ---------------------------------------------------------------------------
// The table
// ---------------------------------------------------------------------------

/// Every city the pickers offer, roughly in order of how often one is wanted:
/// the world's best-known cities first, then the rest grouped by region.
///
/// A `final` rather than a `const`, so the fold in the constructor happens once,
/// lazily, the first time either picker is opened.
final List<WorldCity> kWorldCities = [
  // The two dozen that are wanted most often, whatever the region — an empty
  // query opens on this block.
  WorldCity(name: 'London', country: 'United Kingdom', zone: 'Europe/London', latitude: 51.51, longitude: -0.13),
  WorldCity(name: 'New York', admin: 'New York', country: 'United States', zone: 'America/New_York', latitude: 40.71, longitude: -74.01),
  WorldCity(name: 'Tokyo', country: 'Japan', zone: 'Asia/Tokyo', latitude: 35.68, longitude: 139.69),
  WorldCity(name: 'Paris', country: 'France', zone: 'Europe/Paris', latitude: 48.86, longitude: 2.35),
  WorldCity(name: 'New Delhi', admin: 'Delhi', country: 'India', zone: 'Asia/Kolkata', latitude: 28.61, longitude: 77.21),
  WorldCity(name: 'Singapore', country: 'Singapore', zone: 'Asia/Singapore', latitude: 1.35, longitude: 103.82),
  WorldCity(name: 'San Francisco', admin: 'California', country: 'United States', zone: 'America/Los_Angeles', latitude: 37.77, longitude: -122.42),
  WorldCity(name: 'Los Angeles', admin: 'California', country: 'United States', zone: 'America/Los_Angeles', latitude: 34.05, longitude: -118.24),
  WorldCity(name: 'Sydney', admin: 'New South Wales', country: 'Australia', zone: 'Australia/Sydney', latitude: -33.87, longitude: 151.21),
  WorldCity(name: 'Berlin', country: 'Germany', zone: 'Europe/Berlin', latitude: 52.52, longitude: 13.40),
  WorldCity(name: 'Dubai', country: 'United Arab Emirates', zone: 'Asia/Dubai', latitude: 25.20, longitude: 55.27),
  WorldCity(name: 'Hong Kong', country: 'Hong Kong', zone: 'Asia/Hong_Kong', latitude: 22.32, longitude: 114.17),
  WorldCity(name: 'Shanghai', country: 'China', zone: 'Asia/Shanghai', latitude: 31.23, longitude: 121.47),
  WorldCity(name: 'Beijing', country: 'China', zone: 'Asia/Shanghai', latitude: 39.90, longitude: 116.41, aliases: ['Peking']),
  WorldCity(name: 'Mumbai', admin: 'Maharashtra', country: 'India', zone: 'Asia/Kolkata', latitude: 19.08, longitude: 72.88, aliases: ['Bombay']),
  WorldCity(name: 'São Paulo', country: 'Brazil', zone: 'America/Sao_Paulo', latitude: -23.55, longitude: -46.63, aliases: ['Sao Paulo']),
  WorldCity(name: 'Toronto', admin: 'Ontario', country: 'Canada', zone: 'America/Toronto', latitude: 43.65, longitude: -79.38),
  WorldCity(name: 'Chicago', admin: 'Illinois', country: 'United States', zone: 'America/Chicago', latitude: 41.88, longitude: -87.63),
  WorldCity(name: 'Seattle', admin: 'Washington', country: 'United States', zone: 'America/Los_Angeles', latitude: 47.61, longitude: -122.33),
  WorldCity(name: 'Amsterdam', country: 'Netherlands', zone: 'Europe/Amsterdam', latitude: 52.37, longitude: 4.90),
  WorldCity(name: 'Madrid', country: 'Spain', zone: 'Europe/Madrid', latitude: 40.42, longitude: -3.70),
  WorldCity(name: 'Seoul', country: 'South Korea', zone: 'Asia/Seoul', latitude: 37.57, longitude: 126.98),
  WorldCity(name: 'Mexico City', country: 'Mexico', zone: 'America/Mexico_City', latitude: 19.43, longitude: -99.13),
  WorldCity(name: 'Moscow', country: 'Russia', zone: 'Europe/Moscow', latitude: 55.76, longitude: 37.62),

  // United States
  WorldCity(name: 'Houston', admin: 'Texas', country: 'United States', zone: 'America/Chicago', latitude: 29.76, longitude: -95.37),
  WorldCity(name: 'Phoenix', admin: 'Arizona', country: 'United States', zone: 'America/Phoenix', latitude: 33.45, longitude: -112.07),
  WorldCity(name: 'Philadelphia', admin: 'Pennsylvania', country: 'United States', zone: 'America/New_York', latitude: 39.95, longitude: -75.17),
  WorldCity(name: 'San Antonio', admin: 'Texas', country: 'United States', zone: 'America/Chicago', latitude: 29.42, longitude: -98.49),
  WorldCity(name: 'San Diego', admin: 'California', country: 'United States', zone: 'America/Los_Angeles', latitude: 32.72, longitude: -117.16),
  WorldCity(name: 'Dallas', admin: 'Texas', country: 'United States', zone: 'America/Chicago', latitude: 32.78, longitude: -96.80),
  WorldCity(name: 'Austin', admin: 'Texas', country: 'United States', zone: 'America/Chicago', latitude: 30.27, longitude: -97.74),
  WorldCity(name: 'San Jose', admin: 'California', country: 'United States', zone: 'America/Los_Angeles', latitude: 37.34, longitude: -121.89),
  WorldCity(name: 'Jacksonville', admin: 'Florida', country: 'United States', zone: 'America/New_York', latitude: 30.33, longitude: -81.66),
  WorldCity(name: 'Columbus', admin: 'Ohio', country: 'United States', zone: 'America/New_York', latitude: 39.96, longitude: -83.00),
  WorldCity(name: 'Indianapolis', admin: 'Indiana', country: 'United States', zone: 'America/Indiana/Indianapolis', latitude: 39.77, longitude: -86.16),
  WorldCity(name: 'Denver', admin: 'Colorado', country: 'United States', zone: 'America/Denver', latitude: 39.74, longitude: -104.98),
  WorldCity(name: 'Boston', admin: 'Massachusetts', country: 'United States', zone: 'America/New_York', latitude: 42.36, longitude: -71.06),
  WorldCity(name: 'Nashville', admin: 'Tennessee', country: 'United States', zone: 'America/Chicago', latitude: 36.16, longitude: -86.78),
  WorldCity(name: 'Detroit', admin: 'Michigan', country: 'United States', zone: 'America/Detroit', latitude: 42.33, longitude: -83.05),
  WorldCity(name: 'Portland', admin: 'Oregon', country: 'United States', zone: 'America/Los_Angeles', latitude: 45.52, longitude: -122.68),
  WorldCity(name: 'Las Vegas', admin: 'Nevada', country: 'United States', zone: 'America/Los_Angeles', latitude: 36.17, longitude: -115.14),
  WorldCity(name: 'Memphis', admin: 'Tennessee', country: 'United States', zone: 'America/Chicago', latitude: 35.15, longitude: -90.05),
  WorldCity(name: 'Baltimore', admin: 'Maryland', country: 'United States', zone: 'America/New_York', latitude: 39.29, longitude: -76.61),
  WorldCity(name: 'Milwaukee', admin: 'Wisconsin', country: 'United States', zone: 'America/Chicago', latitude: 43.04, longitude: -87.91),
  WorldCity(name: 'Atlanta', admin: 'Georgia', country: 'United States', zone: 'America/New_York', latitude: 33.75, longitude: -84.39),
  WorldCity(name: 'Miami', admin: 'Florida', country: 'United States', zone: 'America/New_York', latitude: 25.76, longitude: -80.19),
  WorldCity(name: 'Minneapolis', admin: 'Minnesota', country: 'United States', zone: 'America/Chicago', latitude: 44.98, longitude: -93.27),
  WorldCity(name: 'New Orleans', admin: 'Louisiana', country: 'United States', zone: 'America/Chicago', latitude: 29.95, longitude: -90.07),
  WorldCity(name: 'Salt Lake City', admin: 'Utah', country: 'United States', zone: 'America/Denver', latitude: 40.76, longitude: -111.89),
  WorldCity(name: 'Kansas City', admin: 'Missouri', country: 'United States', zone: 'America/Chicago', latitude: 39.10, longitude: -94.58),
  WorldCity(name: 'St. Louis', admin: 'Missouri', country: 'United States', zone: 'America/Chicago', latitude: 38.63, longitude: -90.20),
  WorldCity(name: 'Pittsburgh', admin: 'Pennsylvania', country: 'United States', zone: 'America/New_York', latitude: 40.44, longitude: -80.00),
  WorldCity(name: 'Cleveland', admin: 'Ohio', country: 'United States', zone: 'America/New_York', latitude: 41.50, longitude: -81.69),
  WorldCity(name: 'Charlotte', admin: 'North Carolina', country: 'United States', zone: 'America/New_York', latitude: 35.23, longitude: -80.84),
  WorldCity(name: 'Raleigh', admin: 'North Carolina', country: 'United States', zone: 'America/New_York', latitude: 35.78, longitude: -78.64),
  WorldCity(name: 'Orlando', admin: 'Florida', country: 'United States', zone: 'America/New_York', latitude: 28.54, longitude: -81.38),
  WorldCity(name: 'Tampa', admin: 'Florida', country: 'United States', zone: 'America/New_York', latitude: 27.95, longitude: -82.46),
  WorldCity(name: 'Sacramento', admin: 'California', country: 'United States', zone: 'America/Los_Angeles', latitude: 38.58, longitude: -121.49),
  WorldCity(name: 'Washington', admin: 'District of Columbia', country: 'United States', zone: 'America/New_York', latitude: 38.91, longitude: -77.04),
  WorldCity(name: 'Albuquerque', admin: 'New Mexico', country: 'United States', zone: 'America/Denver', latitude: 35.08, longitude: -106.65),
  WorldCity(name: 'Oklahoma City', admin: 'Oklahoma', country: 'United States', zone: 'America/Chicago', latitude: 35.47, longitude: -97.52),
  WorldCity(name: 'Omaha', admin: 'Nebraska', country: 'United States', zone: 'America/Chicago', latitude: 41.26, longitude: -95.94),
  WorldCity(name: 'Boise', admin: 'Idaho', country: 'United States', zone: 'America/Boise', latitude: 43.62, longitude: -116.20),
  WorldCity(name: 'Buffalo', admin: 'New York', country: 'United States', zone: 'America/New_York', latitude: 42.89, longitude: -78.88),
  WorldCity(name: 'Anchorage', admin: 'Alaska', country: 'United States', zone: 'America/Anchorage', latitude: 61.22, longitude: -149.90),
  WorldCity(name: 'Honolulu', admin: 'Hawaii', country: 'United States', zone: 'Pacific/Honolulu', latitude: 21.31, longitude: -157.86),

  // Canada
  WorldCity(name: 'Montreal', admin: 'Quebec', country: 'Canada', zone: 'America/Toronto', latitude: 45.50, longitude: -73.57),
  WorldCity(name: 'Vancouver', admin: 'British Columbia', country: 'Canada', zone: 'America/Vancouver', latitude: 49.28, longitude: -123.12),
  WorldCity(name: 'Calgary', admin: 'Alberta', country: 'Canada', zone: 'America/Edmonton', latitude: 51.05, longitude: -114.07),
  WorldCity(name: 'Edmonton', admin: 'Alberta', country: 'Canada', zone: 'America/Edmonton', latitude: 53.55, longitude: -113.49),
  WorldCity(name: 'Ottawa', admin: 'Ontario', country: 'Canada', zone: 'America/Toronto', latitude: 45.42, longitude: -75.70),
  WorldCity(name: 'Winnipeg', admin: 'Manitoba', country: 'Canada', zone: 'America/Winnipeg', latitude: 49.90, longitude: -97.14),
  WorldCity(name: 'Quebec City', admin: 'Quebec', country: 'Canada', zone: 'America/Toronto', latitude: 46.81, longitude: -71.21),
  WorldCity(name: 'Halifax', admin: 'Nova Scotia', country: 'Canada', zone: 'America/Halifax', latitude: 44.65, longitude: -63.58),

  // Mexico, Central America and the Caribbean
  WorldCity(name: 'Guadalajara', country: 'Mexico', zone: 'America/Mexico_City', latitude: 20.67, longitude: -103.35),
  WorldCity(name: 'Monterrey', country: 'Mexico', zone: 'America/Monterrey', latitude: 25.69, longitude: -100.32),
  WorldCity(name: 'Tijuana', country: 'Mexico', zone: 'America/Tijuana', latitude: 32.53, longitude: -117.02),
  WorldCity(name: 'Cancún', country: 'Mexico', zone: 'America/Cancun', latitude: 21.16, longitude: -86.85, aliases: ['Cancun']),
  WorldCity(name: 'Guatemala City', country: 'Guatemala', zone: 'America/Guatemala', latitude: 14.63, longitude: -90.51),
  WorldCity(name: 'San Salvador', country: 'El Salvador', zone: 'America/El_Salvador', latitude: 13.69, longitude: -89.19),
  WorldCity(name: 'Tegucigalpa', country: 'Honduras', zone: 'America/Tegucigalpa', latitude: 14.07, longitude: -87.19),
  WorldCity(name: 'Managua', country: 'Nicaragua', zone: 'America/Managua', latitude: 12.11, longitude: -86.24),
  WorldCity(name: 'San José', country: 'Costa Rica', zone: 'America/Costa_Rica', latitude: 9.93, longitude: -84.08, aliases: ['San Jose']),
  WorldCity(name: 'Panama City', country: 'Panama', zone: 'America/Panama', latitude: 8.98, longitude: -79.52),
  WorldCity(name: 'Havana', country: 'Cuba', zone: 'America/Havana', latitude: 23.11, longitude: -82.37),
  WorldCity(name: 'Santo Domingo', country: 'Dominican Republic', zone: 'America/Santo_Domingo', latitude: 18.49, longitude: -69.93),
  WorldCity(name: 'Kingston', country: 'Jamaica', zone: 'America/Jamaica', latitude: 18.02, longitude: -76.80),
  WorldCity(name: 'San Juan', country: 'Puerto Rico', zone: 'America/Puerto_Rico', latitude: 18.47, longitude: -66.11),
  WorldCity(name: 'Port-au-Prince', country: 'Haiti', zone: 'America/Port-au-Prince', latitude: 18.54, longitude: -72.34),
  WorldCity(name: 'Nassau', country: 'Bahamas', zone: 'America/Nassau', latitude: 25.05, longitude: -77.35),

  // South America
  WorldCity(name: 'Rio de Janeiro', country: 'Brazil', zone: 'America/Sao_Paulo', latitude: -22.91, longitude: -43.17),
  WorldCity(name: 'Brasília', country: 'Brazil', zone: 'America/Sao_Paulo', latitude: -15.79, longitude: -47.88, aliases: ['Brasilia']),
  WorldCity(name: 'Belo Horizonte', country: 'Brazil', zone: 'America/Sao_Paulo', latitude: -19.92, longitude: -43.94),
  WorldCity(name: 'Porto Alegre', country: 'Brazil', zone: 'America/Sao_Paulo', latitude: -30.03, longitude: -51.23),
  WorldCity(name: 'Salvador', country: 'Brazil', zone: 'America/Bahia', latitude: -12.97, longitude: -38.50),
  WorldCity(name: 'Recife', country: 'Brazil', zone: 'America/Recife', latitude: -8.05, longitude: -34.88),
  WorldCity(name: 'Fortaleza', country: 'Brazil', zone: 'America/Fortaleza', latitude: -3.73, longitude: -38.53),
  WorldCity(name: 'Manaus', country: 'Brazil', zone: 'America/Manaus', latitude: -3.12, longitude: -60.02),
  WorldCity(name: 'Buenos Aires', country: 'Argentina', zone: 'America/Argentina/Buenos_Aires', latitude: -34.60, longitude: -58.38),
  WorldCity(name: 'Córdoba', country: 'Argentina', zone: 'America/Argentina/Cordoba', latitude: -31.42, longitude: -64.18, aliases: ['Cordoba']),
  WorldCity(name: 'Rosario', country: 'Argentina', zone: 'America/Argentina/Cordoba', latitude: -32.95, longitude: -60.65),
  WorldCity(name: 'Santiago', country: 'Chile', zone: 'America/Santiago', latitude: -33.45, longitude: -70.67),
  WorldCity(name: 'Lima', country: 'Peru', zone: 'America/Lima', latitude: -12.05, longitude: -77.04),
  WorldCity(name: 'Bogotá', country: 'Colombia', zone: 'America/Bogota', latitude: 4.71, longitude: -74.07, aliases: ['Bogota']),
  WorldCity(name: 'Medellín', country: 'Colombia', zone: 'America/Bogota', latitude: 6.24, longitude: -75.58, aliases: ['Medellin']),
  WorldCity(name: 'Cali', country: 'Colombia', zone: 'America/Bogota', latitude: 3.45, longitude: -76.53),
  WorldCity(name: 'Caracas', country: 'Venezuela', zone: 'America/Caracas', latitude: 10.49, longitude: -66.88),
  WorldCity(name: 'Quito', country: 'Ecuador', zone: 'America/Guayaquil', latitude: -0.18, longitude: -78.47),
  WorldCity(name: 'Guayaquil', country: 'Ecuador', zone: 'America/Guayaquil', latitude: -2.17, longitude: -79.92),
  WorldCity(name: 'La Paz', country: 'Bolivia', zone: 'America/La_Paz', latitude: -16.50, longitude: -68.15),
  WorldCity(name: 'Asunción', country: 'Paraguay', zone: 'America/Asuncion', latitude: -25.28, longitude: -57.64, aliases: ['Asuncion']),
  WorldCity(name: 'Montevideo', country: 'Uruguay', zone: 'America/Montevideo', latitude: -34.90, longitude: -56.16),

  // Europe
  WorldCity(name: 'Manchester', country: 'United Kingdom', zone: 'Europe/London', latitude: 53.48, longitude: -2.24),
  WorldCity(name: 'Birmingham', country: 'United Kingdom', zone: 'Europe/London', latitude: 52.49, longitude: -1.89),
  WorldCity(name: 'Glasgow', country: 'United Kingdom', zone: 'Europe/London', latitude: 55.86, longitude: -4.25),
  WorldCity(name: 'Edinburgh', country: 'United Kingdom', zone: 'Europe/London', latitude: 55.95, longitude: -3.19),
  WorldCity(name: 'Leeds', country: 'United Kingdom', zone: 'Europe/London', latitude: 53.80, longitude: -1.55),
  WorldCity(name: 'Bristol', country: 'United Kingdom', zone: 'Europe/London', latitude: 51.45, longitude: -2.59),
  WorldCity(name: 'Belfast', country: 'United Kingdom', zone: 'Europe/London', latitude: 54.60, longitude: -5.93),
  WorldCity(name: 'Cardiff', country: 'United Kingdom', zone: 'Europe/London', latitude: 51.48, longitude: -3.18),
  WorldCity(name: 'Cork', country: 'Ireland', zone: 'Europe/Dublin', latitude: 51.90, longitude: -8.47),
  WorldCity(name: 'Marseille', country: 'France', zone: 'Europe/Paris', latitude: 43.30, longitude: 5.37),
  WorldCity(name: 'Lyon', country: 'France', zone: 'Europe/Paris', latitude: 45.76, longitude: 4.84),
  WorldCity(name: 'Toulouse', country: 'France', zone: 'Europe/Paris', latitude: 43.60, longitude: 1.44),
  WorldCity(name: 'Nice', country: 'France', zone: 'Europe/Paris', latitude: 43.70, longitude: 7.27),
  WorldCity(name: 'Bordeaux', country: 'France', zone: 'Europe/Paris', latitude: 44.84, longitude: -0.58),
  WorldCity(name: 'Barcelona', country: 'Spain', zone: 'Europe/Madrid', latitude: 41.39, longitude: 2.17),
  WorldCity(name: 'Valencia', country: 'Spain', zone: 'Europe/Madrid', latitude: 39.47, longitude: -0.38),
  WorldCity(name: 'Seville', country: 'Spain', zone: 'Europe/Madrid', latitude: 37.39, longitude: -5.98, aliases: ['Sevilla']),
  WorldCity(name: 'Bilbao', country: 'Spain', zone: 'Europe/Madrid', latitude: 43.26, longitude: -2.93),
  WorldCity(name: 'Palma', admin: 'Mallorca', country: 'Spain', zone: 'Europe/Madrid', latitude: 39.57, longitude: 2.65),
  WorldCity(name: 'Porto', country: 'Portugal', zone: 'Europe/Lisbon', latitude: 41.15, longitude: -8.61, aliases: ['Oporto']),
  WorldCity(name: 'Munich', country: 'Germany', zone: 'Europe/Berlin', latitude: 48.14, longitude: 11.58, aliases: ['München', 'Muenchen']),
  WorldCity(name: 'Hamburg', country: 'Germany', zone: 'Europe/Berlin', latitude: 53.55, longitude: 9.99),
  WorldCity(name: 'Frankfurt', country: 'Germany', zone: 'Europe/Berlin', latitude: 50.11, longitude: 8.68),
  WorldCity(name: 'Cologne', country: 'Germany', zone: 'Europe/Berlin', latitude: 50.94, longitude: 6.96, aliases: ['Köln', 'Koeln']),
  WorldCity(name: 'Stuttgart', country: 'Germany', zone: 'Europe/Berlin', latitude: 48.78, longitude: 9.18),
  WorldCity(name: 'Düsseldorf', country: 'Germany', zone: 'Europe/Berlin', latitude: 51.23, longitude: 6.78, aliases: ['Dusseldorf', 'Duesseldorf']),
  WorldCity(name: 'Leipzig', country: 'Germany', zone: 'Europe/Berlin', latitude: 51.34, longitude: 12.37),
  WorldCity(name: 'Rotterdam', country: 'Netherlands', zone: 'Europe/Amsterdam', latitude: 51.92, longitude: 4.48),
  WorldCity(name: 'The Hague', country: 'Netherlands', zone: 'Europe/Amsterdam', latitude: 52.08, longitude: 4.31, aliases: ['Den Haag']),
  WorldCity(name: 'Utrecht', country: 'Netherlands', zone: 'Europe/Amsterdam', latitude: 52.09, longitude: 5.12),
  WorldCity(name: 'Brussels', country: 'Belgium', zone: 'Europe/Brussels', latitude: 50.85, longitude: 4.35, aliases: ['Bruxelles', 'Brussel']),
  WorldCity(name: 'Antwerp', country: 'Belgium', zone: 'Europe/Brussels', latitude: 51.22, longitude: 4.40, aliases: ['Antwerpen']),
  WorldCity(name: 'Luxembourg', country: 'Luxembourg', zone: 'Europe/Luxembourg', latitude: 49.61, longitude: 6.13),
  WorldCity(name: 'Zurich', country: 'Switzerland', zone: 'Europe/Zurich', latitude: 47.38, longitude: 8.54, aliases: ['Zürich']),
  WorldCity(name: 'Geneva', country: 'Switzerland', zone: 'Europe/Zurich', latitude: 46.20, longitude: 6.14, aliases: ['Genève', 'Genf']),
  WorldCity(name: 'Basel', country: 'Switzerland', zone: 'Europe/Zurich', latitude: 47.56, longitude: 7.59),
  WorldCity(name: 'Bern', country: 'Switzerland', zone: 'Europe/Zurich', latitude: 46.95, longitude: 7.45),
  WorldCity(name: 'Vienna', country: 'Austria', zone: 'Europe/Vienna', latitude: 48.21, longitude: 16.37, aliases: ['Wien']),
  WorldCity(name: 'Salzburg', country: 'Austria', zone: 'Europe/Vienna', latitude: 47.81, longitude: 13.06),
  WorldCity(name: 'Rome', country: 'Italy', zone: 'Europe/Rome', latitude: 41.90, longitude: 12.50, aliases: ['Roma']),
  WorldCity(name: 'Milan', country: 'Italy', zone: 'Europe/Rome', latitude: 45.46, longitude: 9.19, aliases: ['Milano']),
  WorldCity(name: 'Naples', country: 'Italy', zone: 'Europe/Rome', latitude: 40.85, longitude: 14.27, aliases: ['Napoli']),
  WorldCity(name: 'Turin', country: 'Italy', zone: 'Europe/Rome', latitude: 45.07, longitude: 7.69, aliases: ['Torino']),
  WorldCity(name: 'Florence', country: 'Italy', zone: 'Europe/Rome', latitude: 43.77, longitude: 11.26, aliases: ['Firenze']),
  WorldCity(name: 'Venice', country: 'Italy', zone: 'Europe/Rome', latitude: 45.44, longitude: 12.32, aliases: ['Venezia']),
  WorldCity(name: 'Bologna', country: 'Italy', zone: 'Europe/Rome', latitude: 44.49, longitude: 11.34),
  WorldCity(name: 'Copenhagen', country: 'Denmark', zone: 'Europe/Copenhagen', latitude: 55.68, longitude: 12.57, aliases: ['København', 'Kobenhavn']),
  WorldCity(name: 'Stockholm', country: 'Sweden', zone: 'Europe/Stockholm', latitude: 59.33, longitude: 18.07),
  WorldCity(name: 'Gothenburg', country: 'Sweden', zone: 'Europe/Stockholm', latitude: 57.71, longitude: 11.97, aliases: ['Göteborg', 'Goteborg']),
  WorldCity(name: 'Oslo', country: 'Norway', zone: 'Europe/Oslo', latitude: 59.91, longitude: 10.75),
  WorldCity(name: 'Bergen', country: 'Norway', zone: 'Europe/Oslo', latitude: 60.39, longitude: 5.32),
  WorldCity(name: 'Helsinki', country: 'Finland', zone: 'Europe/Helsinki', latitude: 60.17, longitude: 24.94),
  WorldCity(name: 'Reykjavík', country: 'Iceland', zone: 'Atlantic/Reykjavik', latitude: 64.15, longitude: -21.94, aliases: ['Reykjavik']),
  WorldCity(name: 'Warsaw', country: 'Poland', zone: 'Europe/Warsaw', latitude: 52.23, longitude: 21.01, aliases: ['Warszawa']),
  WorldCity(name: 'Kraków', country: 'Poland', zone: 'Europe/Warsaw', latitude: 50.06, longitude: 19.94, aliases: ['Krakow', 'Cracow']),
  WorldCity(name: 'Gdańsk', country: 'Poland', zone: 'Europe/Warsaw', latitude: 54.35, longitude: 18.65, aliases: ['Gdansk']),
  WorldCity(name: 'Prague', country: 'Czechia', zone: 'Europe/Prague', latitude: 50.08, longitude: 14.44, aliases: ['Praha', 'Czech Republic']),
  WorldCity(name: 'Bratislava', country: 'Slovakia', zone: 'Europe/Bratislava', latitude: 48.15, longitude: 17.11),
  WorldCity(name: 'Budapest', country: 'Hungary', zone: 'Europe/Budapest', latitude: 47.50, longitude: 19.04),
  WorldCity(name: 'Bucharest', country: 'Romania', zone: 'Europe/Bucharest', latitude: 44.43, longitude: 26.11, aliases: ['București', 'Bucuresti']),
  WorldCity(name: 'Sofia', country: 'Bulgaria', zone: 'Europe/Sofia', latitude: 42.70, longitude: 23.32),
  WorldCity(name: 'Belgrade', country: 'Serbia', zone: 'Europe/Belgrade', latitude: 44.79, longitude: 20.45, aliases: ['Beograd']),
  WorldCity(name: 'Zagreb', country: 'Croatia', zone: 'Europe/Zagreb', latitude: 45.81, longitude: 15.98),
  WorldCity(name: 'Ljubljana', country: 'Slovenia', zone: 'Europe/Ljubljana', latitude: 46.06, longitude: 14.51),
  WorldCity(name: 'Sarajevo', country: 'Bosnia and Herzegovina', zone: 'Europe/Sarajevo', latitude: 43.86, longitude: 18.41),
  WorldCity(name: 'Skopje', country: 'North Macedonia', zone: 'Europe/Skopje', latitude: 42.00, longitude: 21.43),
  WorldCity(name: 'Tirana', country: 'Albania', zone: 'Europe/Tirane', latitude: 41.33, longitude: 19.82, aliases: ['Tirane']),
  WorldCity(name: 'Athens', country: 'Greece', zone: 'Europe/Athens', latitude: 37.98, longitude: 23.73, aliases: ['Athina']),
  WorldCity(name: 'Thessaloniki', country: 'Greece', zone: 'Europe/Athens', latitude: 40.64, longitude: 22.94),
  WorldCity(name: 'Istanbul', country: 'Türkiye', zone: 'Europe/Istanbul', latitude: 41.01, longitude: 28.98, aliases: ['Turkey', 'Constantinople']),
  WorldCity(name: 'Ankara', country: 'Türkiye', zone: 'Europe/Istanbul', latitude: 39.93, longitude: 32.86, aliases: ['Turkey']),
  WorldCity(name: 'Izmir', country: 'Türkiye', zone: 'Europe/Istanbul', latitude: 38.42, longitude: 27.14, aliases: ['Turkey', 'İzmir']),
  WorldCity(name: 'Antalya', country: 'Türkiye', zone: 'Europe/Istanbul', latitude: 36.90, longitude: 30.71, aliases: ['Turkey']),
  WorldCity(name: 'Kyiv', country: 'Ukraine', zone: 'Europe/Kyiv', latitude: 50.45, longitude: 30.52, aliases: ['Kiev']),
  WorldCity(name: 'Lviv', country: 'Ukraine', zone: 'Europe/Kyiv', latitude: 49.84, longitude: 24.03),
  WorldCity(name: 'Odesa', country: 'Ukraine', zone: 'Europe/Kyiv', latitude: 46.48, longitude: 30.73, aliases: ['Odessa']),
  WorldCity(name: 'Minsk', country: 'Belarus', zone: 'Europe/Minsk', latitude: 53.90, longitude: 27.57),
  WorldCity(name: 'Saint Petersburg', country: 'Russia', zone: 'Europe/Moscow', latitude: 59.94, longitude: 30.31, aliases: ['St Petersburg', 'Leningrad']),
  WorldCity(name: 'Kazan', country: 'Russia', zone: 'Europe/Moscow', latitude: 55.79, longitude: 49.12),
  WorldCity(name: 'Yekaterinburg', country: 'Russia', zone: 'Asia/Yekaterinburg', latitude: 56.84, longitude: 60.65, aliases: ['Ekaterinburg']),
  WorldCity(name: 'Novosibirsk', country: 'Russia', zone: 'Asia/Novosibirsk', latitude: 55.03, longitude: 82.92),
  WorldCity(name: 'Vladivostok', country: 'Russia', zone: 'Asia/Vladivostok', latitude: 43.12, longitude: 131.89),
  WorldCity(name: 'Riga', country: 'Latvia', zone: 'Europe/Riga', latitude: 56.95, longitude: 24.11),
  WorldCity(name: 'Vilnius', country: 'Lithuania', zone: 'Europe/Vilnius', latitude: 54.69, longitude: 25.28),
  WorldCity(name: 'Tallinn', country: 'Estonia', zone: 'Europe/Tallinn', latitude: 59.44, longitude: 24.75),
  WorldCity(name: 'Chișinău', country: 'Moldova', zone: 'Europe/Chisinau', latitude: 47.01, longitude: 28.86, aliases: ['Chisinau', 'Kishinev']),
  WorldCity(name: 'Valletta', country: 'Malta', zone: 'Europe/Malta', latitude: 35.90, longitude: 14.51),
  WorldCity(name: 'Nicosia', country: 'Cyprus', zone: 'Asia/Nicosia', latitude: 35.19, longitude: 33.38),
  WorldCity(name: 'Monaco', country: 'Monaco', zone: 'Europe/Monaco', latitude: 43.74, longitude: 7.42),
  WorldCity(name: 'Andorra la Vella', country: 'Andorra', zone: 'Europe/Andorra', latitude: 42.51, longitude: 1.52),

  // The Middle East and the Caucasus
  WorldCity(name: 'Abu Dhabi', country: 'United Arab Emirates', zone: 'Asia/Dubai', latitude: 24.45, longitude: 54.38),
  WorldCity(name: 'Doha', country: 'Qatar', zone: 'Asia/Qatar', latitude: 25.29, longitude: 51.53),
  WorldCity(name: 'Riyadh', country: 'Saudi Arabia', zone: 'Asia/Riyadh', latitude: 24.71, longitude: 46.68),
  WorldCity(name: 'Jeddah', country: 'Saudi Arabia', zone: 'Asia/Riyadh', latitude: 21.49, longitude: 39.19, aliases: ['Jiddah']),
  WorldCity(name: 'Mecca', country: 'Saudi Arabia', zone: 'Asia/Riyadh', latitude: 21.39, longitude: 39.86, aliases: ['Makkah']),
  WorldCity(name: 'Kuwait City', country: 'Kuwait', zone: 'Asia/Kuwait', latitude: 29.38, longitude: 47.99),
  WorldCity(name: 'Manama', country: 'Bahrain', zone: 'Asia/Bahrain', latitude: 26.23, longitude: 50.59),
  WorldCity(name: 'Muscat', country: 'Oman', zone: 'Asia/Muscat', latitude: 23.59, longitude: 58.41),
  WorldCity(name: 'Tehran', country: 'Iran', zone: 'Asia/Tehran', latitude: 35.69, longitude: 51.39, aliases: ['Teheran']),
  WorldCity(name: 'Baghdad', country: 'Iraq', zone: 'Asia/Baghdad', latitude: 33.31, longitude: 44.37),
  WorldCity(name: 'Amman', country: 'Jordan', zone: 'Asia/Amman', latitude: 31.95, longitude: 35.93),
  WorldCity(name: 'Beirut', country: 'Lebanon', zone: 'Asia/Beirut', latitude: 33.89, longitude: 35.50),
  WorldCity(name: 'Damascus', country: 'Syria', zone: 'Asia/Damascus', latitude: 33.51, longitude: 36.29),
  WorldCity(name: 'Jerusalem', country: 'Israel', zone: 'Asia/Jerusalem', latitude: 31.78, longitude: 35.22),
  WorldCity(name: 'Tel Aviv', country: 'Israel', zone: 'Asia/Jerusalem', latitude: 32.08, longitude: 34.78),
  WorldCity(name: 'Baku', country: 'Azerbaijan', zone: 'Asia/Baku', latitude: 40.41, longitude: 49.87),
  WorldCity(name: 'Tbilisi', country: 'Georgia', zone: 'Asia/Tbilisi', latitude: 41.72, longitude: 44.79),
  WorldCity(name: 'Yerevan', country: 'Armenia', zone: 'Asia/Yerevan', latitude: 40.18, longitude: 44.51),

  // Africa
  WorldCity(name: 'Cairo', country: 'Egypt', zone: 'Africa/Cairo', latitude: 30.04, longitude: 31.24),
  WorldCity(name: 'Alexandria', country: 'Egypt', zone: 'Africa/Cairo', latitude: 31.20, longitude: 29.92),
  WorldCity(name: 'Lagos', country: 'Nigeria', zone: 'Africa/Lagos', latitude: 6.52, longitude: 3.38),
  WorldCity(name: 'Abuja', country: 'Nigeria', zone: 'Africa/Lagos', latitude: 9.06, longitude: 7.49),
  WorldCity(name: 'Kano', country: 'Nigeria', zone: 'Africa/Lagos', latitude: 12.00, longitude: 8.52),
  WorldCity(name: 'Accra', country: 'Ghana', zone: 'Africa/Accra', latitude: 5.60, longitude: -0.19),
  WorldCity(name: 'Abidjan', country: "Côte d'Ivoire", zone: 'Africa/Abidjan', latitude: 5.36, longitude: -4.01, aliases: ['Ivory Coast']),
  WorldCity(name: 'Dakar', country: 'Senegal', zone: 'Africa/Dakar', latitude: 14.72, longitude: -17.47),
  WorldCity(name: 'Casablanca', country: 'Morocco', zone: 'Africa/Casablanca', latitude: 33.57, longitude: -7.59),
  WorldCity(name: 'Rabat', country: 'Morocco', zone: 'Africa/Casablanca', latitude: 34.02, longitude: -6.84),
  WorldCity(name: 'Marrakesh', country: 'Morocco', zone: 'Africa/Casablanca', latitude: 31.63, longitude: -7.99, aliases: ['Marrakech']),
  WorldCity(name: 'Algiers', country: 'Algeria', zone: 'Africa/Algiers', latitude: 36.75, longitude: 3.06),
  WorldCity(name: 'Tunis', country: 'Tunisia', zone: 'Africa/Tunis', latitude: 36.81, longitude: 10.18),
  WorldCity(name: 'Tripoli', country: 'Libya', zone: 'Africa/Tripoli', latitude: 32.89, longitude: 13.19),
  WorldCity(name: 'Khartoum', country: 'Sudan', zone: 'Africa/Khartoum', latitude: 15.50, longitude: 32.56),
  WorldCity(name: 'Addis Ababa', country: 'Ethiopia', zone: 'Africa/Addis_Ababa', latitude: 9.03, longitude: 38.74),
  WorldCity(name: 'Nairobi', country: 'Kenya', zone: 'Africa/Nairobi', latitude: -1.29, longitude: 36.82),
  WorldCity(name: 'Mombasa', country: 'Kenya', zone: 'Africa/Nairobi', latitude: -4.04, longitude: 39.67),
  WorldCity(name: 'Kampala', country: 'Uganda', zone: 'Africa/Kampala', latitude: 0.35, longitude: 32.58),
  WorldCity(name: 'Dar es Salaam', country: 'Tanzania', zone: 'Africa/Dar_es_Salaam', latitude: -6.79, longitude: 39.21),
  WorldCity(name: 'Kigali', country: 'Rwanda', zone: 'Africa/Kigali', latitude: -1.94, longitude: 30.06),
  WorldCity(name: 'Kinshasa', country: 'DR Congo', zone: 'Africa/Kinshasa', latitude: -4.32, longitude: 15.31, aliases: ['Congo']),
  WorldCity(name: 'Luanda', country: 'Angola', zone: 'Africa/Luanda', latitude: -8.84, longitude: 13.23),
  WorldCity(name: 'Lusaka', country: 'Zambia', zone: 'Africa/Lusaka', latitude: -15.42, longitude: 28.28),
  WorldCity(name: 'Harare', country: 'Zimbabwe', zone: 'Africa/Harare', latitude: -17.83, longitude: 31.05),
  WorldCity(name: 'Maputo', country: 'Mozambique', zone: 'Africa/Maputo', latitude: -25.97, longitude: 32.57),
  WorldCity(name: 'Johannesburg', country: 'South Africa', zone: 'Africa/Johannesburg', latitude: -26.20, longitude: 28.05),
  WorldCity(name: 'Cape Town', country: 'South Africa', zone: 'Africa/Johannesburg', latitude: -33.92, longitude: 18.42),
  WorldCity(name: 'Durban', country: 'South Africa', zone: 'Africa/Johannesburg', latitude: -29.86, longitude: 31.02),
  WorldCity(name: 'Pretoria', country: 'South Africa', zone: 'Africa/Johannesburg', latitude: -25.75, longitude: 28.19),
  WorldCity(name: 'Windhoek', country: 'Namibia', zone: 'Africa/Windhoek', latitude: -22.56, longitude: 17.08),
  WorldCity(name: 'Gaborone', country: 'Botswana', zone: 'Africa/Gaborone', latitude: -24.65, longitude: 25.91),
  WorldCity(name: 'Antananarivo', country: 'Madagascar', zone: 'Indian/Antananarivo', latitude: -18.88, longitude: 47.51),
  WorldCity(name: 'Port Louis', country: 'Mauritius', zone: 'Indian/Mauritius', latitude: -20.16, longitude: 57.50),

  // South Asia
  WorldCity(name: 'Bengaluru', admin: 'Karnataka', country: 'India', zone: 'Asia/Kolkata', latitude: 12.97, longitude: 77.59, aliases: ['Bangalore']),
  WorldCity(name: 'Chennai', admin: 'Tamil Nadu', country: 'India', zone: 'Asia/Kolkata', latitude: 13.08, longitude: 80.27, aliases: ['Madras']),
  WorldCity(name: 'Kolkata', admin: 'West Bengal', country: 'India', zone: 'Asia/Kolkata', latitude: 22.57, longitude: 88.36, aliases: ['Calcutta']),
  WorldCity(name: 'Hyderabad', admin: 'Telangana', country: 'India', zone: 'Asia/Kolkata', latitude: 17.39, longitude: 78.49),
  WorldCity(name: 'Pune', admin: 'Maharashtra', country: 'India', zone: 'Asia/Kolkata', latitude: 18.52, longitude: 73.86, aliases: ['Poona']),
  WorldCity(name: 'Ahmedabad', admin: 'Gujarat', country: 'India', zone: 'Asia/Kolkata', latitude: 23.02, longitude: 72.57),
  WorldCity(name: 'Jaipur', admin: 'Rajasthan', country: 'India', zone: 'Asia/Kolkata', latitude: 26.91, longitude: 75.79),
  WorldCity(name: 'Surat', admin: 'Gujarat', country: 'India', zone: 'Asia/Kolkata', latitude: 21.17, longitude: 72.83),
  WorldCity(name: 'Lucknow', admin: 'Uttar Pradesh', country: 'India', zone: 'Asia/Kolkata', latitude: 26.85, longitude: 80.95),
  WorldCity(name: 'Kanpur', admin: 'Uttar Pradesh', country: 'India', zone: 'Asia/Kolkata', latitude: 26.45, longitude: 80.33),
  WorldCity(name: 'Nagpur', admin: 'Maharashtra', country: 'India', zone: 'Asia/Kolkata', latitude: 21.15, longitude: 79.09),
  WorldCity(name: 'Kochi', admin: 'Kerala', country: 'India', zone: 'Asia/Kolkata', latitude: 9.93, longitude: 76.27, aliases: ['Cochin']),
  WorldCity(name: 'Chandigarh', country: 'India', zone: 'Asia/Kolkata', latitude: 30.73, longitude: 76.78),
  WorldCity(name: 'Karachi', country: 'Pakistan', zone: 'Asia/Karachi', latitude: 24.86, longitude: 67.01),
  WorldCity(name: 'Lahore', country: 'Pakistan', zone: 'Asia/Karachi', latitude: 31.55, longitude: 74.34),
  WorldCity(name: 'Islamabad', country: 'Pakistan', zone: 'Asia/Karachi', latitude: 33.68, longitude: 73.05),
  WorldCity(name: 'Faisalabad', country: 'Pakistan', zone: 'Asia/Karachi', latitude: 31.42, longitude: 73.08),
  WorldCity(name: 'Dhaka', country: 'Bangladesh', zone: 'Asia/Dhaka', latitude: 23.81, longitude: 90.41, aliases: ['Dacca']),
  WorldCity(name: 'Chattogram', country: 'Bangladesh', zone: 'Asia/Dhaka', latitude: 22.36, longitude: 91.78, aliases: ['Chittagong']),
  WorldCity(name: 'Colombo', country: 'Sri Lanka', zone: 'Asia/Colombo', latitude: 6.93, longitude: 79.86),
  WorldCity(name: 'Kathmandu', country: 'Nepal', zone: 'Asia/Kathmandu', latitude: 27.72, longitude: 85.32),
  WorldCity(name: 'Thimphu', country: 'Bhutan', zone: 'Asia/Thimphu', latitude: 27.47, longitude: 89.64),
  WorldCity(name: 'Kabul', country: 'Afghanistan', zone: 'Asia/Kabul', latitude: 34.53, longitude: 69.17),
  WorldCity(name: 'Malé', country: 'Maldives', zone: 'Indian/Maldives', latitude: 4.18, longitude: 73.51, aliases: ['Male']),

  // Central Asia
  WorldCity(name: 'Tashkent', country: 'Uzbekistan', zone: 'Asia/Tashkent', latitude: 41.30, longitude: 69.24),
  WorldCity(name: 'Almaty', country: 'Kazakhstan', zone: 'Asia/Almaty', latitude: 43.24, longitude: 76.89),
  WorldCity(name: 'Astana', country: 'Kazakhstan', zone: 'Asia/Almaty', latitude: 51.17, longitude: 71.45, aliases: ['Nur-Sultan', 'Akmola']),
  WorldCity(name: 'Bishkek', country: 'Kyrgyzstan', zone: 'Asia/Bishkek', latitude: 42.87, longitude: 74.59),
  WorldCity(name: 'Dushanbe', country: 'Tajikistan', zone: 'Asia/Dushanbe', latitude: 38.56, longitude: 68.79),
  WorldCity(name: 'Ashgabat', country: 'Turkmenistan', zone: 'Asia/Ashgabat', latitude: 37.95, longitude: 58.38),

  // East Asia
  WorldCity(name: 'Osaka', country: 'Japan', zone: 'Asia/Tokyo', latitude: 34.69, longitude: 135.50),
  WorldCity(name: 'Kyoto', country: 'Japan', zone: 'Asia/Tokyo', latitude: 35.01, longitude: 135.77),
  WorldCity(name: 'Yokohama', country: 'Japan', zone: 'Asia/Tokyo', latitude: 35.44, longitude: 139.64),
  WorldCity(name: 'Nagoya', country: 'Japan', zone: 'Asia/Tokyo', latitude: 35.18, longitude: 136.91),
  WorldCity(name: 'Sapporo', country: 'Japan', zone: 'Asia/Tokyo', latitude: 43.06, longitude: 141.35),
  WorldCity(name: 'Fukuoka', country: 'Japan', zone: 'Asia/Tokyo', latitude: 33.59, longitude: 130.40),
  WorldCity(name: 'Busan', country: 'South Korea', zone: 'Asia/Seoul', latitude: 35.18, longitude: 129.08, aliases: ['Pusan']),
  WorldCity(name: 'Incheon', country: 'South Korea', zone: 'Asia/Seoul', latitude: 37.46, longitude: 126.71),
  WorldCity(name: 'Pyongyang', country: 'North Korea', zone: 'Asia/Pyongyang', latitude: 39.02, longitude: 125.75),
  WorldCity(name: 'Guangzhou', country: 'China', zone: 'Asia/Shanghai', latitude: 23.13, longitude: 113.26, aliases: ['Canton']),
  WorldCity(name: 'Shenzhen', country: 'China', zone: 'Asia/Shanghai', latitude: 22.54, longitude: 114.06),
  WorldCity(name: 'Chengdu', country: 'China', zone: 'Asia/Shanghai', latitude: 30.57, longitude: 104.07),
  WorldCity(name: 'Chongqing', country: 'China', zone: 'Asia/Shanghai', latitude: 29.56, longitude: 106.55),
  WorldCity(name: 'Tianjin', country: 'China', zone: 'Asia/Shanghai', latitude: 39.34, longitude: 117.36),
  WorldCity(name: 'Wuhan', country: 'China', zone: 'Asia/Shanghai', latitude: 30.59, longitude: 114.31),
  WorldCity(name: "Xi'an", country: 'China', zone: 'Asia/Shanghai', latitude: 34.34, longitude: 108.94, aliases: ['Xian']),
  WorldCity(name: 'Hangzhou', country: 'China', zone: 'Asia/Shanghai', latitude: 30.27, longitude: 120.16),
  WorldCity(name: 'Nanjing', country: 'China', zone: 'Asia/Shanghai', latitude: 32.06, longitude: 118.80),
  WorldCity(name: 'Shenyang', country: 'China', zone: 'Asia/Shanghai', latitude: 41.81, longitude: 123.43),
  WorldCity(name: 'Qingdao', country: 'China', zone: 'Asia/Shanghai', latitude: 36.07, longitude: 120.38),
  WorldCity(name: 'Ürümqi', country: 'China', zone: 'Asia/Urumqi', latitude: 43.83, longitude: 87.62, aliases: ['Urumqi']),
  WorldCity(name: 'Macau', country: 'Macau', zone: 'Asia/Macau', latitude: 22.20, longitude: 113.55, aliases: ['Macao']),
  WorldCity(name: 'Taipei', country: 'Taiwan', zone: 'Asia/Taipei', latitude: 25.03, longitude: 121.57),
  WorldCity(name: 'Kaohsiung', country: 'Taiwan', zone: 'Asia/Taipei', latitude: 22.63, longitude: 120.30),
  WorldCity(name: 'Ulaanbaatar', country: 'Mongolia', zone: 'Asia/Ulaanbaatar', latitude: 47.89, longitude: 106.91, aliases: ['Ulan Bator']),

  // South-East Asia
  WorldCity(name: 'Bangkok', country: 'Thailand', zone: 'Asia/Bangkok', latitude: 13.76, longitude: 100.50),
  WorldCity(name: 'Chiang Mai', country: 'Thailand', zone: 'Asia/Bangkok', latitude: 18.79, longitude: 98.99),
  WorldCity(name: 'Phuket', country: 'Thailand', zone: 'Asia/Bangkok', latitude: 7.88, longitude: 98.39),
  WorldCity(name: 'Kuala Lumpur', country: 'Malaysia', zone: 'Asia/Kuala_Lumpur', latitude: 3.14, longitude: 101.69),
  WorldCity(name: 'George Town', admin: 'Penang', country: 'Malaysia', zone: 'Asia/Kuala_Lumpur', latitude: 5.41, longitude: 100.34, aliases: ['Penang']),
  WorldCity(name: 'Jakarta', country: 'Indonesia', zone: 'Asia/Jakarta', latitude: -6.21, longitude: 106.85),
  WorldCity(name: 'Surabaya', country: 'Indonesia', zone: 'Asia/Jakarta', latitude: -7.25, longitude: 112.75),
  WorldCity(name: 'Bandung', country: 'Indonesia', zone: 'Asia/Jakarta', latitude: -6.91, longitude: 107.61),
  WorldCity(name: 'Denpasar', admin: 'Bali', country: 'Indonesia', zone: 'Asia/Makassar', latitude: -8.65, longitude: 115.22, aliases: ['Bali']),
  WorldCity(name: 'Manila', country: 'Philippines', zone: 'Asia/Manila', latitude: 14.60, longitude: 120.98),
  WorldCity(name: 'Cebu City', country: 'Philippines', zone: 'Asia/Manila', latitude: 10.32, longitude: 123.89),
  WorldCity(name: 'Hanoi', country: 'Vietnam', zone: 'Asia/Ho_Chi_Minh', latitude: 21.03, longitude: 105.85, aliases: ['Ha Noi']),
  WorldCity(name: 'Ho Chi Minh City', country: 'Vietnam', zone: 'Asia/Ho_Chi_Minh', latitude: 10.82, longitude: 106.63, aliases: ['Saigon']),
  WorldCity(name: 'Phnom Penh', country: 'Cambodia', zone: 'Asia/Phnom_Penh', latitude: 11.56, longitude: 104.92),
  WorldCity(name: 'Vientiane', country: 'Laos', zone: 'Asia/Vientiane', latitude: 17.97, longitude: 102.63),
  WorldCity(name: 'Yangon', country: 'Myanmar', zone: 'Asia/Yangon', latitude: 16.87, longitude: 96.20, aliases: ['Rangoon', 'Burma']),
  WorldCity(name: 'Naypyidaw', country: 'Myanmar', zone: 'Asia/Yangon', latitude: 19.75, longitude: 96.10, aliases: ['Burma']),
  WorldCity(name: 'Bandar Seri Begawan', country: 'Brunei', zone: 'Asia/Brunei', latitude: 4.89, longitude: 114.94),

  // Oceania
  WorldCity(name: 'Melbourne', admin: 'Victoria', country: 'Australia', zone: 'Australia/Melbourne', latitude: -37.81, longitude: 144.96),
  WorldCity(name: 'Brisbane', admin: 'Queensland', country: 'Australia', zone: 'Australia/Brisbane', latitude: -27.47, longitude: 153.03),
  WorldCity(name: 'Perth', admin: 'Western Australia', country: 'Australia', zone: 'Australia/Perth', latitude: -31.95, longitude: 115.86),
  WorldCity(name: 'Adelaide', admin: 'South Australia', country: 'Australia', zone: 'Australia/Adelaide', latitude: -34.93, longitude: 138.60),
  WorldCity(name: 'Canberra', country: 'Australia', zone: 'Australia/Sydney', latitude: -35.28, longitude: 149.13),
  WorldCity(name: 'Hobart', admin: 'Tasmania', country: 'Australia', zone: 'Australia/Hobart', latitude: -42.88, longitude: 147.33),
  WorldCity(name: 'Darwin', admin: 'Northern Territory', country: 'Australia', zone: 'Australia/Darwin', latitude: -12.46, longitude: 130.84),
  WorldCity(name: 'Gold Coast', admin: 'Queensland', country: 'Australia', zone: 'Australia/Brisbane', latitude: -28.02, longitude: 153.40),
  WorldCity(name: 'Auckland', country: 'New Zealand', zone: 'Pacific/Auckland', latitude: -36.85, longitude: 174.76),
  WorldCity(name: 'Wellington', country: 'New Zealand', zone: 'Pacific/Auckland', latitude: -41.29, longitude: 174.78),
  WorldCity(name: 'Christchurch', country: 'New Zealand', zone: 'Pacific/Auckland', latitude: -43.53, longitude: 172.64),
  WorldCity(name: 'Suva', country: 'Fiji', zone: 'Pacific/Fiji', latitude: -18.14, longitude: 178.44),
  WorldCity(name: 'Port Moresby', country: 'Papua New Guinea', zone: 'Pacific/Port_Moresby', latitude: -9.44, longitude: 147.18),
  WorldCity(name: 'Nouméa', country: 'New Caledonia', zone: 'Pacific/Noumea', latitude: -22.28, longitude: 166.46, aliases: ['Noumea']),
  WorldCity(name: 'Papeete', country: 'French Polynesia', zone: 'Pacific/Tahiti', latitude: -17.54, longitude: -149.57, aliases: ['Tahiti']),
  WorldCity(name: 'Hagåtña', country: 'Guam', zone: 'Pacific/Guam', latitude: 13.47, longitude: 144.75, aliases: ['Hagatna', 'Agana']),
];
