import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary enterprise user cannot open the address book web console', () {
    expect(
      shouldShowAddressBookWebConsole(
        enterpriseWindows: true,
        isAdmin: false,
        legacyMode: false,
        canWrite: true,
      ),
      isFalse,
    );
  });

  test('enterprise administrator can open the address book web console', () {
    expect(
      shouldShowAddressBookWebConsole(
        enterpriseWindows: true,
        isAdmin: true,
        legacyMode: false,
        canWrite: true,
      ),
      isTrue,
    );
  });

  test(
      'non-enterprise address book keeps the existing web console behavior', () {
    expect(
      shouldShowAddressBookWebConsole(
        enterpriseWindows: false,
        isAdmin: false,
        legacyMode: false,
        canWrite: true,
      ),
      isTrue,
    );
  });

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
