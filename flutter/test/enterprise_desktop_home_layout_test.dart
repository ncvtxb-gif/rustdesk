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
            accountButton: const SizedBox(),
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

  testWidgets('enterprise top cards align title and ID text baselines',
      (tester) async {
    final localIdController = TextEditingController(text: '214 650 118');
    addTearDown(localIdController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) => Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '远程标题参考',
                            key: const Key('remote-title-reference'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.merge(const TextStyle(height: 1)),
                          ),
                          const SizedBox(height: 15),
                          Container(
                            height: 57,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 13),
                            child: const Text(
                              '766 907 916',
                              key: Key('remote-id-reference'),
                              style: TextStyle(
                                fontFamily: 'WorkSans',
                                fontSize: 22,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: EnterpriseLocalIdCard(
                    idController: localIdController,
                    onCopy: () {},
                    accountButton: EnterpriseAccountButton(
                      displayName: '钟俊歌',
                      onLogout: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('你的桌面')).dy,
      closeTo(
          tester.getTopLeft(find.byKey(const Key('remote-title-reference'))).dy,
          2.5),
    );
    expect(
      tester.getTopLeft(find.text('214 650 118')).dy,
      closeTo(
          tester.getTopLeft(find.byKey(const Key('remote-id-reference'))).dy,
          0.5),
    );
    final titleCenter = tester.getCenter(find.text('你的桌面')).dy;
    final accountCenter =
        tester.getCenter(find.byKey(enterpriseAccountButtonKey)).dy;
    expect(accountCenter, closeTo(titleCenter, 4));
  });

  testWidgets('enterprise account menu shows Feishu name and logout',
      (tester) async {
    var logoutRequests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: EnterpriseAccountButton(
            displayName: '钟俊歌',
            onLogout: () => logoutRequests++,
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(enterpriseAccountButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('钟俊歌'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(logoutRequests, 1);
  });
}
