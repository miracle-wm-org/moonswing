import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:graceful_shell/modules/workspaces.dart';
import 'package:graceful_shell/scopes.dart';

/// Pumps the module the way a panel does: under the theme and Miracle scopes
/// the window chrome supplies. No [ShellServicesScope] — a module built alone
/// has no `main()` behind it, so `isLoading` answers false and nothing is
/// pending.
Future<void> pumpWorkspaces(WidgetTester tester, MiracleManager manager) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: MiracleScope(
          manager: manager,
          child: const Center(child: Workspaces()),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing at all when Miracle is unavailable',
      (tester) async {
    final manager = MiracleManager(socketPath: '');
    await pumpWorkspaces(tester, manager);

    // Neither the spinner (which would never come down) nor the retry button
    // (which would mean "this failed" and could never succeed).
    expect(find.byType(LoadingIndicator), findsNothing);
    expect(tester.getSize(find.byType(Workspaces)), Size.zero);
  });

  testWidgets('offers a retry when the socket exists but will not open',
      (tester) async {
    final manager =
        MiracleManager(socketPath: '/nonexistent/graceful-shell-test.sock');
    await manager.connect();
    await pumpWorkspaces(tester, manager);

    expect(manager.lastError, isNotNull);
    expect(tester.getSize(find.byType(Workspaces)), isNot(Size.zero));
  });
}
