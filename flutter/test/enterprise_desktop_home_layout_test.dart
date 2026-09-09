import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/enterprise_desktop_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'enterprise home uses equal top cards and full-width peer content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EnterpriseDesktopHomeLayout(
            remoteCard: ColoredBox(color: Colors.white),
            localIdCard: ColoredBox(color: Colors.white),
            peerContent: ColoredBox(color: Colors.white),
            statusBar: SizedBox(height: 28),
          ),
        ),
      ),
    );

    final remoteSize = tester.getSize(find.byKey(enterpriseRemoteCardKey));
    final localSize = tester.getSize(find.byKey(enterpriseLocalIdCardKey));
    final peerSize = tester.getSize(find.byKey(enterprisePeerContentKey));

    expect(remoteSize, localSize);
    expect(remoteSize.width, greaterThan(500));
    expect(peerSize.width, greaterThan(1200));
  });

  testWidgets('enterprise local ID card keeps copy behavior without a menu',
      (tester) async {
    var copyRequests = 0;
    final idController = TextEditingController(text: '214 650 118');
    addTearDown(idController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnterpriseLocalIdCard(
            idController: idController,
            onCopy: () => copyRequests++,
          ),
        ),
      ),
    );

    expect(find.text('你的桌面'), findsOneWidget);
    expect(find.text('你的桌面可以通过下面的 ID 进行远程访问。'), findsOneWidget);
    expect(find.text('ID'), findsOneWidget);
    expect(find.text('214 650 118'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_outlined), findsNothing);

    await tester.tap(find.text('214 650 118'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('214 650 118'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(copyRequests, 1);
  });
}
