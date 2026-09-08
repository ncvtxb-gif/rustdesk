import 'package:flutter_hbb/models/enterprise_auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forged cached login fails closed after a network error', () {
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.networkError,
        managedIdentityActive: false,
      ),
      EnterpriseAuthState.unauthenticated,
    );
  });

  test('network error grants offline grace only to an applied identity', () {
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.networkError,
        managedIdentityActive: true,
      ),
      EnterpriseAuthState.offlineGrace,
    );
  });

  test('401 clears authentication while 400 preserves an applied identity', () {
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.unauthorized,
        managedIdentityActive: true,
      ),
      EnterpriseAuthState.unauthenticated,
    );
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.badResponse,
        managedIdentityActive: true,
      ),
      EnterpriseAuthState.offlineGrace,
    );
  });

  test('500 or parse failures cannot authenticate a cached-only identity', () {
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.badResponse,
        managedIdentityActive: false,
      ),
      EnterpriseAuthState.unauthenticated,
    );
  });

  test('successful user refresh requires an applied identity', () {
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.success,
        managedIdentityActive: false,
      ),
      EnterpriseAuthState.unauthenticated,
    );
    expect(
      enterpriseStateAfterRefresh(
        outcome: EnterpriseRefreshOutcome.success,
        managedIdentityActive: true,
      ),
      EnterpriseAuthState.authenticated,
    );
  });
}
