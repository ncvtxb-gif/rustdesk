import 'dart:async';

import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';

typedef BootstrapManagedIdentity = Future<bool> Function(String accessToken);
typedef RenewManagedIdentity = Future<String> Function(String accessToken);
typedef ClearManagedIdentity = Future<void> Function();
typedef IsManagedIdentityActive = Future<bool> Function();
typedef ManagedIdentityRemainingSeconds = Future<int> Function();
typedef ClearLocalCredential = Future<void> Function();
typedef RetryDelay = Future<void> Function(Duration delay);
typedef RemoteLogout = Future<void> Function();

class EnterpriseClearResult {
  const EnterpriseClearResult._(this.success, this.error);

  const EnterpriseClearResult.success() : this._(true, '');
  const EnterpriseClearResult.failure(String error) : this._(false, error);

  final bool success;
  final String error;
}

enum EnterpriseRenewalResult { renewed, offlineValid, expired, revoked }

enum EnterpriseActivePollAction { continuePolling, stopAndRetry }

EnterpriseActivePollAction enterpriseActivePollAction(bool active) => active
    ? EnterpriseActivePollAction.continuePolling
    : EnterpriseActivePollAction.stopAndRetry;

class EnterpriseRenewalPolicy {
  const EnterpriseRenewalPolicy({
    this.interval = const Duration(hours: 6),
    this.jitterWindow = const Duration(minutes: 30),
    this.retryInterval = const Duration(minutes: 5),
    this.retryJitterWindow = const Duration(minutes: 1),
    this.startupJitterWindow = const Duration(minutes: 5),
    this.expirySafetyMargin = const Duration(minutes: 2),
  });

  final Duration interval;
  final Duration jitterWindow;
  final Duration retryInterval;
  final Duration retryJitterWindow;
  final Duration startupJitterWindow;
  final Duration expirySafetyMargin;
  Duration get initialDelay => Duration.zero;

  Duration normalDelay(double randomUnit) =>
      _withJitter(interval, jitterWindow, randomUnit);
  Duration retryDelay(double randomUnit) =>
      _withJitter(retryInterval, retryJitterWindow, randomUnit);
  Duration startupDelay(Duration remaining, double randomUnit) {
    final safeRemaining = remaining - expirySafetyMargin;
    if (safeRemaining <= Duration.zero) return Duration.zero;
    final jitter = _withJitter(Duration.zero, startupJitterWindow, randomUnit);
    return jitter < safeRemaining ? jitter : safeRemaining;
  }

  Duration _withJitter(
      Duration base, Duration window, double randomUnit) {
    final bounded = randomUnit.clamp(0.0, 1.0);
    return base +
        Duration(
            milliseconds: (window.inMilliseconds * bounded).round());
  }
}

class EnterpriseIdentityRenewal {
  const EnterpriseIdentityRenewal({
    required this.renewCall,
    required this.isActive,
  });

  final RenewManagedIdentity renewCall;
  final IsManagedIdentityActive isActive;

  Future<EnterpriseRenewalResult> renew(String accessToken) async {
    if (accessToken.isEmpty) return EnterpriseRenewalResult.expired;
    String error;
    try {
      error = await renewCall(accessToken);
    } catch (e) {
      error = e.toString();
    }
    if (error.isEmpty) return EnterpriseRenewalResult.renewed;
    if (error.contains('HTTP 400') ||
        error.contains('HTTP 401') ||
        error.contains('HTTP 403')) {
      return EnterpriseRenewalResult.revoked;
    }
    try {
      return await isActive()
          ? EnterpriseRenewalResult.offlineValid
          : EnterpriseRenewalResult.expired;
    } catch (_) {
      return EnterpriseRenewalResult.expired;
    }
  }
}

class EnterpriseIdentityOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (e, stackTrace) {
        completer.completeError(e, stackTrace);
      }
    });
    return completer.future;
  }
}

Future<EnterpriseClearResult> clearEnterpriseSession({
  required ClearManagedIdentity clearIdentity,
  required ClearLocalCredential clearToken,
  required ClearLocalCredential clearUser,
  required ClearLocalCredential clearCaches,
  int maxAttempts = 3,
  RetryDelay retryDelay = Future<void>.delayed,
}) async {
  Object? lastError;
  var identityCleared = false;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await clearIdentity();
      identityCleared = true;
      break;
    } catch (e) {
      lastError = e;
      if (attempt < maxAttempts) {
        await retryDelay(Duration(milliseconds: 100 * attempt));
      }
    }
  }
  if (identityCleared) {
    await clearToken();
    await clearUser();
  }
  // Cached unattended hashes are never retained after a logout/401 attempt.
  try {
    await clearCaches();
  } catch (e) {
    return EnterpriseClearResult.failure('failed to clear auth caches: $e');
  }
  return identityCleared
      ? const EnterpriseClearResult.success()
      : EnterpriseClearResult.failure(lastError.toString());
}

Future<EnterpriseClearResult> completeEnterpriseLogout({
  required ClearManagedIdentity clearIdentity,
  required ClearLocalCredential clearCaches,
  required RemoteLogout notifyRemoteLogout,
  required ClearLocalCredential clearToken,
  required ClearLocalCredential clearUser,
  int maxAttempts = 3,
  RetryDelay retryDelay = Future<void>.delayed,
}) async {
  final result = await clearEnterpriseSession(
    clearIdentity: clearIdentity,
    clearToken: () async {},
    clearUser: () async {},
    clearCaches: clearCaches,
    maxAttempts: maxAttempts,
    retryDelay: retryDelay,
  );
  if (!result.success) return result;
  try {
    await notifyRemoteLogout();
  } catch (_) {
    // Local logout remains authoritative once the service identity is clear.
  }
  await clearToken();
  await clearUser();
  return const EnterpriseClearResult.success();
}

class EnterpriseIdentityCoordinator {
  const EnterpriseIdentityCoordinator({
    required this.bootstrap,
    required this.clear,
  });

  final BootstrapManagedIdentity bootstrap;
  final ClearManagedIdentity clear;

  Future<bool> applyLogin(LoginResponse response) async {
    final accessToken = response.access_token;
    if (accessToken == null || accessToken.isEmpty || response.user == null) {
      await clear();
      return false;
    }
    var bootstrapped = false;
    try {
      bootstrapped = await bootstrap(accessToken);
    } catch (_) {
      bootstrapped = false;
    }
    if (!bootstrapped) {
      await clear();
      return false;
    }
    return true;
  }
}

class EnterpriseIdentityBridge {
  static BootstrapManagedIdentity bootstrap = (_) async => false;
  static ClearManagedIdentity clear = () async {};
  static IsManagedIdentityActive isActive = () async => false;
  static ManagedIdentityRemainingSeconds remainingSeconds = () async => 0;
  static RenewManagedIdentity renew = (_) async => 'unavailable';
}

Future<bool> installEnterpriseIdentityBridge() async {
  if (!bind.mainIsEnterpriseWindowsBuild()) return false;
  EnterpriseIdentityBridge.bootstrap = (accessToken) async {
    final error = await EnterpriseIdentityBridge.renew(accessToken);
    return error.isEmpty;
  };
  EnterpriseIdentityBridge.renew = (accessToken) async {
    return await bind.mainBootstrapManagedIdentity(
      accessToken: accessToken,
    );
  };
  EnterpriseIdentityBridge.clear = () async {
    final error = await bind.mainClearManagedIdentity();
    if (error.isNotEmpty) throw StateError(error);
  };
  EnterpriseIdentityBridge.isActive = () => bind.mainIsManagedIdentityActive();
  EnterpriseIdentityBridge.remainingSeconds =
      () => bind.mainManagedIdentityRemainingSeconds();
  return await EnterpriseIdentityBridge.isActive();
}
