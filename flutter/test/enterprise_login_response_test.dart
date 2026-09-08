import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/enterprise_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final responseJson = {
    'type': 'access_token',
    'access_token': 'token',
    'user': {'name': 'alice', 'status': 1},
    'device': {
      'rustdesk_id': '123456789',
      'permanent_password': 'hidden-secret',
      'password_version': 2,
      'status': 'active',
    },
  };

  test('parses the optional managed device response', () {
    final response = LoginResponse.fromJson(responseJson);
    expect(response.device?.rustdeskId, '123456789');
    expect(response.device?.permanentPassword, 'hidden-secret');
    expect(response.device?.passwordVersion, 2);
  });

  test('enterprise login succeeds only after identity application', () async {
    final response = LoginResponse.fromJson(responseJson);
    final coordinator = EnterpriseIdentityCoordinator(
      apply: (_) async => true,
      rollback: () async {},
    );
    expect(await coordinator.applyLogin(response), isTrue);
  });

  test('missing device or apply failure rolls back and fails closed', () async {
    var rollbacks = 0;
    final coordinator = EnterpriseIdentityCoordinator(
      apply: (_) async => false,
      rollback: () async {
        rollbacks++;
      },
    );
    expect(
      await coordinator.applyLogin(LoginResponse.fromJson(responseJson)),
      isFalse,
    );
    expect(
      await coordinator.applyLogin(LoginResponse.fromJson({
        'type': 'access_token',
        'access_token': 'token',
        'user': {'name': 'alice', 'status': 1},
      })),
      isFalse,
    );
    expect(rollbacks, 2);
  });

  test('identity application exception rolls back and fails closed', () async {
    var rolledBack = false;
    final coordinator = EnterpriseIdentityCoordinator(
      apply: (_) async => throw StateError('apply failed'),
      rollback: () async {
        rolledBack = true;
      },
    );

    expect(
      await coordinator.applyLogin(LoginResponse.fromJson(responseJson)),
      isFalse,
    );
    expect(rolledBack, isTrue);
  });
}
