// The count behind `borrowSurfaceKeyboard`: who holds a surface's keyboard, so
// that the first holder flips the surface to `onDemand` and the last flips it
// back. The surface itself is a GTK window and cannot be made here; what is
// pinned is the arithmetic every popup's open and close now goes through.

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/popup.dart';

void main() {
  test('the first holder flips the surface and the last flips it back', () {
    final loans = KeyboardLoans<Object>();
    final panel = Object();

    expect(loans.isLent(panel), isFalse);
    expect(loans.take(panel), isTrue, reason: 'the first holder flips');
    expect(loans.isLent(panel), isTrue);
    expect(loans.give(panel), isTrue, reason: 'the last holder flips back');
    expect(loans.isLent(panel), isFalse);
  });

  test('a popup still closing does not take the keyboard from its successor',
      () {
    // Close-then-open in one gesture: the outgoing card holds the panel until
    // its exit ends, by which time the incoming one has borrowed too.
    final loans = KeyboardLoans<Object>();
    final panel = Object();

    expect(loans.take(panel), isTrue);
    expect(loans.take(panel), isFalse, reason: 'already focusable');
    expect(loans.give(panel), isFalse, reason: 'the successor still holds it');
    expect(loans.isLent(panel), isTrue);
    expect(loans.give(panel), isTrue);
    expect(loans.isLent(panel), isFalse);
  });

  test('giving back what was never taken changes nothing', () {
    final loans = KeyboardLoans<Object>();
    final panel = Object();

    expect(loans.give(panel), isFalse);
    expect(loans.isLent(panel), isFalse);
    // And leaves no debt for the next borrow to pay off.
    expect(loans.take(panel), isTrue);
    expect(loans.give(panel), isTrue);
    expect(loans.give(panel), isFalse);
  });

  test('surfaces are counted separately', () {
    final loans = KeyboardLoans<Object>();
    final top = Object();
    final bottom = Object();

    expect(loans.take(top), isTrue);
    expect(loans.take(bottom), isTrue);
    expect(loans.give(top), isTrue);
    expect(loans.isLent(top), isFalse);
    expect(loans.isLent(bottom), isTrue);
  });
}
