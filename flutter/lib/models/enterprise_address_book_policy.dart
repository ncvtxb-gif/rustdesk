bool shouldShowAddressBookTab({
  required bool enterpriseWindows,
  required bool isAdmin,
}) =>
    !enterpriseWindows || isAdmin;
