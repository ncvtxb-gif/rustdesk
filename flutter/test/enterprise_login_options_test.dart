import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/desktop/widgets/enterprise_feishu_login_gate.dart';
import 'package:flutter_hbb/models/enterprise_oidc_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise login options contain only configured Feishu provider', () {
    final options = [
      {'name': 'webauth', 'icon': 'web'},
      {'name': '飞书登录', 'icon': 'company'},
      {'name': 'another-oidc', 'icon': 'other'},
    ];
    expect(
      enterpriseFeishuLoginOptions(options, configuredProvider: '飞书登录'),
      [
        {'name': '飞书登录', 'icon': 'company'},
      ],
    );
  });

  test('enterprise login options reject WebAuth and duplicates', () {
    final options = [
      {'name': 'webauth'},
      {'name': '飞书登录', 'icon': 'first'},
      {'name': '飞书登录', 'icon': 'duplicate'},
    ];
    expect(
      enterpriseFeishuLoginOptions(options, configuredProvider: '飞书登录'),
      [
        {'name': '飞书登录', 'icon': 'first'},
      ],
    );
  });

  test('enterprise login options fail closed when provider is missing', () {
    expect(
      enterpriseFeishuLoginOptions([
        {'name': 'webauth'},
      ], configuredProvider: '飞书登录'),
      isEmpty,
    );
  });

  testWidgets('gate click starts direct Feishu OIDC without a dialog',
      (tester) async {
    var starts = 0;
    var launches = 0;
    final flow = EnterpriseOidcFlow(
      queryOptions: () async => [
        {'name': 'webauth'},
        {'name': '飞书登录'},
      ],
      startAuth: ({required op, required rememberMe}) async => starts++,
      readAuthResult: () async => jsonEncode({
        'state_msg': 'Waiting account auth',
        'failed_msg': '',
        'url': 'https://example.invalid/feishu',
        'auth_body': {'type': 'access_token'},
      }),
      launchExternalUrl: (_) async {
        launches++;
        return true;
      },
      waitForNextPoll: () async {},
      onAuthBody: (_) async {},
    );

    await tester.pumpWidget(MaterialApp(
      home: EnterpriseFeishuLoginGate(
        state: EnterpriseAuthState.unauthenticated,
        onFeishuLogin: () => flow.start(configuredProvider: '飞书登录'),
        authenticatedChild: const Text('desktop-content'),
      ),
    ));
    await tester.tap(find.byKey(enterpriseFeishuLoginButtonKey));
    await tester.pump();

    expect(find.byType(Dialog), findsNothing);
    expect(starts, 1);
    expect(launches, 1);
  });

  test('direct OIDC handles URL arriving after unchanged waiting state',
      () async {
    var polls = 0;
    var launches = 0;
    final flow = EnterpriseOidcFlow(
      queryOptions: () async => [
        {'name': '飞书登录'},
      ],
      startAuth: ({required op, required rememberMe}) async {},
      readAuthResult: () async {
        polls++;
        return jsonEncode({
          'state_msg': 'Waiting account auth',
          'failed_msg': '',
          'url': polls == 1 ? null : 'https://example.invalid/feishu',
          'auth_body': polls == 1 ? null : {'type': 'access_token'},
        });
      },
      launchExternalUrl: (_) async {
        launches++;
        return true;
      },
      waitForNextPoll: () async {},
      onAuthBody: (_) async {},
    );

    await flow.start(configuredProvider: '飞书登录');
    expect(launches, 1);
  });

  test('direct OIDC reports browser launch failure', () async {
    final flow = EnterpriseOidcFlow(
      queryOptions: () async => [
        {'name': '飞书登录'},
      ],
      startAuth: ({required op, required rememberMe}) async {},
      readAuthResult: () async => jsonEncode({
        'state_msg': 'Waiting account auth',
        'failed_msg': '',
        'url': 'https://example.invalid/feishu',
        'auth_body': null,
      }),
      launchExternalUrl: (_) async => false,
      waitForNextPoll: () async {},
      onAuthBody: (_) async {},
    );

    await expectLater(
      flow.start(configuredProvider: '飞书登录'),
      throwsA(isA<EnterpriseOidcException>().having(
          (e) => e.message, 'message', 'Failed to open system browser')),
    );
  });

  test('direct OIDC times out after bounded polling', () async {
    var polls = 0;
    final flow = EnterpriseOidcFlow(
      queryOptions: () async => [
        {'name': '飞书登录'},
      ],
      startAuth: ({required op, required rememberMe}) async {},
      readAuthResult: () async {
        polls++;
        return '';
      },
      launchExternalUrl: (_) async => true,
      waitForNextPoll: () async {},
      onAuthBody: (_) async {},
      maxPolls: 2,
    );

    await expectLater(
      flow.start(configuredProvider: '飞书登录'),
      throwsA(isA<EnterpriseOidcException>().having(
          (e) => e.message, 'message', 'Feishu login timed out')),
    );
    expect(polls, 2);
  });
}
