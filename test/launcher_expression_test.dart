import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/launcher/expression.dart';

void main() {
  group('evaluateExpression', () {
    test('evaluates the usual arithmetic', () {
      expect(evaluateExpression('2+2'), '4');
      expect(evaluateExpression('10/4'), '2.5');
      expect(evaluateExpression('2^10'), '1024');
      expect(evaluateExpression('(1+2)*3'), '9');
      expect(evaluateExpression('7 % 3'), '1');
      expect(evaluateExpression('-3 + 10'), '7');
      expect(evaluateExpression('sqrt(16)+1'), '5');
    });

    test('hides binary floating-point noise', () {
      expect(evaluateExpression('0.1+0.2'), '0.3');
      expect(evaluateExpression('1/3'), '0.333333333333');
    });

    test('surrounding whitespace does not matter', () {
      expect(evaluateExpression('  2 + 2  '), '4');
    });

    test('results that are not finite have nothing to show', () {
      // These come back as infinity/NaN rather than throwing, so they have to
      // be filtered explicitly.
      expect(evaluateExpression('1/0'), isNull);
      expect(evaluateExpression('0/0'), isNull);
      expect(evaluateExpression('1e400*10'), isNull);
    });

    test('an app search never turns into a calculation', () {
      // The parser reads a bare identifier as a variable and knows `e` and
      // `pi` as constants, so the gate has to reject these before it sees them.
      expect(evaluateExpression('gimp'), isNull);
      expect(evaluateExpression('e'), isNull);
      expect(evaluateExpression('pi'), isNull);
      expect(evaluateExpression('42'), isNull);
      expect(evaluateExpression('7zip'), isNull);
      expect(evaluateExpression('python3-dev'), isNull);
      expect(evaluateExpression('x11-utils'), isNull);
      expect(evaluateExpression('gtk2-engines'), isNull);
      expect(evaluateExpression('2 apps'), isNull);
      expect(evaluateExpression(''), isNull);
    });

    test('a half-typed expression is silent, not an error', () {
      expect(evaluateExpression('2+'), isNull);
      expect(evaluateExpression('(2+3'), isNull);
      expect(evaluateExpression('2**'), isNull);
    });
  });

  group('formatResult', () {
    test('whole numbers lose their decimal tail', () {
      expect(formatResult(4.0), '4');
      expect(formatResult(-12), '-12');
    });

    test('magnitudes past exact integer range fall back to exponent form', () {
      expect(formatResult(1e14), '100000000000000');
      expect(formatResult(1e20), '1e+20');
      expect(formatResult(1.5e30), '1.5e+30');
    });

    test('non-finite values have no rendering', () {
      expect(formatResult(double.nan), isNull);
      expect(formatResult(double.infinity), isNull);
      expect(formatResult(double.negativeInfinity), isNull);
    });
  });
}
