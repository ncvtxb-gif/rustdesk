enum EnterpriseAuthState {
  checking,
  unauthenticated,
  authenticated,
  offlineGrace,
}

enum EnterpriseRefreshOutcome {
  success,
  unauthorized,
  networkError,
  badResponse,
}

EnterpriseAuthState enterpriseStateAfterRefresh({
  required EnterpriseRefreshOutcome outcome,
  required bool managedIdentityActive,
}) {
  if (outcome == EnterpriseRefreshOutcome.unauthorized) {
    return EnterpriseAuthState.unauthenticated;
  }
  if (!managedIdentityActive) {
    return EnterpriseAuthState.unauthenticated;
  }
  return outcome == EnterpriseRefreshOutcome.success
      ? EnterpriseAuthState.authenticated
      : EnterpriseAuthState.offlineGrace;
}
