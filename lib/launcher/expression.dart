// The launcher's calculator: turns a typed query into a result string, or null
// when the query is not arithmetic.
//
// Pure — no Flutter, no I/O — so the gate and the formatting are unit tested
// without a widget in sight.

import 'package:math_expressions/math_expressions.dart';

/// Identifiers `math_expressions` understands. Stripped out before the charset
/// check so `sqrt(16)+2` is recognised as arithmetic while `sqlitebrowser` is
/// not. Longest first, so `arctan` is not partially eaten as `tan`.
const List<String> _allowedIdentifiers = [
  'arccos', 'arcsin', 'arctan', //
  'ceil', 'floor', 'sqrt', 'sgn', 'abs', 'nrt', 'log',
  'cos', 'sin', 'tan', 'ln', 'pi', 'e',
];

/// What is left once identifiers are removed: digits, whitespace, operators,
/// grouping, and the decimal point / argument separator.
final RegExp _arithmeticOnly = RegExp(r'^[0-9\s+\-*/^%!(),.]*$');

/// An operator or a bracket has to appear somewhere, or `5` would "evaluate"
/// to `5` and every numeric app name would grow a pointless result row.
final RegExp _hasOperator = RegExp(r'[+\-*/^%!()]');

final RegExp _hasDigit = RegExp(r'[0-9]');

/// A number on its own (possibly signed / decimal) — nothing to compute.
final RegExp _bareNumber = RegExp(r'^[+-]?\d+(\.\d+)?$');

final GrammarParser _parser = GrammarParser();
final RealEvaluator _evaluator = RealEvaluator();

/// Whether [query] looks enough like arithmetic to be worth parsing.
///
/// Deliberately strict. The parser is happy to read a bare identifier as a
/// variable and `e` as Euler's number, so without this an app search for `e` or
/// `pi` would sprout a calculator row.
bool looksLikeExpression(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return false;
  if (!_hasDigit.hasMatch(trimmed)) return false;
  if (!_hasOperator.hasMatch(trimmed)) return false;
  if (_bareNumber.hasMatch(trimmed)) return false;

  var stripped = trimmed.toLowerCase();
  for (final identifier in _allowedIdentifiers) {
    stripped = stripped.replaceAll(identifier, '');
  }
  return _arithmeticOnly.hasMatch(stripped);
}

/// Evaluates [query] as a mathematical expression, or returns null when it is not
/// one (or cannot be computed).
///
/// Never throws: a half-typed expression is the normal case, since this runs on
/// every keystroke.
String? evaluateExpression(String query) {
  if (!looksLikeExpression(query)) return null;
  try {
    final result = _evaluator.evaluate(_parser.parse(query.trim()));
    return formatResult(result);
  } catch (_) {
    // Unbound variable, unbalanced parens, half-typed operator — all expected
    // while the user is still typing.
    return null;
  }
}

/// Renders an evaluated result the way a calculator would.
///
/// `1/0` and `0/0` come back as infinity and NaN rather than throwing, so they are
/// filtered here: there is no useful thing to show for either.
///
/// [precision] is the significant-figure count the fractional form is trimmed to;
/// the unit converter passes a shorter one, because a conversion factor is a
/// measurement. It does not reach a value that is *exactly* an integer, which
/// prints in full either way — `1 mi` is 1,609,344 mm and not 1.60934e6.
String? formatResult(num value, {int precision = 12}) {
  final asDouble = value.toDouble();
  if (!asDouble.isFinite) return null;

  // Whole numbers print without a decimal tail, but only while a double still
  // represents them exactly.
  if (asDouble == asDouble.roundToDouble() && asDouble.abs() < 1e15) {
    return asDouble.toInt().toString();
  }

  // Trim to a precision that hides binary-floating-point noise: 0.1 + 0.2
  // should read 0.3, not 0.30000000000000004.
  final text = asDouble.toStringAsPrecision(precision);
  final exponent = text.indexOf('e');
  if (exponent == -1) return _trimZeros(text);
  return '${_trimZeros(text.substring(0, exponent))}${text.substring(exponent)}';
}

String _trimZeros(String mantissa) {
  if (!mantissa.contains('.')) return mantissa;
  var trimmed = mantissa.replaceFirst(RegExp(r'0+$'), '');
  if (trimmed.endsWith('.')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}
