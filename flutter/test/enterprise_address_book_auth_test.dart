import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enterprise administrator cache retains API-provided peer hash', () {
    expect(
      shouldPersistAddressBookHash(
        enterpriseWindows: true,
        isAdmin: true,
        isPersonal: false,
      ),
      isTrue,
    );
  });

  test('ordinary enterprise user cannot retain unattended auth material', () {
    expect(
      shouldPersistAddressBookHash(
        enterpriseWindows: true,
        isAdmin: false,
        isPersonal: false,
      ),
      isFalse,
    );
  });

  test('non-enterprise behavior retains hashes only for personal books', () {
    expect(
      shouldPersistAddressBookHash(
        enterpriseWindows: false,
        isAdmin: true,
        isPersonal: false,
      ),
      isFalse,
    );
    expect(
      shouldPersistAddressBookHash(
        enterpriseWindows: false,
        isAdmin: false,
        isPersonal: true,
      ),
      isTrue,
    );
  });
}
