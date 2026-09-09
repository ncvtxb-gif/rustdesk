import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';
import 'enterprise_auth_state.dart';
import 'enterprise_identity.dart';

bool refreshingUser = false;

class UserModel {
  static const _renewalPolicy = EnterpriseRenewalPolicy();
  final _identityOperations = EnterpriseIdentityOperationQueue();
  Timer? _managedRenewalTimer;
  Timer? _managedActivePollTimer;
  int _identityGeneration = 0;
  final RxString userName = ''.obs;
  final RxString displayName = ''.obs;
  final RxString avatar = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  final Rx<EnterpriseAuthState> enterpriseAuthState =
      EnterpriseAuthState.checking.obs;
  final RxBool managedIdentityActive = false.obs;
  bool get isLogin => userName.isNotEmpty;
  String get displayNameOrUserName =>
      displayName.value.trim().isEmpty ? userName.value : displayName.value;
  String get accountLabelWithHandle {
    final username = userName.value.trim();
    if (username.isEmpty) {
      return '';
    }
    final preferred = displayName.value.trim();
    if (preferred.isEmpty || preferred == username) {
      return username;
    }
    return '$preferred (@$username)';
  }

  WeakReference<FFI> parent;

  UserModel(this.parent) {
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }

  void refreshCurrentUser() async {
    if (bind.isDisableAccount()) return;
    networkError.value = '';
    final token = bind.mainGetLocalOption(key: 'access_token');
    final refreshGeneration = _identityGeneration;
    if (token == '') {
      if (bind.mainIsEnterpriseWindowsBuild()) {
        await reset(resetOther: true);
        return;
      }
      enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (refreshingUser) return;
    var skipOtherModels = false;
    try {
      refreshingUser = true;
      final http.Response response;
      try {
        response = await http.post(Uri.parse('$url/api/currentUser'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body));
      } catch (e) {
        networkError.value = e.toString();
        rethrow;
      }
      refreshingUser = false;
      final status = response.statusCode;
      if (status == 401) {
        skipOtherModels = true;
        await reset(resetOther: true);
        return;
      }
      if (status != 200) {
        throw RequestException(status, 'Failed to refresh current user');
      }
      final data = json.decode(decode_http_response(response));
      final error = data['error'];
      if (error != null) {
        throw error;
      }
      if (refreshGeneration != _identityGeneration) return;

      final user = UserPayload.fromJson(data);
      _parseAndUpdateUser(user);
      if (bind.mainIsEnterpriseWindowsBuild()) {
        enterpriseAuthState.value = EnterpriseAuthState.checking;
        final remainingSeconds =
            await EnterpriseIdentityBridge.remainingSeconds();
        if (remainingSeconds <= 0) {
          await _renewManagedIdentity(refreshGeneration);
        } else {
          managedIdentityActive.value = true;
          enterpriseAuthState.value = EnterpriseAuthState.authenticated;
          _scheduleStartupManagedRenewal(
              Duration(seconds: remainingSeconds));
          _startManagedActivePolling();
        }
      } else {
        enterpriseAuthState.value = enterpriseStateAfterRefresh(
          outcome: EnterpriseRefreshOutcome.success,
          managedIdentityActive: managedIdentityActive.value,
        );
      }
    } catch (e) {
      debugPrint('Failed to refreshCurrentUser: $e');
      enterpriseAuthState.value = enterpriseStateAfterRefresh(
        outcome: e is RequestException
            ? EnterpriseRefreshOutcome.badResponse
            : EnterpriseRefreshOutcome.networkError,
        managedIdentityActive: managedIdentityActive.value,
      );
      if (bind.mainIsEnterpriseWindowsBuild()) {
        _scheduleManagedRenewal(retry: true);
      }
    } finally {
      refreshingUser = false;
      if (!skipOtherModels) {
        await updateOtherModels();
      }
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = (userInfo['name'] ?? '').toString();
      displayName.value = (userInfo['display_name'] ?? '').toString();
      avatar.value = (userInfo['avatar'] ?? '').toString();
    }
  }

  Future<bool> reset({bool resetOther = false}) async {
    _identityGeneration++;
    _managedRenewalTimer?.cancel();
    _managedActivePollTimer?.cancel();
    // Clearing the service-side identity is idempotent and must complete before
    // credentials are removed, including after a 401 or a partial bootstrap.
    final result = await _identityOperations.run(() => clearEnterpriseSession(
          clearIdentity: EnterpriseIdentityBridge.clear,
          clearToken: () =>
              bind.mainSetLocalOption(key: 'access_token', value: ''),
          clearUser: () =>
              bind.mainSetLocalOption(key: 'user_info', value: ''),
          clearCaches: resetOther ? _clearEnterpriseCaches : () async {},
        ));
    if (!result.success) {
      enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
      networkError.value =
          'Failed to clear managed identity after retries: ${result.error}';
      return false;
    }
    _clearInMemorySession();
    return true;
  }

  Future<void> _clearEnterpriseCaches() async {
    await gFFI.abModel.reset();
    await gFFI.groupModel.reset();
  }

  void setManagedIdentityApplied(bool active) {
    managedIdentityActive.value = active;
    enterpriseAuthState.value = active
        ? EnterpriseAuthState.authenticated
        : EnterpriseAuthState.unauthenticated;
  }

  void initializeManagedIdentity(bool active) {
    managedIdentityActive.value = active;
    enterpriseAuthState.value = EnterpriseAuthState.checking;
    if (active) {
      _startManagedActivePolling();
    }
  }

  Future<bool> applyEnterpriseLoginResponse(LoginResponse response) async {
    final generation = ++_identityGeneration;
    _managedRenewalTimer?.cancel();
    final coordinator = EnterpriseIdentityCoordinator(
      bootstrap: EnterpriseIdentityBridge.bootstrap,
      clear: () async {
        final result = await clearEnterpriseSession(
          clearIdentity: EnterpriseIdentityBridge.clear,
          clearToken: () =>
              bind.mainSetLocalOption(key: 'access_token', value: ''),
          clearUser: () =>
              bind.mainSetLocalOption(key: 'user_info', value: ''),
          clearCaches: _clearEnterpriseCaches,
        );
        if (!result.success) {
          networkError.value =
              'Failed to clear managed identity after retries: ${result.error}';
        }
      },
    );
    final applied =
        await _identityOperations.run(() => coordinator.applyLogin(response));
    if (generation != _identityGeneration) return false;
    if (!applied) {
      setManagedIdentityApplied(false);
      return false;
    }
    await bind.mainSetLocalOption(
        key: 'access_token', value: response.access_token!);
    await bind.mainSetLocalOption(
        key: 'user_info', value: jsonEncode(response.user!));
    _parseAndUpdateUser(response.user!);
    setManagedIdentityApplied(true);
    _scheduleManagedRenewal();
    _startManagedActivePolling();
    return true;
  }

  void _scheduleManagedRenewal({bool retry = false}) {
    if (!bind.mainIsEnterpriseWindowsBuild()) return;
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token.isEmpty) return;
    _managedRenewalTimer?.cancel();
    final randomUnit = Random.secure().nextDouble();
    final delay = retry
        ? _renewalPolicy.retryDelay(randomUnit)
        : _renewalPolicy.normalDelay(randomUnit);
    final generation = _identityGeneration;
    _managedRenewalTimer =
        Timer(delay, () => _renewManagedIdentity(generation));
  }

  void _scheduleStartupManagedRenewal(Duration remaining) {
    if (!bind.mainIsEnterpriseWindowsBuild()) return;
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token.isEmpty) return;
    _managedRenewalTimer?.cancel();
    final delay =
        _renewalPolicy.startupDelay(remaining, Random.secure().nextDouble());
    final generation = _identityGeneration;
    _managedRenewalTimer =
        Timer(delay, () => _renewManagedIdentity(generation));
  }

  Future<void> _renewManagedIdentity(int generation) async {
    if (generation != _identityGeneration) return;
    final token = bind.mainGetLocalOption(key: 'access_token');
    final result = await _identityOperations.run(() async {
      if (generation != _identityGeneration) return null;
      return EnterpriseIdentityRenewal(
        renewCall: EnterpriseIdentityBridge.renew,
        isActive: EnterpriseIdentityBridge.isActive,
      ).renew(token);
    });
    if (result == null || generation != _identityGeneration) return;
    switch (result.result) {
      case EnterpriseRenewalResult.renewed:
        managedIdentityActive.value = true;
        enterpriseAuthState.value = EnterpriseAuthState.authenticated;
        networkError.value = '';
        _scheduleManagedRenewal();
        _startManagedActivePolling();
        break;
      case EnterpriseRenewalResult.offlineValid:
        managedIdentityActive.value = true;
        enterpriseAuthState.value = EnterpriseAuthState.offlineGrace;
        networkError.value = enterpriseRenewalFailureMessage(result);
        _scheduleManagedRenewal(retry: true);
        break;
      case EnterpriseRenewalResult.expired:
        _managedActivePollTimer?.cancel();
        _managedActivePollTimer = null;
        managedIdentityActive.value = false;
        enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
        networkError.value = enterpriseRenewalFailureMessage(result);
        _scheduleManagedRenewal(retry: true);
        break;
      case EnterpriseRenewalResult.revoked:
        if (await reset(resetOther: true)) {
          networkError.value = enterpriseRenewalFailureMessage(result);
        }
        break;
    }
  }

  void _startManagedActivePolling() {
    if (!bind.mainIsEnterpriseWindowsBuild()) return;
    _managedActivePollTimer?.cancel();
    final generation = _identityGeneration;
    _managedActivePollTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (generation != _identityGeneration) return;
      var active = false;
      try {
        active = await EnterpriseIdentityBridge.isActive();
      } catch (_) {
        return;
      }
      if (enterpriseActivePollAction(active) ==
              EnterpriseActivePollAction.stopAndRetry &&
          generation == _identityGeneration) {
        _managedActivePollTimer?.cancel();
        _managedActivePollTimer = null;
        managedIdentityActive.value = false;
        enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
        networkError.value =
            'Managed identity session expired; renewal is required';
        _scheduleManagedRenewal(retry: true);
      }
    });
  }

  void _clearInMemorySession() {
    userName.value = '';
    displayName.value = '';
    avatar.value = '';
    isAdmin.value = false;
    managedIdentityActive.value = false;
    enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
  }

  _parseAndUpdateUser(UserPayload user) {
    userName.value = user.name;
    displayName.value = user.displayName;
    avatar.value = user.avatar;
    isAdmin.value = user.isAdmin;
    bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
    if (isWeb) {
      // ugly here, tmp solution
      bind.mainSetLocalOption(key: 'verifier', value: user.verifier ?? '');
    }
  }

  // update ab and group status
  static Future<bool> updateOtherModels() async {
    final results = await Future.wait<dynamic>([
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
      gFFI.groupModel.pull()
    ]);
    return results[1] == true;
  }

  Future<void> logOut({String? apiServer}) async {
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    _identityGeneration++;
    _managedRenewalTimer?.cancel();
    _managedActivePollTimer?.cancel();
    try {
      final url = apiServer ?? await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      final body = jsonEncode({
        'id': await bind.mainGetMyId(),
        'uuid': await bind.mainGetUuid(),
      });
      final result = await _identityOperations.run(
        () => completeEnterpriseLogout(
          clearIdentity: EnterpriseIdentityBridge.clear,
          clearCaches: _clearEnterpriseCaches,
          notifyRemoteLogout: () async {
            await http
                .post(Uri.parse('$url/api/logout'),
                    body: body, headers: authHeaders)
                .timeout(Duration(seconds: 2));
          },
          clearToken: () =>
              bind.mainSetLocalOption(key: 'access_token', value: ''),
          clearUser: () =>
              bind.mainSetLocalOption(key: 'user_info', value: ''),
        ),
      );
      if (!result.success) {
        enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
        networkError.value =
            'Failed to clear managed identity after retries: ${result.error}';
        return;
      }
      _clearInMemorySession();
    } finally {
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest) async {
    final url = await bind.mainGetApiServer();
    final resp = await http.post(Uri.parse('$url/api/login'),
        body: jsonEncode(loginRequest.toJson()));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(decode_http_response(resp));
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    return getLoginResponseFromAuthBody(body);
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body,
      {bool deferManagedIdentity = false}) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      debugPrint("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    final isLogInDone = loginResponse.type == HttpType.kAuthResTypeToken &&
        loginResponse.access_token != null;
    if (isLogInDone && loginResponse.user != null && !deferManagedIdentity) {
      _parseAndUpdateUser(loginResponse.user!);
      // Task 7 will call setManagedIdentityApplied(true) only after the Rust
      // atomic identity apply succeeds. A token alone must never open the UI.
      enterpriseAuthState.value = EnterpriseAuthState.unauthenticated;
    }

    return loginResponse;
  }

  static Future<List<dynamic>> queryOidcLoginOptions() async {
    try {
      final url = await bind.mainGetApiServer();
      if (url.trim().isEmpty) return [];
      final resp = await http.get(Uri.parse('$url/api/login-options'));
      final List<String> ops = [];
      for (final item in jsonDecode(resp.body)) {
        ops.add(item as String);
      }
      for (final item in ops) {
        if (item.startsWith('common-oidc/')) {
          return jsonDecode(item.substring('common-oidc/'.length));
        }
      }
      return ops
          .where((item) => item.startsWith('oidc/'))
          .map((item) => {'name': item.substring('oidc/'.length)})
          .toList();
    } catch (e) {
      debugPrint(
          "queryOidcLoginOptions: jsonDecode resp body failed: ${e.toString()}");
      return [];
    }
  }
}
