import 'package:flutter_hbb/desktop/widgets/enterprise_feishu_login_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise main window is locked to 1280 by 720', () async {
    final calls = <String>[];

    await configureEnterpriseMainWindow(
      unmaximize: () async => calls.add('unmaximize'),
      setSize: (size) async => calls.add('size:${size.width}x${size.height}'),
      setMinimumSize: (size) async =>
          calls.add('min:${size.width}x${size.height}'),
      setMaximumSize: (size) async =>
          calls.add('max:${size.width}x${size.height}'),
      setResizable: (value) async => calls.add('resizable:$value'),
      setMaximizable: (value) async => calls.add('maximizable:$value'),
    );

    expect(calls, [
      'unmaximize',
      'size:1280.0x720.0',
      'min:1280.0x720.0',
      'max:1280.0x720.0',
      'resizable:false',
      'maximizable:false',
    ]);
  });
}
