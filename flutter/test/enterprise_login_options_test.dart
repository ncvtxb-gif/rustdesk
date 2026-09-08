import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise login options contain only the configured Feishu provider', () {
    final options = [
      {'name': 'webauth', 'icon': 'web'},
      {'name': 'feishu', 'icon': 'company'},
      {'name': 'another-oidc', 'icon': 'other'},
    ];

    expect(
      enterpriseFeishuLoginOptions(options, configuredProvider: 'feishu'),
      [
        {'name': 'feishu', 'icon': 'company'},
      ],
    );
  });
}
