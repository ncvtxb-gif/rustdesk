import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/enterprise_auth_state.dart';

export 'package:flutter_hbb/models/enterprise_auth_state.dart';

const enterpriseFeishuLoginButtonKey = Key('enterprise-feishu-login');
const enterpriseTitleBarDragAreaKey = Key('enterprise-titlebar-drag-area');
const enterpriseMinimizeButtonKey = Key('enterprise-titlebar-minimize');
const enterpriseCloseButtonKey = Key('enterprise-titlebar-close');

bool shouldUseEnterpriseWindowsGate({
  required bool isWindows,
  required bool enterpriseBuild,
}) =>
    isWindows && enterpriseBuild;

bool shouldKeepEnterpriseClientResident({
  required bool isWindows,
  required bool enterpriseBuild,
}) =>
    isWindows && enterpriseBuild;

Future<void> closeEnterpriseWindow({
  required Future<void> Function() hide,
}) async {
  await hide();
}

class EnterpriseUiPolicy {
  const EnterpriseUiPolicy._(this.active);

  static const enabled = EnterpriseUiPolicy._(true);
  static const disabled = EnterpriseUiPolicy._(false);

  final bool active;
  bool get showPasswordBoard => !active;
  bool get showPasswordSettings => !active;
  bool get showNetworkSettings => !active;
  bool get showDiscoveryTab => !active;
  bool get allowSoftwareUpdates => !active;
  bool get allowProcessExit => !active;
}

class EnterpriseFeishuLoginGate extends StatelessWidget {
  const EnterpriseFeishuLoginGate({
    super.key,
    required this.state,
    this.managedIdentityActive = false,
    this.errorText = '',
    this.onStartDragging,
    this.onMinimize,
    this.onClose,
    this.loginInProgress = false,
    required this.onFeishuLogin,
    required this.authenticatedChild,
  });

  final EnterpriseAuthState state;
  final bool managedIdentityActive;
  final String errorText;
  final Future<void> Function()? onStartDragging;
  final Future<void> Function()? onMinimize;
  final Future<void> Function()? onClose;
  final bool loginInProgress;
  final Future<void> Function() onFeishuLogin;
  final Widget authenticatedChild;

  @override
  Widget build(BuildContext context) {
    if (managedIdentityActive &&
        (state == EnterpriseAuthState.authenticated ||
            state == EnterpriseAuthState.offlineGrace)) {
      return authenticatedChild;
    }
    return Scaffold(
      body: Column(children: [
        SizedBox(
          height: 36,
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                key: enterpriseTitleBarDragAreaKey,
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onStartDragging?.call(),
                child: const SizedBox.expand(),
              ),
            ),
            IconButton(
              key: enterpriseMinimizeButtonKey,
              tooltip: 'Minimize',
              onPressed: onMinimize,
              icon: const Icon(Icons.remove, size: 18),
            ),
            IconButton(
              key: enterpriseCloseButtonKey,
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
        ),
        Expanded(
          child: state == EnterpriseAuthState.checking
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.business_rounded, size: 56),
                        const SizedBox(height: 24),
                        const Text('登录后才可使用远程桌面',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 20),
                        if (errorText.isNotEmpty) ...[
                          Text(errorText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error)),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: enterpriseFeishuLoginButtonKey,
                            onPressed:
                                loginInProgress ? null : onFeishuLogin,
                            icon: loginInProgress
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ))
                                : const Icon(Icons.login),
                            label: const Text('使用飞书登录'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}
