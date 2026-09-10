import 'package:flutter_hbb/desktop/widgets/enterprise_feishu_login_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise UI removes user-managed surfaces', () {
    const policy = EnterpriseUiPolicy.enabled;

    expect(policy.showFavorites, isFalse);
    expect(policy.showPluginSettings, isFalse);
    expect(policy.showAccountSettings, isFalse);
    expect(policy.showPrinterSettings, isFalse);
    expect(policy.showAboutSettings, isFalse);
    expect(policy.showAdvancedSecuritySettings, isFalse);
  });

  test('original UI retains shared surfaces', () {
    const policy = EnterpriseUiPolicy.disabled;

    expect(policy.showFavorites, isTrue);
    expect(policy.showPluginSettings, isTrue);
    expect(policy.showAccountSettings, isTrue);
    expect(policy.showPrinterSettings, isTrue);
    expect(policy.showAboutSettings, isTrue);
    expect(policy.showAdvancedSecuritySettings, isTrue);
  });
}
