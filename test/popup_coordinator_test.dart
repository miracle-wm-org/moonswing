import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/popup_coordinator.dart';

/// Stands in for the `State` that owns a surface: identity plus a record of
/// what the coordinator asked it to do.
class _Owner {
  _Owner(this.name, this.log);
  final String name;
  final List<String> log;
  int dismissals = 0;

  void onDismiss() {
    dismissals++;
    log.add(name);
  }
}

void main() {
  late PopupCoordinator coordinator;
  late List<String> log;

  setUp(() {
    coordinator = PopupCoordinator.forTesting();
    log = <String>[];
  });

  TransientHandle openOne(
    String name, {
    TransientHandle? parent,
    TransientPolicy policy = TransientPolicy.menu,
    _Owner? owner,
  }) {
    final o = owner ?? _Owner(name, log);
    return coordinator.open(
      owner: o,
      parent: parent,
      policy: policy,
      onDismiss: o.onDismiss,
    );
  }

  PointerDownEvent down({int buttons = kPrimaryButton}) =>
      PointerDownEvent(buttons: buttons);

  group('displacement', () {
    test('opening an unrelated surface dismisses the open one, once', () {
      final a = _Owner('a', log);
      openOne('a', owner: a);
      openOne('b');

      expect(a.dismissals, 1);
      expect(log, <String>['a']);
    });

    test('a tooltip dismisses nothing, but is dismissed by others', () {
      final menu = _Owner('menu', log);
      openOne('menu', owner: menu);
      final tip = _Owner('tip', log);
      openOne('tip', owner: tip, policy: TransientPolicy.tooltip);

      expect(menu.dismissals, 0, reason: 'a hover label must not close a menu');

      openOne('other');
      expect(tip.dismissals, 1);
      expect(menu.dismissals, 1);
    });

    test('a modal survives another surface opening, and still displaces', () {
      final first = _Owner('first', log);
      openOne('first', owner: first);
      final modal = _Owner('modal', log);
      openOne('modal', owner: modal, policy: TransientPolicy.modal);

      expect(first.dismissals, 1, reason: 'a modal still displaces');

      openOne('after');
      expect(modal.dismissals, 0, reason: 'nothing may resolve it for the user');
    });

    test('a surface nested in a modal inherits its refusal', () {
      final modal = openOne('modal', policy: TransientPolicy.modal);
      final child = _Owner('child', log);
      openOne('child', owner: child, parent: modal);

      coordinator.dismissOutside(null);

      expect(child.dismissals, 0);
    });
  });

  group('nesting', () {
    test('a child does not dismiss its parent', () {
      final parent = _Owner('parent', log);
      final a = openOne('parent', owner: parent);
      openOne('flyout', parent: a);

      expect(parent.dismissals, 0);
    });

    test('a grandchild dismisses neither ancestor', () {
      final parent = _Owner('parent', log);
      final directory = openOne('parent', owner: parent);
      final flyoutOwner = _Owner('flyout', log);
      final flyout =
          openOne('flyout', owner: flyoutOwner, parent: directory);
      openOne('pin-menu', parent: flyout);

      expect(parent.dismissals, 0);
      expect(flyoutOwner.dismissals, 0);
    });

    test('a sibling dismisses its sibling and keeps the parent', () {
      final parent = _Owner('parent', log);
      final directory = openOne('parent', owner: parent);
      final first = _Owner('flyout-1', log);
      openOne('flyout-1', owner: first, parent: directory);
      openOne('flyout-2', parent: directory);

      expect(first.dismissals, 1);
      expect(parent.dismissals, 0);
    });

    test('dismissing a parent dismisses descendants children-first', () {
      final directory = openOne('directory');
      final flyout = openOne('flyout', parent: directory);
      openOne('pin-menu', parent: flyout);

      coordinator.dismiss(directory);

      expect(log, <String>['pin-menu', 'flyout', 'directory']);
    });

    test('dismissOutside keeps the tip chain and kills the rest', () {
      final directory = openOne('directory');
      final flyout = openOne('flyout', parent: directory);
      // A tooltip, so opening it does not displace the chain under test.
      final unrelated = _Owner('unrelated', log);
      openOne('unrelated', owner: unrelated, policy: TransientPolicy.tooltip);

      coordinator.dismissOutside(flyout);

      expect(log, <String>['unrelated']);
      expect(unrelated.dismissals, 1);
    });

    test('dismissOutside(null) kills everything', () {
      final directory = openOne('directory');
      openOne('flyout', parent: directory);

      coordinator.dismissOutside(null);

      expect(log, <String>['flyout', 'directory']);
    });
  });

  group('graceful close', () {
    test('the handle stays registered until close, and does not re-fire', () {
      final owner = _Owner('overlay', log);
      final handle = openOne('overlay', owner: owner);

      coordinator.dismiss(handle);
      expect(coordinator.openHandles, contains(handle),
          reason: 'the exit animation is still playing');

      // A second dismissal mid-fade must not restart the animation.
      coordinator.dismiss(handle);
      coordinator.dismissOutside(null);
      expect(owner.dismissals, 1);

      coordinator.close(handle);
      expect(coordinator.openHandles, isEmpty);
    });

    test('close is idempotent and null-tolerant', () {
      final handle = openOne('a');
      coordinator.close(handle);
      coordinator.close(handle);
      coordinator.close(null);
      expect(coordinator.openHandles, isEmpty);
    });

    test('dismissAll ignores policy and goes children-first', () {
      final modal = _Owner('modal', log);
      final handle = openOne('modal', owner: modal, policy: TransientPolicy.modal);
      openOne('child', parent: handle);

      coordinator.dismissAll();

      expect(log, <String>['child', 'modal']);
    });
  });

  group('reopen guard', () {
    test('a primary click arms it for the owner it dismissed', () {
      final owner = _Owner('popup', log);
      openOne('popup', owner: owner);

      coordinator.dismissFromPointerDown(down());

      expect(coordinator.consumeReopenGuard(owner), isTrue);
      expect(coordinator.consumeReopenGuard(owner), isFalse,
          reason: 'at most once per click');
    });

    test('a secondary click dismisses but arms nothing', () {
      final owner = _Owner('popup', log);
      openOne('popup', owner: owner);

      coordinator.dismissFromPointerDown(down(buttons: kSecondaryButton));

      expect(owner.dismissals, 1);
      expect(coordinator.consumeReopenGuard(owner), isFalse,
          reason: 'a right-click must still be free to open its menu');
    });

    test('a dismissed tooltip owner is never guarded', () {
      final owner = _Owner('tip', log);
      openOne('tip', owner: owner, policy: TransientPolicy.tooltip);

      coordinator.dismissFromPointerDown(down());

      expect(owner.dismissals, 1);
      expect(coordinator.consumeReopenGuard(owner), isFalse);
    });

    test('a later pointer-down clears a stale entry', () {
      final owner = _Owner('popup', log);
      openOne('popup', owner: owner);
      coordinator.dismissFromPointerDown(down());

      coordinator.dismissFromPointerDown(down());

      expect(coordinator.consumeReopenGuard(owner), isFalse);
    });

    test('a click inside a popup spares its chain', () {
      final parentOwner = _Owner('directory', log);
      final directory = openOne('directory', owner: parentOwner);
      final flyoutOwner = _Owner('flyout', log);
      final flyout = openOne('flyout', owner: flyoutOwner, parent: directory);
      // A dock tooltip still lingering elsewhere in the shell.
      final tip = _Owner('tip', log);
      openOne('tip', owner: tip, policy: TransientPolicy.tooltip);

      coordinator.dismissFromPointerDown(down(), within: flyout);

      expect(parentOwner.dismissals, 0);
      expect(flyoutOwner.dismissals, 0);
      expect(tip.dismissals, 1);
      expect(coordinator.openHandles,
          containsAll(<TransientHandle>[directory, flyout]));
    });
  });
}
