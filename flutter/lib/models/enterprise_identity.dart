import 'package:flutter_hbb/common/hbbs/hbbs.dart';

typedef BootstrapManagedIdentity = Future<bool> Function(String accessToken);
typedef ClearManagedIdentity = Future<void> Function();
typedef ClearLocalCredential = Future<void> Function();

Future<void> clearEnterpriseSession({
  required ClearManagedIdentity clearIdentity,
  required ClearLocalCredential clearToken,
  required ClearLocalCredential clearUser,
}) async {
  try {
    await clearIdentity();
  } catch (_) {
    // Local credentials must still be removed if the idempotent service call
    // cannot be completed (for example because the service has stopped).
  }
  await clearToken();
  await clearUser();
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
