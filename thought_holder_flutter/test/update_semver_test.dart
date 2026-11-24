import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/services/app_update_service.dart';

void main() {
  group('Semver comparison', () {
    test('numeric segments compare numerically, not lexically', () {
      expect(AppUpdateService.compareSemVer('1.10.0', '1.9.0'), greaterThan(0));
      expect(AppUpdateService.compareSemVer('1.9.0', '1.10.0'), lessThan(0));
      expect(AppUpdateService.compareSemVer('1.4.0', '1.4.0'), 0);
      expect(AppUpdateService.compareSemVer('v1.4.0', '1.4.0'), 0);
      expect(AppUpdateService.compareSemVer('2.0.0', '1.99.99'), greaterThan(0));
      expect(AppUpdateService.compareSemVer('1.4.0-beta.1', '1.4.0'), 0);
      expect(AppUpdateService.compareSemVer('1.4', '1.4.0'), 0);
      expect(AppUpdateService.compareSemVer('1.4.1', '1.4'), greaterThan(0));
    });
  });

  group('UpdateCheckException', () {
    test('maps failure kinds to actionable messages', () {
      const timeout = UpdateCheckException(
        kind: UpdateCheckFailureKind.timeout,
        message: 'timeout',
        manifestUrl: 'https://example.com/version.json',
      );
      const dns = UpdateCheckException(
        kind: UpdateCheckFailureKind.dns,
        message: 'dns',
        manifestUrl: 'https://example.com/version.json',
      );
      const http = UpdateCheckException(
        kind: UpdateCheckFailureKind.http,
        message: 'http',
        manifestUrl: 'https://example.com/version.json',
        statusCode: 404,
      );
      const badJson = UpdateCheckException(
        kind: UpdateCheckFailureKind.badJson,
        message: 'bad',
        manifestUrl: 'https://example.com/version.json',
      );

      expect(timeout.userMessage.toLowerCase(), contains('timed out'));
      expect(dns.userMessage.toLowerCase(), contains('resolve'));
      expect(http.userMessage, contains('404'));
      expect(badJson.userMessage.toLowerCase(), contains('json'));
    });
  });
}
