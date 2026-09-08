import 'package:flutter_hbb/common/hbbs/hbbs.dart';

typedef ApplyManagedIdentity = Future<bool> Function(
    ManagedDevicePayload device);
typedef RollbackManagedIdentity = Future<void> Function();

class EnterpriseIdentityCoordinator {
  const EnterpriseIdentityCoordinator({
    required this.apply,
    required this.rollback,
  });

  final ApplyManagedIdentity apply;
  final RollbackManagedIdentity rollback;

  Future<bool> applyLogin(LoginResponse response) async {
    final device = response.device;
    if (response.access_token == null ||
        response.user == null ||
        device == null ||
        !device.isValid) {
      await rollback();
      return false;
    }
    var applied = false;
    try {
      applied = await apply(device);
    } catch (_) {
      applied = false;
    }
    if (!applied) {
      await rollback();
      return false;
    }
    return true;
  }
}

class EnterpriseIdentityBridge {
  static ApplyManagedIdentity apply = (_) async => false;
  static RollbackManagedIdentity rollback = () async {};
}
