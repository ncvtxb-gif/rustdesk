import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/group_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group peer payload preserves API-provided authentication hash', () {
    final payload = PeerPayload.fromJson({
      'id': '123456789',
      'hash': 'compatible-auth-hash',
      'info': <String, dynamic>{},
    });

    final peer = PeerPayload.toPeer(payload);

    expect(payload.hash, 'compatible-auth-hash');
    expect(peer.hash, 'compatible-auth-hash');
  });

  test('ordinary users discard a server-provided authentication hash', () {
    expect(
      groupPeerHashForRole(
        'compatible-auth-hash',
        enterpriseWindows: true,
        isAdmin: false,
      ),
      isEmpty,
    );
    expect(
      groupPeerHashForRole(
        'compatible-auth-hash',
        enterpriseWindows: true,
        isAdmin: true,
      ),
      'compatible-auth-hash',
    );
    expect(
      groupPeerHashForRole(
        'compatible-auth-hash',
        enterpriseWindows: false,
        isAdmin: false,
      ),
      'compatible-auth-hash',
      reason: 'non-enterprise clients must retain their existing behavior',
    );
  });

  test('group cache retains auth hash only for enterprise administrators', () {
    expect(
      shouldPersistGroupPeerHash(
          enterpriseWindows: true, isAdmin: true),
      isTrue,
    );
    expect(
      shouldPersistGroupPeerHash(
          enterpriseWindows: true, isAdmin: false),
      isFalse,
    );
    expect(
      shouldPersistGroupPeerHash(
          enterpriseWindows: false, isAdmin: true),
      isFalse,
    );

    final peer = Peer.fromJson({
      'id': '123456789',
      'hash': 'compatible-auth-hash',
    });
    expect(peer.toGroupCacheJson(includingHash: true)['hash'],
        'compatible-auth-hash');
    expect(peer.toGroupCacheJson(includingHash: false).containsKey('hash'),
        isFalse);
  });
}
