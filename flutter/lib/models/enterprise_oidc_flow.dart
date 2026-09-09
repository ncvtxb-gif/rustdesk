import 'dart:convert';

typedef EnterpriseOidcStart = Future<void> Function({
  required String op,
  required bool rememberMe,
});

class EnterpriseOidcException implements Exception {
  const EnterpriseOidcException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EnterpriseOidcFlow {
  const EnterpriseOidcFlow({
    required this.queryOptions,
    required this.startAuth,
    required this.readAuthResult,
    required this.launchExternalUrl,
    required this.waitForNextPoll,
    required this.onAuthBody,
    this.maxPolls = 180,
  });

  final Future<List<dynamic>> Function() queryOptions;
  final EnterpriseOidcStart startAuth;
  final Future<String> Function() readAuthResult;
  final Future<bool> Function(Uri url) launchExternalUrl;
  final Future<void> Function() waitForNextPoll;
  final Future<void> Function(Map<String, dynamic> authBody) onAuthBody;
  final int maxPolls;

  Future<void> start({required String configuredProvider}) async {
    if (configuredProvider.toLowerCase() == 'webauth') {
      throw const EnterpriseOidcException('Feishu login provider is missing');
    }
    final options = await queryOptions();
    final matches = options.where((option) {
      return option is Map && option['name'] == configuredProvider;
    }).toList();
    if (matches.length != 1) {
      throw const EnterpriseOidcException('Feishu login provider is missing');
    }

    await startAuth(op: configuredProvider, rememberMe: true);
    var launchedUrl = '';
    for (var poll = 0; poll < maxPolls; poll++) {
      final raw = await readAuthResult();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const EnterpriseOidcException('Invalid OIDC response');
        }
        final failed = decoded['failed_msg'];
        if (failed is String && failed.isNotEmpty) {
          throw EnterpriseOidcException(failed);
        }
        final url = decoded['url'];
        final urlLaunched = decoded['url_launched'] == true;
        if (url is String &&
            url.isNotEmpty &&
            url != launchedUrl &&
            !urlLaunched) {
          if (!await launchExternalUrl(Uri.parse(url))) {
            throw const EnterpriseOidcException(
                'Failed to open system browser');
          }
          launchedUrl = url;
        }
        final authBody = decoded['auth_body'];
        if (authBody is Map) {
          await onAuthBody(Map<String, dynamic>.from(authBody));
          return;
        }
      }
      await waitForNextPoll();
    }
    throw const EnterpriseOidcException('Feishu login timed out');
  }
}
