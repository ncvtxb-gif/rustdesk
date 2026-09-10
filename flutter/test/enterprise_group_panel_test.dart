import 'package:flutter_hbb/desktop/widgets/enterprise_desktop_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise accessible devices panel matches address book width', () {
    expect(accessibleDevicesPanelWidth(enterpriseWindows: true), 200);
    expect(accessibleDevicesPanelWidth(enterpriseWindows: false), 150);
  });

  test('enterprise users display Feishu names without account fallback', () {
    expect(enterpriseUserDisplayLabel('钟俊歌'), '钟俊歌');
    expect(enterpriseUserDisplayLabel('  '), '未知用户');
  });
}
