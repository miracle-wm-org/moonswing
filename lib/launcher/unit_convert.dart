// The launcher's unit converter: turns a typed quantity into the same quantity
// said in other units, or null when the query is not one.
//
// Pure — no Flutter, no I/O — so the table, the gate and the peer choice are unit
// tested without a widget in sight. `expression.dart`'s sibling: the two rows
// cannot both fire, because a conversion carries no operator and
// `looksLikeExpression` demands one.

import 'dart:math' as math;

import 'package:graceful_shell/launcher/expression.dart' show formatResult;

/// What a unit measures. Two units convert only within one of these.
enum UnitDimension {
  length,
  mass,
  temperature,
  volume,
  area,
  speed,
  time,
  data,
  pressure,
  energy,
  angle,
}

/// Which family a unit belongs to, used for one thing only: a peer from a
/// *different* family is listed first, because somebody typing `1kg` almost
/// always wants pounds before they want grams.
enum UnitSystem {
  metric,
  imperial,
  /// Powers of ten, for the storage units that have a binary counterpart.
  decimal,
  /// Powers of 1024.
  binary,
  /// Belongs to no pair — seconds, kelvin, knots.
  neutral,
}

/// One unit, and how to reach its dimension's base unit.
///
/// `base = value * factor + offset`. The offset is what makes temperature work:
/// it is the one dimension whose conversions are affine rather than a ratio, and
/// a table of plain factors would special-case it somewhere less visible.
class ConvertibleUnit {
  const ConvertibleUnit({
    required this.id,
    required this.symbol,
    required this.dimension,
    required this.system,
    required this.factor,
    required this.aliases,
    this.offset = 0,
    this.exactAliases = const [],
    this.specialist = false,
  });

  /// Stable identity, used by the peer tables and by tests.
  final String id;

  /// What the row prints: `kg`, `°F`, `mi`.
  final String symbol;

  final UnitDimension dimension;
  final UnitSystem system;
  final double factor;
  final double offset;

  /// Spellings, matched case-insensitively with whitespace removed.
  final List<String> aliases;

  /// Spellings matched *before* [aliases] and with case intact. Exists for
  /// kelvin alone: `K` is its symbol, and a lower-case `k` is what somebody
  /// typing `10k` means by a thousand — reading that as a temperature is the
  /// converter answering a question nobody asked.
  final List<String> exactAliases;

  /// Whether the unit is reachable only by being asked for.
  ///
  /// A knot is the right answer to `100 kph in knots` and the wrong first line of
  /// `100 kph`, which is a question about miles per hour. Nautical miles and
  /// gradians likewise: each is the nearest-to-human-sized peer in its dimension
  /// and would therefore lead every bare query in it — the peer chooser being
  /// right about the arithmetic and wrong about the reader.
  final bool specialist;

  double toBase(double value) => value * factor + offset;
  double fromBase(double base) => (base - offset) / factor;
}

/// A number and what it is in.
class Quantity {
  const Quantity(this.value, this.unit);

  final double value;
  final ConvertibleUnit unit;
}

/// A converted query: what was typed, and what it comes to.
class UnitConversion {
  const UnitConversion({
    required this.input,
    required this.results,
    required this.explicit,
  });

  /// The quantity the user typed.
  final Quantity input;

  /// What it comes to. One entry when the user named a target unit, up to
  /// [kUnitPeerLimit] when they did not.
  final List<Quantity> results;

  /// Whether the user named the target unit (`5 km to mi`) rather than leaving
  /// the peers to be chosen (`5 km`).
  final bool explicit;
}

/// How many peers a bare quantity is answered with.
///
/// Four: the row is a glance, not a table, and the card must not grow a
/// scrollable region above the results it is supposed to be introducing.
const int kUnitPeerLimit = 4;

/// The window a converted value has to land in to be worth printing, where the
/// dimension is one in which magnitude means anything.
///
/// `1 mm` in miles is `0.00000062`, which is the row spending a quarter of itself
/// saying "very small". The bounds are generous rather than tight, because
/// dropping a conversion the user was after is the worse failure.
const double kReadableMin = 1e-2;
const double kReadableMax = 1e5;

/// What a value under 1 costs the reader, as a multiple of what the same
/// distance above it costs. See [_magnitudeDistance].
const double kSmallValuePenalty = 3;

/// Words that separate the two halves of an explicit conversion.
///
/// `in` is in here *and* is inch's symbol, which is why the split is done over
/// whole tokens and tried from the right: `5 in in cm` splits at the second
/// one, leaving `5 in` to parse as a quantity.
const List<String> _conversionKeywords = ['to', 'in', 'into', 'as', '>'];

/// A leading number: optionally signed, decimal point either side.
///
/// No exponent form — `1e3kg` cannot be told from a unit whose spelling starts
/// with `e`, and the calculator is where an exponent belongs anyway.
final RegExp _quantityPattern = RegExp(r'^([+-]?(?:\d+\.?\d*|\.\d+))\s*(.+)$');

/// The whole table. Ordering within a dimension is the tie-break the peer
/// chooser falls back on, so it runs from the unit somebody is most likely to
/// want to the one they are least.
const List<ConvertibleUnit> kConvertibleUnits = [
  // ---- Length, base metre ----
  ConvertibleUnit(
    id: 'metre', symbol: 'm', dimension: UnitDimension.length,
    system: UnitSystem.metric, factor: 1,
    aliases: ['m', 'meter', 'meters', 'metre', 'metres'],
  ),
  ConvertibleUnit(
    id: 'centimetre', symbol: 'cm', dimension: UnitDimension.length,
    system: UnitSystem.metric, factor: 0.01,
    aliases: ['cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'],
  ),
  ConvertibleUnit(
    id: 'millimetre', symbol: 'mm', dimension: UnitDimension.length,
    system: UnitSystem.metric, factor: 0.001,
    aliases: ['mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'],
  ),
  ConvertibleUnit(
    id: 'kilometre', symbol: 'km', dimension: UnitDimension.length,
    system: UnitSystem.metric, factor: 1000,
    aliases: ['km', 'kilometer', 'kilometers', 'kilometre', 'kilometres'],
  ),
  ConvertibleUnit(
    id: 'mile', symbol: 'mi', dimension: UnitDimension.length,
    system: UnitSystem.imperial, factor: 1609.344,
    aliases: ['mi', 'mile', 'miles'],
  ),
  ConvertibleUnit(
    id: 'foot', symbol: 'ft', dimension: UnitDimension.length,
    system: UnitSystem.imperial, factor: 0.3048,
    aliases: ['ft', 'foot', 'feet', "'"],
  ),
  ConvertibleUnit(
    id: 'inch', symbol: 'in', dimension: UnitDimension.length,
    system: UnitSystem.imperial, factor: 0.0254,
    aliases: ['in', 'inch', 'inches', '"'],
  ),
  ConvertibleUnit(
    id: 'yard', symbol: 'yd', dimension: UnitDimension.length,
    system: UnitSystem.imperial, factor: 0.9144,
    aliases: ['yd', 'yard', 'yards'],
  ),
  ConvertibleUnit(
    id: 'nautical-mile', symbol: 'nmi', dimension: UnitDimension.length,
    system: UnitSystem.neutral, factor: 1852,
    aliases: ['nmi', 'nauticalmile', 'nauticalmiles'],
    specialist: true,
  ),

  // ---- Mass, base kilogram ----
  ConvertibleUnit(
    id: 'kilogram', symbol: 'kg', dimension: UnitDimension.mass,
    system: UnitSystem.metric, factor: 1,
    aliases: ['kg', 'kilo', 'kilos', 'kilogram', 'kilograms'],
  ),
  ConvertibleUnit(
    id: 'gram', symbol: 'g', dimension: UnitDimension.mass,
    system: UnitSystem.metric, factor: 0.001,
    aliases: ['g', 'gram', 'grams', 'gramme', 'grammes'],
  ),
  ConvertibleUnit(
    id: 'milligram', symbol: 'mg', dimension: UnitDimension.mass,
    system: UnitSystem.metric, factor: 1e-6,
    aliases: ['mg', 'milligram', 'milligrams'],
  ),
  ConvertibleUnit(
    id: 'tonne', symbol: 't', dimension: UnitDimension.mass,
    system: UnitSystem.metric, factor: 1000,
    aliases: ['t', 'tonne', 'tonnes', 'metricton', 'metrictons'],
  ),
  ConvertibleUnit(
    id: 'pound', symbol: 'lb', dimension: UnitDimension.mass,
    system: UnitSystem.imperial, factor: 0.45359237,
    aliases: ['lb', 'lbs', 'pound', 'pounds'],
  ),
  ConvertibleUnit(
    id: 'ounce', symbol: 'oz', dimension: UnitDimension.mass,
    system: UnitSystem.imperial, factor: 0.028349523125,
    aliases: ['oz', 'ounce', 'ounces'],
  ),
  ConvertibleUnit(
    id: 'stone', symbol: 'st', dimension: UnitDimension.mass,
    system: UnitSystem.imperial, factor: 6.35029318,
    aliases: ['st', 'stone', 'stones'],
  ),
  ConvertibleUnit(
    id: 'short-ton', symbol: 'ton', dimension: UnitDimension.mass,
    system: UnitSystem.imperial, factor: 907.18474,
    aliases: ['ton', 'tons', 'shortton', 'shorttons'],
  ),

  // ---- Temperature, base kelvin ----
  ConvertibleUnit(
    id: 'celsius', symbol: '°C', dimension: UnitDimension.temperature,
    system: UnitSystem.metric, factor: 1, offset: 273.15,
    aliases: ['c', '°c', 'celsius', 'centigrade'],
  ),
  ConvertibleUnit(
    id: 'fahrenheit', symbol: '°F', dimension: UnitDimension.temperature,
    system: UnitSystem.imperial, factor: 5 / 9, offset: 273.15 - 32 * 5 / 9,
    aliases: ['f', '°f', 'fahrenheit'],
  ),
  ConvertibleUnit(
    id: 'kelvin', symbol: 'K', dimension: UnitDimension.temperature,
    system: UnitSystem.neutral, factor: 1,
    aliases: ['°k', 'kelvin', 'kelvins'], exactAliases: ['K'],
  ),

  // ---- Volume, base litre. Gallons and the spoons are US ----
  ConvertibleUnit(
    id: 'litre', symbol: 'L', dimension: UnitDimension.volume,
    system: UnitSystem.metric, factor: 1,
    aliases: ['l', 'liter', 'liters', 'litre', 'litres'],
  ),
  ConvertibleUnit(
    id: 'millilitre', symbol: 'mL', dimension: UnitDimension.volume,
    system: UnitSystem.metric, factor: 0.001,
    aliases: ['ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres'],
  ),
  ConvertibleUnit(
    id: 'gallon', symbol: 'gal', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 3.785411784,
    aliases: ['gal', 'gallon', 'gallons', 'usgal'],
  ),
  ConvertibleUnit(
    id: 'quart', symbol: 'qt', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 0.946352946,
    aliases: ['qt', 'quart', 'quarts'],
  ),
  ConvertibleUnit(
    id: 'pint', symbol: 'pt', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 0.473176473,
    aliases: ['pt', 'pint', 'pints'],
  ),
  ConvertibleUnit(
    id: 'cup', symbol: 'cup', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 0.2365882365,
    aliases: ['cup', 'cups'],
  ),
  ConvertibleUnit(
    id: 'fluid-ounce', symbol: 'fl oz', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 0.0295735295625,
    aliases: ['floz', 'fluidounce', 'fluidounces'],
  ),
  ConvertibleUnit(
    id: 'tablespoon', symbol: 'tbsp', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 0.01478676478125,
    aliases: ['tbsp', 'tablespoon', 'tablespoons'],
  ),
  ConvertibleUnit(
    id: 'teaspoon', symbol: 'tsp', dimension: UnitDimension.volume,
    system: UnitSystem.imperial, factor: 0.00492892159375,
    aliases: ['tsp', 'teaspoon', 'teaspoons'],
  ),

  // ---- Area, base square metre ----
  ConvertibleUnit(
    id: 'square-metre', symbol: 'm²', dimension: UnitDimension.area,
    system: UnitSystem.metric, factor: 1,
    aliases: ['m2', 'm^2', 'm²', 'sqm', 'squaremeter', 'squaremeters'],
  ),
  ConvertibleUnit(
    id: 'square-kilometre', symbol: 'km²', dimension: UnitDimension.area,
    system: UnitSystem.metric, factor: 1e6,
    aliases: ['km2', 'km^2', 'km²', 'sqkm'],
  ),
  ConvertibleUnit(
    id: 'hectare', symbol: 'ha', dimension: UnitDimension.area,
    system: UnitSystem.metric, factor: 1e4,
    aliases: ['ha', 'hectare', 'hectares'],
  ),
  ConvertibleUnit(
    id: 'square-centimetre', symbol: 'cm²', dimension: UnitDimension.area,
    system: UnitSystem.metric, factor: 1e-4,
    aliases: ['cm2', 'cm^2', 'cm²', 'sqcm'],
  ),
  ConvertibleUnit(
    id: 'acre', symbol: 'acre', dimension: UnitDimension.area,
    system: UnitSystem.imperial, factor: 4046.8564224,
    aliases: ['acre', 'acres'],
  ),
  ConvertibleUnit(
    id: 'square-foot', symbol: 'ft²', dimension: UnitDimension.area,
    system: UnitSystem.imperial, factor: 0.09290304,
    aliases: ['ft2', 'ft^2', 'ft²', 'sqft', 'squarefoot', 'squarefeet'],
  ),
  ConvertibleUnit(
    id: 'square-mile', symbol: 'mi²', dimension: UnitDimension.area,
    system: UnitSystem.imperial, factor: 2589988.110336,
    aliases: ['mi2', 'mi^2', 'mi²', 'sqmi'],
  ),
  ConvertibleUnit(
    id: 'square-yard', symbol: 'yd²', dimension: UnitDimension.area,
    system: UnitSystem.imperial, factor: 0.83612736,
    aliases: ['yd2', 'yd^2', 'yd²', 'sqyd'],
  ),

  // ---- Speed, base metre per second ----
  ConvertibleUnit(
    id: 'kilometres-per-hour', symbol: 'km/h', dimension: UnitDimension.speed,
    system: UnitSystem.metric, factor: 1 / 3.6,
    aliases: ['km/h', 'kmh', 'kph', 'kmph'],
  ),
  ConvertibleUnit(
    id: 'metres-per-second', symbol: 'm/s', dimension: UnitDimension.speed,
    system: UnitSystem.metric, factor: 1,
    aliases: ['m/s', 'mps', 'ms-1'],
  ),
  ConvertibleUnit(
    id: 'miles-per-hour', symbol: 'mph', dimension: UnitDimension.speed,
    system: UnitSystem.imperial, factor: 0.44704,
    aliases: ['mph', 'mi/h', 'milesperhour'],
  ),
  ConvertibleUnit(
    id: 'feet-per-second', symbol: 'ft/s', dimension: UnitDimension.speed,
    system: UnitSystem.imperial, factor: 0.3048,
    aliases: ['ft/s', 'fps', 'feetpersecond'],
  ),
  ConvertibleUnit(
    id: 'knot', symbol: 'kn', dimension: UnitDimension.speed,
    system: UnitSystem.neutral, factor: 1852 / 3600,
    aliases: ['kn', 'kt', 'kts', 'knot', 'knots'],
    specialist: true,
  ),

  // ---- Time, base second. No bare `d`: `3d` is a search, not three days ----
  ConvertibleUnit(
    id: 'second', symbol: 's', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 1,
    aliases: ['s', 'sec', 'secs', 'second', 'seconds'],
  ),
  ConvertibleUnit(
    id: 'minute', symbol: 'min', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 60,
    aliases: ['min', 'mins', 'minute', 'minutes'],
  ),
  ConvertibleUnit(
    id: 'hour', symbol: 'h', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 3600,
    aliases: ['h', 'hr', 'hrs', 'hour', 'hours'],
  ),
  ConvertibleUnit(
    id: 'day', symbol: 'd', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 86400,
    aliases: ['day', 'days'],
  ),
  ConvertibleUnit(
    id: 'week', symbol: 'wk', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 604800,
    aliases: ['wk', 'wks', 'week', 'weeks'],
  ),
  ConvertibleUnit(
    id: 'year', symbol: 'yr', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 31557600,
    aliases: ['yr', 'yrs', 'year', 'years'],
  ),
  ConvertibleUnit(
    id: 'millisecond', symbol: 'ms', dimension: UnitDimension.time,
    system: UnitSystem.neutral, factor: 0.001,
    aliases: ['ms', 'millisecond', 'milliseconds'],
  ),

  // ---- Data, base byte ----
  ConvertibleUnit(
    id: 'byte', symbol: 'B', dimension: UnitDimension.data,
    system: UnitSystem.neutral, factor: 1,
    aliases: ['b', 'byte', 'bytes'],
  ),
  ConvertibleUnit(
    id: 'kilobyte', symbol: 'kB', dimension: UnitDimension.data,
    system: UnitSystem.decimal, factor: 1e3,
    aliases: ['kb', 'kilobyte', 'kilobytes'],
  ),
  ConvertibleUnit(
    id: 'megabyte', symbol: 'MB', dimension: UnitDimension.data,
    system: UnitSystem.decimal, factor: 1e6,
    aliases: ['mb', 'megabyte', 'megabytes'],
  ),
  ConvertibleUnit(
    id: 'gigabyte', symbol: 'GB', dimension: UnitDimension.data,
    system: UnitSystem.decimal, factor: 1e9,
    aliases: ['gb', 'gigabyte', 'gigabytes'],
  ),
  ConvertibleUnit(
    id: 'terabyte', symbol: 'TB', dimension: UnitDimension.data,
    system: UnitSystem.decimal, factor: 1e12,
    aliases: ['tb', 'terabyte', 'terabytes'],
  ),
  ConvertibleUnit(
    id: 'kibibyte', symbol: 'KiB', dimension: UnitDimension.data,
    system: UnitSystem.binary, factor: 1024,
    aliases: ['kib', 'kibibyte', 'kibibytes'],
  ),
  ConvertibleUnit(
    id: 'mebibyte', symbol: 'MiB', dimension: UnitDimension.data,
    system: UnitSystem.binary, factor: 1048576,
    aliases: ['mib', 'mebibyte', 'mebibytes'],
  ),
  ConvertibleUnit(
    id: 'gibibyte', symbol: 'GiB', dimension: UnitDimension.data,
    system: UnitSystem.binary, factor: 1073741824,
    aliases: ['gib', 'gibibyte', 'gibibytes'],
  ),
  ConvertibleUnit(
    id: 'tebibyte', symbol: 'TiB', dimension: UnitDimension.data,
    system: UnitSystem.binary, factor: 1099511627776,
    aliases: ['tib', 'tebibyte', 'tebibytes'],
  ),
  ConvertibleUnit(
    id: 'bit', symbol: 'bit', dimension: UnitDimension.data,
    system: UnitSystem.neutral, factor: 0.125,
    aliases: ['bit', 'bits'],
  ),

  // ---- Pressure, base pascal ----
  ConvertibleUnit(
    id: 'bar', symbol: 'bar', dimension: UnitDimension.pressure,
    system: UnitSystem.metric, factor: 1e5,
    aliases: ['bar', 'bars'],
  ),
  ConvertibleUnit(
    id: 'pascal', symbol: 'Pa', dimension: UnitDimension.pressure,
    system: UnitSystem.metric, factor: 1,
    aliases: ['pa', 'pascal', 'pascals'],
  ),
  ConvertibleUnit(
    id: 'kilopascal', symbol: 'kPa', dimension: UnitDimension.pressure,
    system: UnitSystem.metric, factor: 1000,
    aliases: ['kpa', 'kilopascal', 'kilopascals'],
  ),
  ConvertibleUnit(
    id: 'hectopascal', symbol: 'hPa', dimension: UnitDimension.pressure,
    system: UnitSystem.metric, factor: 100,
    aliases: ['hpa', 'mbar', 'millibar', 'millibars'],
  ),
  ConvertibleUnit(
    id: 'psi', symbol: 'psi', dimension: UnitDimension.pressure,
    system: UnitSystem.imperial, factor: 6894.757293168,
    aliases: ['psi'],
  ),
  ConvertibleUnit(
    id: 'atmosphere', symbol: 'atm', dimension: UnitDimension.pressure,
    system: UnitSystem.neutral, factor: 101325,
    aliases: ['atm', 'atmosphere', 'atmospheres'],
  ),
  ConvertibleUnit(
    id: 'millimetre-of-mercury', symbol: 'mmHg',
    dimension: UnitDimension.pressure,
    system: UnitSystem.neutral, factor: 133.322387415,
    aliases: ['mmhg', 'torr'],
  ),

  // ---- Energy, base joule ----
  ConvertibleUnit(
    id: 'joule', symbol: 'J', dimension: UnitDimension.energy,
    system: UnitSystem.metric, factor: 1,
    aliases: ['j', 'joule', 'joules'],
  ),
  ConvertibleUnit(
    id: 'kilojoule', symbol: 'kJ', dimension: UnitDimension.energy,
    system: UnitSystem.metric, factor: 1000,
    aliases: ['kj', 'kilojoule', 'kilojoules'],
  ),
  ConvertibleUnit(
    id: 'kilocalorie', symbol: 'kcal', dimension: UnitDimension.energy,
    system: UnitSystem.metric, factor: 4184,
    aliases: ['kcal', 'kilocalorie', 'kilocalories'],
  ),
  ConvertibleUnit(
    id: 'calorie', symbol: 'cal', dimension: UnitDimension.energy,
    system: UnitSystem.metric, factor: 4.184,
    aliases: ['cal', 'calorie', 'calories'],
  ),
  ConvertibleUnit(
    id: 'watt-hour', symbol: 'Wh', dimension: UnitDimension.energy,
    system: UnitSystem.neutral, factor: 3600,
    aliases: ['wh', 'watthour', 'watthours'],
  ),
  ConvertibleUnit(
    id: 'kilowatt-hour', symbol: 'kWh', dimension: UnitDimension.energy,
    system: UnitSystem.neutral, factor: 3.6e6,
    aliases: ['kwh', 'kilowatthour', 'kilowatthours'],
  ),
  ConvertibleUnit(
    id: 'btu', symbol: 'BTU', dimension: UnitDimension.energy,
    system: UnitSystem.imperial, factor: 1055.05585262,
    aliases: ['btu', 'btus'],
  ),

  // ---- Angle, base degree ----
  ConvertibleUnit(
    id: 'degree', symbol: '°', dimension: UnitDimension.angle,
    system: UnitSystem.neutral, factor: 1,
    aliases: ['deg', 'degs', 'degree', 'degrees', '°'],
  ),
  ConvertibleUnit(
    id: 'radian', symbol: 'rad', dimension: UnitDimension.angle,
    system: UnitSystem.neutral, factor: 180 / math.pi,
    aliases: ['rad', 'rads', 'radian', 'radians'],
  ),
  ConvertibleUnit(
    id: 'gradian', symbol: 'grad', dimension: UnitDimension.angle,
    system: UnitSystem.neutral, factor: 0.9,
    aliases: ['grad', 'grads', 'gradian', 'gradians'],
    specialist: true,
  ),
];

/// Dimensions whose peers are chosen by declared order rather than by how
/// readable the converted number is.
///
/// Temperature is the whole of it: `0 °C` and `-40 °F` are ordinary readings, and
/// a rule judging a conversion by its distance from 1 would throw away the
/// freezing point of water for being too near zero.
const Set<UnitDimension> kUnorderedByMagnitude = {UnitDimension.temperature};

final Map<String, ConvertibleUnit> _byAlias = {
  for (final unit in kConvertibleUnits)
    for (final alias in unit.aliases) alias: unit,
};

final Map<String, ConvertibleUnit> _byExactAlias = {
  for (final unit in kConvertibleUnits)
    for (final alias in unit.exactAliases) alias: unit,
};

/// The unit [token] names, or null.
///
/// Whitespace inside the token is dropped, which is what lets `fl oz`, `sq ft`
/// and `km / h` be spelled the way somebody types them while the table keeps
/// one entry each.
ConvertibleUnit? unitForToken(String token) {
  final compact = token.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return null;
  return _byExactAlias[compact] ?? _byAlias[compact.toLowerCase()];
}

/// Parses `1kg`, `1 kg`, `-40°F`, `2.5 fl oz` — a number and a unit, nothing
/// else. Returns null for anything that is not exactly that.
Quantity? parseQuantity(String text) {
  final match = _quantityPattern.firstMatch(text.trim());
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null || !value.isFinite) return null;
  final unit = unitForToken(match.group(2)!);
  if (unit == null) return null;
  return Quantity(value, unit);
}

/// Converts [quantity] into [target], which must share its dimension.
Quantity convertQuantity(Quantity quantity, ConvertibleUnit target) =>
    Quantity(target.fromBase(quantity.unit.toBase(quantity.value)), target);

/// Answers [query] as a conversion, or null when it is not one.
///
/// Never throws: this runs on every keystroke, and a half-typed query is the
/// normal case rather than an error.
UnitConversion? convertQuery(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;

  final explicit = _parseExplicit(trimmed);
  if (explicit != null) return explicit;

  final input = parseQuantity(trimmed);
  if (input == null) return null;
  final peers = peersFor(input);
  if (peers.isEmpty) return null;
  return UnitConversion(input: input, results: peers, explicit: false);
}

/// `5 km to mi` — the form that names its own target.
///
/// Splits over whole tokens and tries the keywords from the right, so `5 in in
/// cm` and `5 cm in in` both land. A split whose halves do not both parse is not
/// a conversion, which keeps `2 to 3` and `5 apps in dock` out.
UnitConversion? _parseExplicit(String trimmed) {
  final words = trimmed.split(RegExp(r'\s+'));
  for (var i = words.length - 1; i > 0; i--) {
    if (!_conversionKeywords.contains(words[i].toLowerCase())) continue;
    final left = words.sublist(0, i).join(' ');
    final right = words.sublist(i + 1).join(' ');
    if (right.isEmpty) continue;
    final input = parseQuantity(left);
    if (input == null) continue;
    final target = unitForToken(right);
    if (target == null || target.dimension != input.unit.dimension) continue;
    return UnitConversion(
      input: input,
      results: [convertQuantity(input, target)],
      explicit: true,
    );
  }
  return null;
}

/// What a bare quantity is answered with: the units of its dimension that say
/// something useful about it, best first, capped at [kUnitPeerLimit].
///
/// Two rules decide the order, both because `1kg` is a question about pounds far
/// more often than about grams. A peer from a *different* system comes first;
/// within each group the one nearest a human-sized number leads, so `1 mi` leads
/// with kilometres and `1 mm` with inches without either being special-cased.
List<Quantity> peersFor(Quantity input) {
  final candidates = [
    for (final unit in kConvertibleUnits)
      if (unit.dimension == input.unit.dimension &&
          unit.id != input.unit.id &&
          !unit.specialist)
        convertQuantity(input, unit),
  ]..removeWhere((peer) => !peer.value.isFinite);

  final ordered = kUnorderedByMagnitude.contains(input.unit.dimension) ||
          input.value == 0
      ? _orderedAsDeclared(input, candidates)
      : _orderedByReadability(input, candidates);

  return ordered.take(kUnitPeerLimit).toList();
}

/// Declared order, with the other systems first.
List<Quantity> _orderedAsDeclared(Quantity input, List<Quantity> candidates) {
  final indices = {
    for (var i = 0; i < kConvertibleUnits.length; i++)
      kConvertibleUnits[i].id: i,
  };
  return candidates.toList()
    ..sort((a, b) {
      final bySystem = _systemRank(input, a) - _systemRank(input, b);
      if (bySystem != 0) return bySystem;
      return indices[a.unit.id]! - indices[b.unit.id]!;
    });
}

/// Readable conversions first, ordered by how close each lands to a number a
/// person would say out loud.
///
/// The unreadable ones are dropped rather than sorted to the back — but only
/// while something survives: a query whose every peer is enormous still gets the
/// least enormous, because a row that renders nothing is a conversion the shell
/// decided the user did not want.
List<Quantity> _orderedByReadability(
    Quantity input, List<Quantity> candidates) {
  var readable = candidates
      .where((peer) =>
          peer.value.abs() >= kReadableMin && peer.value.abs() <= kReadableMax)
      .toList();
  if (readable.isEmpty) readable = candidates.toList();

  return readable
    ..sort((a, b) {
      final bySystem = _systemRank(input, a) - _systemRank(input, b);
      if (bySystem != 0) return bySystem;
      return _magnitudeDistance(a.value).compareTo(_magnitudeDistance(b.value));
    });
}

/// 0 for a peer in another system, 1 for one in the input's own.
int _systemRank(Quantity input, Quantity peer) =>
    peer.unit.system == input.unit.system ? 1 : 0;

/// How much harder than `2.2` a value is to read, in decades.
///
/// Distance from 1 either way, but a value *below* it counts for three times as
/// much: `0.125 d` and `180 min` are the same three hours and the same decade and
/// a half from 1, and only one is a number somebody says out loud. Without the
/// asymmetry the days would lead.
///
/// Zero cannot reach this — the dimensions where a conversion can legitimately be
/// zero do not sort by it.
double _magnitudeDistance(double value) {
  final magnitude = value.abs();
  if (magnitude == 0) return double.maxFinite;
  final decades = math.log(magnitude) / math.ln10;
  return decades >= 0 ? decades : -decades * kSmallValuePenalty;
}

/// `2.20462 lb`. The number and its unit, as one string.
String formatQuantity(Quantity quantity) {
  final value = formatQuantityValue(quantity.value);
  if (value == null) return quantity.unit.symbol;
  return '$value ${quantity.unit.symbol}';
}

/// The number half of a conversion, or null when there is nothing to print.
///
/// Six significant figures rather than the calculator's twelve: a conversion
/// factor is a measurement, and `2.20462262185 lb` claims a precision the question
/// never had. Long integers are grouped, `formatKilometres`'s rule.
String? formatQuantityValue(double value) {
  final text = formatResult(value, precision: 6);
  if (text == null) return null;
  return _groupDigits(text);
}

/// Commas every three digits of the integer part, from five digits up.
///
/// Exponent form is left alone: there are no unbroken runs in `1e-7` to break
/// up, and a comma in one would read as a second number.
String _groupDigits(String text) {
  if (text.contains('e')) return text;
  final sign = text.startsWith('-') ? '-' : '';
  final unsigned = sign.isEmpty ? text : text.substring(1);
  final point = unsigned.indexOf('.');
  final whole = point == -1 ? unsigned : unsigned.substring(0, point);
  final tail = point == -1 ? '' : unsigned.substring(point);
  if (whole.length < 5) return text;

  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '$sign$buffer$tail';
}
