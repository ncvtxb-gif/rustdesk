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
      'password_version': 2,
      'status': 'active',
    },
  };

  test('parses login token and user without requiring managed secrets', () {
    final response = LoginResponse.fromJson({
      'type': 'access_token',
      'access_token': 'token',
      'user': {'name': 'alice', 'status': 1},
      'device': {
        'rustdesk_id': '123456789',
        'password_version': 2,
        'status': 'active',
      },
    });
    expect(response.access_token, 'token');
    expect(response.user?.name, 'alice');
  });

  test('renewal policy adds bounded jitter to avoid startup bursts', () {
    const policy = EnterpriseRenewalPolicy();
    expect(policy.initialDelay, Duration.zero);
    expect(policy.normalDelay(0), const Duration(hours: 6));
    expect(policy.normalDelay(1), const Duration(hours: 6, minutes: 30));
    expect(policy.retryDelay(0), const Duration(minutes: 5));
    expect(policy.retryDelay(1), const Duration(minutes: 6));
  });

  test('startup renewal is jittered while identity has a safe lifetime', () {
    const policy = EnterpriseRenewalPolicy();
    expect(policy.startupDelay(const Duration(hours: 12), 0), Duration.zero);
    expect(policy.startupDelay(const Duration(hours: 12), 1),
        const Duration(minutes: 5));
  });

  test('startup renewal never crosses the local expiry safety margin', () {
    const policy = EnterpriseRenewalPolicy();
    expect(policy.startupDelay(const Duration(minutes: 4), 1),
        const Duration(minutes: 2));
    expect(policy.startupDelay(const Duration(minutes: 2), 1), Duration.zero);
    expect(policy.startupDelay(Duration.zero, 1), Duration.zero);
  });

  test('inactive marker stops polling before scheduling renewal retry', () {
    expect(
      enterpriseActivePollAction(true),
      EnterpriseActivePollAction.continuePolling,
    );
    expect(
      enterpriseActivePollAction(false),
      EnterpriseActivePollAction.stopAndRetry,
    );
  });

  test('renewal keeps an old valid identity on transient network failure',
      () async {
    final renewal = EnterpriseIdentityRenewal(
      renewCall: (_) async => 'managed device bootstrap request failed',
      isActive: () async => true,
    );
    expect((await renewal.renew('token')).result,
        EnterpriseRenewalResult.offlineValid);
  });

  test('renewal fails closed once the old identity has expired', () async {
    final renewal = EnterpriseIdentityRenewal(
      renewCall: (_) async => 'managed device bootstrap request failed',
      isActive: () async => false,
    );
    final outcome = await renewal.renew('token');
    expect(outcome.result, EnterpriseRenewalResult.expired);
    expect(enterpriseRenewalFailureMessage(outcome),
        contains('managed device bootstrap request failed'));
  });

  test('renewal rejects server auth or device denial while old marker is valid',
      () async {
    for (final status in [401, 403]) {
      final renewal = EnterpriseIdentityRenewal(
        renewCall: (_) async =>
            'managed device bootstrap was rejected with HTTP $status',
        isActive: () async => true,
      );
      expect((await renewal.renew('token')).result,
          EnterpriseRenewalResult.revoked);
    }
  });

  test('renewal preserves actionable service error when identity is inactive',
      () async {
    final renewal = EnterpriseIdentityRenewal(
      renewCall: (_) async => 'managed device auth hash upload timed out',
      isActive: () async => false,
    );

    final outcome = await renewal.renew('token');
    expect(outcome.result, EnterpriseRenewalResult.expired);
    expect(outcome.error, 'managed device auth hash upload timed out');
    expect(enterpriseRenewalFailureMessage(outcome),
        contains('managed device auth hash upload timed out'));
    expect(enterpriseRenewalFailureMessage(outcome), isNot(contains('sign in')));
  });

  test('only explicit unauthorized responses require a new login', () async {
    for (final status in [401, 403]) {
      final outcome = await EnterpriseIdentityRenewal(
        renewCall: (_) async =>
            'managed device bootstrap was rejected with HTTP $status',
        isActive: () async => false,
      ).renew('token');
      expect(outcome.result, EnterpriseRenewalResult.revoked);
      expect(enterpriseRenewalFailureMessage(outcome), contains('sign in again'));
    }

    final badRequest = await EnterpriseIdentityRenewal(
      renewCall: (_) async =>
          'managed device bootstrap was rejected with HTTP 400',
      isActive: () async => false,
    ).renew('token');
    expect(badRequest.result, EnterpriseRenewalResult.expired);
    expect(badRequest.error, contains('HTTP 400'));
    expect(
        enterpriseRenewalFailureMessage(badRequest), isNot(contains('sign in')));
  });

  test('identity operation queue orders logout clear after active renewal',
      () async {
    final queue = EnterpriseIdentityOperationQueue();
    final events = <String>[];
    final renewal = queue.run(() async {
      events.add('renew-start');
      await Future<void>.delayed(Duration.zero);
      events.add('renew-active');
    });
    final logout = queue.run(() async => events.add('logout-clear'));

    await Future.wait([renewal, logout]);
    expect(events, ['renew-start', 'renew-active', 'logout-clear']);
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

  test('successful enterprise login synchronizes administrator device credentials',
      () async {
    final events = <String>[];

    final applied = await completeEnterpriseLogin(
      administrator: true,
      applyIdentity: () async {
        events.add('identity');
        return true;
      },
      syncDeviceCredentials: () async {
        events.add('credentials');
        return true;
      },
      rollbackIdentity: () async => events.add('rollback'),
    );

    expect(applied, isTrue);
    expect(events, ['identity', 'credentials']);
  });

  test('failed enterprise identity never synchronizes device credentials',
      () async {
    final events = <String>[];

    final applied = await completeEnterpriseLogin(
      administrator: true,
      applyIdentity: () async {
        events.add('identity');
        return false;
      },
      syncDeviceCredentials: () async {
        events.add('credentials');
        return true;
      },
      rollbackIdentity: () async => events.add('rollback'),
    );

    expect(applied, isFalse);
    expect(events, ['identity']);
  });

  test('ordinary enterprise login never synchronizes administrator credentials',
      () async {
    final events = <String>[];

    final applied = await completeEnterpriseLogin(
      administrator: false,
      applyIdentity: () async {
        events.add('identity');
        return true;
      },
      syncDeviceCredentials: () async {
        events.add('credentials');
        return true;
      },
      rollbackIdentity: () async => events.add('rollback'),
    );

    expect(applied, isTrue);
    expect(events, ['identity']);
  });

  test('administrator credential sync failure rolls back managed identity',
      () async {
    final events = <String>[];

    final applied = await completeEnterpriseLogin(
      administrator: true,
      applyIdentity: () async {
        events.add('identity');
        return true;
      },
      syncDeviceCredentials: () async {
        events.add('credentials');
        return false;
      },
      rollbackIdentity: () async => events.add('rollback'),
    );

    expect(applied, isFalse);
    expect(events, ['identity', 'credentials', 'rollback']);
  });

  test('administrator credential sync exception rolls back managed identity',
      () async {
    final events = <String>[];

    final applied = await completeEnterpriseLogin(
      administrator: true,
      applyIdentity: () async {
        events.add('identity');
        return true;
      },
      syncDeviceCredentials: () async {
        events.add('credentials');
        throw StateError('group sync failed');
      },
      rollbackIdentity: () async => events.add('rollback'),
    );

    expect(applied, isFalse);
    expect(events, ['identity', 'credentials', 'rollback']);
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

  test('session clear retries and retains credentials after identity failure',
      () async {
    final events = <String>[];

    final result = await clearEnterpriseSession(
      clearIdentity: () async {
        events.add('identity');
        throw StateError('idempotent service clear failed');
      },
      clearToken: () async => events.add('token'),
      clearUser: () async => events.add('user'),
      clearCaches: () async => events.add('caches'),
      retryDelay: (_) async {},
    );

    expect(result.success, isFalse);
    expect(result.error, contains('idempotent service clear failed'));
    expect(events, ['identity', 'identity', 'identity', 'caches']);
  });

  test('session clear deletes credentials only after service clear succeeds',
      () async {
    final events = <String>[];
    var attempts = 0;

    final result = await clearEnterpriseSession(
      clearIdentity: () async {
        attempts++;
        events.add('identity-$attempts');
        if (attempts == 1) throw StateError('transient');
      },
      clearToken: () async => events.add('token'),
      clearUser: () async => events.add('user'),
      clearCaches: () async => events.add('caches'),
      retryDelay: (_) async {},
    );

    expect(result.success, isTrue);
    expect(events, ['identity-1', 'identity-2', 'token', 'user', 'caches']);
  });

  test('logout notifies API only after managed identity clear', () async {
    final events = <String>[];
    final result = await completeEnterpriseLogout(
      clearIdentity: () async => events.add('identity'),
      clearCaches: () async => events.add('caches'),
      notifyRemoteLogout: () async => events.add('api'),
      clearToken: () async => events.add('token'),
      clearUser: () async => events.add('user'),
      retryDelay: (_) async {},
    );
    expect(result.success, isTrue);
    expect(events, ['identity', 'caches', 'api', 'token', 'user']);
  });

  test('logout does not notify API or delete credentials when clear fails',
      () async {
    final events = <String>[];
    final result = await completeEnterpriseLogout(
      clearIdentity: () async => throw StateError('service active'),
      clearCaches: () async => events.add('caches'),
      notifyRemoteLogout: () async => events.add('api'),
      clearToken: () async => events.add('token'),
      clearUser: () async => events.add('user'),
      retryDelay: (_) async {},
    );
    expect(result.success, isFalse);
    expect(events, ['caches']);
  });
}
