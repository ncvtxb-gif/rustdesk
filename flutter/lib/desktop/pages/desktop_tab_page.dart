import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/desktop/widgets/enterprise_feishu_login_gate.dart';
import 'package:flutter_hbb/models/enterprise_oidc_flow.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);
  final _enterpriseLoginInProgress = false.obs;
  final _enterpriseLoginError = ''.obs;

  Future<void> _startEnterpriseFeishuLogin() async {
    if (_enterpriseLoginInProgress.value) return;
    _enterpriseLoginInProgress.value = true;
    _enterpriseLoginError.value = '';
    final configured = bind.mainGetBuildinOption(
        key: 'enterprise-feishu-oidc-op');
    final provider = configured.isEmpty ? '飞书登录' : configured;
    final flow = EnterpriseOidcFlow(
      queryOptions: UserModel.queryOidcLoginOptions,
      startAuth: ({required op, required rememberMe}) =>
          bind.mainAccountAuth(op: op, rememberMe: rememberMe),
      readAuthResult: () => bind.mainAccountAuthResult(),
      launchExternalUrl: (url) =>
          launchUrl(url, mode: LaunchMode.externalApplication),
      waitForNextPoll: () => Future.delayed(const Duration(seconds: 1)),
      onAuthBody: (authBody) async {
        final response = gFFI.userModel.getLoginResponseFromAuthBody(
          authBody,
          deferManagedIdentity: true,
        );
        if (!await gFFI.userModel.applyEnterpriseLoginResponse(response)) {
          throw const EnterpriseOidcException(
              'Failed to apply managed device identity');
        }
      },
    );
    try {
      await flow.start(configuredProvider: provider);
    } catch (e) {
      await bind.mainAccountAuthCancel();
      _enterpriseLoginError.value = e.toString();
    } finally {
      _enterpriseLoginInProgress.value = false;
    }
  }

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(
              controller: tabController,
              tail: Offstage(
                offstage: bind.isIncomingOnly() || bind.isDisableSettings(),
                child: ActionIcon(
                  message: 'Settings',
                  icon: IconFont.menu,
                  onTap: DesktopTabPage.onAddSetting,
                  isClose: false,
                ),
              ),
            )));
    final enterpriseBuild = bind.mainIsEnterpriseWindowsBuild();
    if (shouldUseEnterpriseWindowsGate(
        isWindows: isWindows, enterpriseBuild: enterpriseBuild)) {
      return Obx(() => EnterpriseFeishuLoginGate(
            state: gFFI.userModel.enterpriseAuthState.value,
            managedIdentityActive:
                gFFI.userModel.managedIdentityActive.value,
            errorText: _enterpriseLoginError.value.isNotEmpty
                ? _enterpriseLoginError.value
                : gFFI.userModel.networkError.value,
            loginInProgress: _enterpriseLoginInProgress.value,
            onStartDragging: windowManager.startDragging,
            onMinimize: windowManager.minimize,
            onClose: () => closeEnterpriseWindow(
              hide: windowManager.hide,
            ),
            onFeishuLogin: _startEnterpriseFeishuLogin,
            authenticatedChild: tabWidget,
          ));
    }
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}
