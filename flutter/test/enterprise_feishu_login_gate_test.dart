import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/enterprise_feishu_login_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(find.byKey(enterpriseFeishuLoginButtonKey));
    await tester.pump();
    expect(loginRequests, 1);
  });

  testWidgets('authenticated gate restores the original desktop content',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.authenticated,
        onFeishuLogin: () async {},
        authenticatedChild: const Text('desktop-content'),
      ),
    ));

    expect(find.text('desktop-content'), findsOneWidget);
    expect(find.byKey(enterpriseFeishuLoginButtonKey), findsNothing);
  });
}
