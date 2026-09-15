import 'package:flutter_hbb/models/enterprise_address_book_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary enterprise user cannot see the address book tab', () {
    expect(
      shouldShowAddressBookTab(
        enterpriseWindows: true,
        isAdmin: false,
      ),
      isFalse,
    );
  });

  test('enterprise administrator can see the address book tab', () {
    expect(
      shouldShowAddressBookTab(
        enterpriseWindows: true,
        isAdmin: true,
      ),
      isTrue,
    );
  });

  test('non-enterprise clients keep the existing address book tab', () {
    expect(
      shouldShowAddressBookTab(
        enterpriseWindows: false,
        isAdmin: false,
      ),
      isTrue,
    );
  });
}
