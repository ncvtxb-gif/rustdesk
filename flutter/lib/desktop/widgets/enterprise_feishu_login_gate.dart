import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/enterprise_auth_state.dart';

export 'package:flutter_hbb/models/enterprise_auth_state.dart';

const enterpriseFeishuLoginButtonKey = Key('enterprise-feishu-login');

bool shouldUseEnterpriseWindowsGate({
  required bool isWindows,
  required bool enterpriseBuild,
}) =>
    isWindows && enterpriseBuild;

class EnterpriseUiPolicy {
  const EnterpriseUiPolicy._(this.active);

  static const enabled = EnterpriseUiPolicy._(true);
  static const disabled = EnterpriseUiPolicy._(false);

  final bool active;
  bool get showPasswordBoard => !active;
  bool get showPasswordSettings => !active;
  bool get showNetworkSettings => !active;
  bool get showDiscoveryTab => !active;
}

class EnterpriseFeishuLoginGate extends StatelessWidget {
  const EnterpriseFeishuLoginGate({
    super.key,
    required this.state,
    this.managedIdentityActive = false,
    this.errorText = '',
    required this.onFeishuLogin,
    required this.authenticatedChild,
  });

  final EnterpriseAuthState state;
  final bool managedIdentityActive;
  final String errorText;
  final Future<void> Function() onFeishuLogin;
  final Widget authenticatedChild;

  @override
  Widget build(BuildContext context) {
    if (managedIdentityActive &&
        (state == EnterpriseAuthState.authenticated ||
            state == EnterpriseAuthState.offlineGrace)) {
      return authenticatedChild;
    }
    if (state == EnterpriseAuthState.checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.business_rounded, size: 56),
              const SizedBox(height: 24),
              const Text('登录后才可使用远程桌面',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              if (errorText.isNotEmpty) ...[
                Text(errorText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: enterpriseFeishuLoginButtonKey,
                  onPressed: onFeishuLogin,
                  icon: const Icon(Icons.login),
                  label: const Text('使用飞书登录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
