import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/enterprise_feishu_login_gate.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise close hides the window without allowing process exit',
      () async {
    final calls = <String>[];

    await closeEnterpriseWindow(
      hide: () async => calls.add('hide'),
    );

    expect(calls, ['hide']);
  });

  test('enterprise gate is limited to enterprise Windows builds', () {
    expect(
      shouldUseEnterpriseWindowsGate(isWindows: true, enterpriseBuild: true),
      isTrue,
    );
    expect(
      shouldUseEnterpriseWindowsGate(isWindows: false, enterpriseBuild: true),
      isFalse,
    );
    expect(
      shouldUseEnterpriseWindowsGate(isWindows: true, enterpriseBuild: false),
      isFalse,
    );
  });

  test('enterprise policy hides password network and discovery surfaces', () {
    const policy = EnterpriseUiPolicy.enabled;
    expect(policy.showPasswordBoard, isFalse);
    expect(policy.showPasswordSettings, isFalse);
    expect(policy.showNetworkSettings, isFalse);
    expect(policy.showDiscoveryTab, isFalse);
    expect(policy.allowSoftwareUpdates, isFalse);
    expect(policy.allowProcessExit, isFalse);
    expect(EnterpriseUiPolicy.disabled.showPasswordBoard, isTrue);
    expect(EnterpriseUiPolicy.disabled.allowSoftwareUpdates, isTrue);
    expect(EnterpriseUiPolicy.disabled.allowProcessExit, isTrue);
  });

  test('enterprise Windows remains resident after its last window closes', () {
    expect(
      shouldKeepEnterpriseClientResident(
          isWindows: true, enterpriseBuild: true),
      isTrue,
    );
    expect(
      shouldKeepEnterpriseClientResident(
          isWindows: true, enterpriseBuild: false),
      isFalse,
    );
    expect(
      shouldKeepEnterpriseClientResident(
          isWindows: false, enterpriseBuild: true),
      isFalse,
    );
  });

  testWidgets('hidden update card leaves a uniformly painted sidebar',
      (tester) async {
    const sidebar = Color(0xFFEFEFF2);
    const exposedWindowBackground = Color(0xFFC3C3C3);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(background: sidebar),
      ),
      home: const Center(
        child: SizedBox(
          width: 200,
          height: 500,
          child: ColoredBox(
            color: exposedWindowBackground,
            child: Column(
              children: [
                SizedBox(height: 100),
                Expanded(child: DesktopLeftPaneRemainder()),
              ],
            ),
          ),
        ),
      ),
    ));

    final surface = tester.widget<ColoredBox>(
        find.byKey(desktopLeftPaneRemainderKey));
    expect(surface.color, sidebar);
    expect(
      tester.getSize(find.byKey(desktopLeftPaneRemainderKey)),
      const Size(200, 400),
      reason: 'the surface must paint the complete width below the ID panel',
    );
  });

  testWidgets('unauthenticated gate exposes only the Feishu action',
      (tester) async {
    var loginRequests = 0;
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.unauthenticated,
        onFeishuLogin: () async {
          loginRequests++;
        },
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsNothing);
    expect(find.byKey(enterpriseFeishuLoginButtonKey), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(enterpriseCloseButtonKey), findsOneWidget);

    await tester.tap(find.byKey(enterpriseFeishuLoginButtonKey));
    await tester.pump();
    expect(loginRequests, 1);
  });

  testWidgets('enterprise gate title bar exposes drag minimize and close',
      (tester) async {
    var drags = 0;
    var minimizes = 0;
    var closes = 0;
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.unauthenticated,
        onStartDragging: () async => drags++,
        onMinimize: () async => minimizes++,
        onClose: () async => closes++,
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    await tester.drag(find.byKey(enterpriseTitleBarDragAreaKey),
        const Offset(20, 0));
    await tester.tap(find.byKey(enterpriseMinimizeButtonKey));
    await tester.tap(find.byKey(enterpriseCloseButtonKey));
    await tester.pump();

    expect(drags, 1);
    expect(minimizes, 1);
    expect(closes, 1);
  });

  testWidgets('fail-closed gate displays managed identity clear error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.unauthenticated,
        managedIdentityActive: true,
        errorText: 'Failed to clear managed identity after retries',
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsNothing);
    expect(find.text('Failed to clear managed identity after retries'),
        findsOneWidget);
  });

  testWidgets('gate displays system browser launch failure', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.unauthenticated,
        errorText: 'Failed to open system browser',
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('Failed to open system browser'), findsOneWidget);
  });

  testWidgets('authenticated gate restores the original desktop content',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.authenticated,
        managedIdentityActive: true,
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsOneWidget);
    expect(find.byKey(enterpriseFeishuLoginButtonKey), findsNothing);
  });

  testWidgets('checking state never exposes desktop content', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.checking,
        managedIdentityActive: false,
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(enterpriseTitleBarDragAreaKey), findsOneWidget);
    expect(find.byKey(enterpriseMinimizeButtonKey), findsOneWidget);
    expect(find.byKey(enterpriseCloseButtonKey), findsOneWidget);
  });

  testWidgets('offline grace fails closed without an applied managed identity',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.offlineGrace,
        managedIdentityActive: false,
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsNothing);
    expect(find.byKey(enterpriseFeishuLoginButtonKey), findsOneWidget);
  });

  testWidgets('offline grace restores content only for an applied identity',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.offlineGrace,
        managedIdentityActive: true,
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsOneWidget);
  });
}
