import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';

typedef BootstrapManagedIdentity = Future<bool> Function(String accessToken);
typedef ClearManagedIdentity = Future<void> Function();
typedef ClearLocalCredential = Future<void> Function();
typedef RetryDelay = Future<void> Function(Duration delay);

class EnterpriseClearResult {
  const EnterpriseClearResult._(this.success, this.error);

  const EnterpriseClearResult.success() : this._(true, '');
  const EnterpriseClearResult.failure(String error) : this._(false, error);

  final bool success;
  final String error;
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
}

Future<bool> installEnterpriseIdentityBridge() async {
  if (!bind.mainIsEnterpriseWindowsBuild()) return false;
  EnterpriseIdentityBridge.bootstrap = (accessToken) async {
    final error = await bind.mainBootstrapManagedIdentity(
      accessToken: accessToken,
    );
    return error.isEmpty;
  };
  EnterpriseIdentityBridge.clear = () async {
    final error = await bind.mainClearManagedIdentity();
    if (error.isNotEmpty) throw StateError(error);
  };
  return await bind.mainIsManagedIdentityActive();
}
