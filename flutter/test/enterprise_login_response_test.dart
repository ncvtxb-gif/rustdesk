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

  test('parses login token and user without requiring managed secrets', () {
    final response = LoginResponse.fromJson({
      'type': 'access_token',
      'access_token': 'token',
      'user': {'name': 'alice', 'status': 1},
    });
    expect(response.access_token, 'token');
    expect(response.user?.name, 'alice');
  });

  test('enterprise login bootstraps Rust using access token only', () async {
    final response = LoginResponse.fromJson(responseJson);
    String? bootstrappedToken;
    final coordinator = EnterpriseIdentityCoordinator(
      bootstrap: (accessToken) async {
        bootstrappedToken = accessToken;
        return true;
      },
      clear: () async {},
    );
    expect(await coordinator.applyLogin(response), isTrue);
    expect(bootstrappedToken, 'token');
  });

  test('device payload is not required and bootstrap failure clears', () async {
    var clears = 0;
    final coordinator = EnterpriseIdentityCoordinator(
      bootstrap: (_) async => false,
      clear: () async {
        clears++;
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
    expect(clears, 2);
  });

  test('bootstrap exception clears and fails closed', () async {
    var cleared = false;
    final coordinator = EnterpriseIdentityCoordinator(
      bootstrap: (_) async => throw StateError('bootstrap failed'),
      clear: () async {
        cleared = true;
      },
    );

    expect(
      await coordinator.applyLogin(LoginResponse.fromJson(responseJson)),
      isFalse,
    );
    expect(cleared, isTrue);
  });

  test('missing token or user never calls bootstrap and clears', () async {
    var bootstrapCalls = 0;
    var clears = 0;
    final coordinator = EnterpriseIdentityCoordinator(
      bootstrap: (_) async {
        bootstrapCalls++;
        return true;
      },
      clear: () async {
        clears++;
      },
    );

    expect(
      await coordinator.applyLogin(LoginResponse.fromJson({
        'type': 'access_token',
        'user': {'name': 'alice', 'status': 1},
      })),
      isFalse,
    );
    expect(
      await coordinator.applyLogin(LoginResponse.fromJson({
        'type': 'access_token',
        'access_token': 'token',
      })),
      isFalse,
    );
    expect(bootstrapCalls, 0);
    expect(clears, 2);
  });

  test('session clear awaits identity clear before deleting credentials',
      () async {
    final events = <String>[];

    await clearEnterpriseSession(
      clearIdentity: () async {
        events.add('identity-start');
        await Future<void>.delayed(Duration.zero);
        events.add('identity-done');
        throw StateError('idempotent service clear failed');
      },
      clearToken: () async => events.add('token'),
      clearUser: () async => events.add('user'),
    );

    expect(events,
        ['identity-start', 'identity-done', 'token', 'user']);
  });
}
