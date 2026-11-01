import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' as c;

void main() {
  test('X25519 key exchange generates identical shared secret on both sides', () async {
    final x25519 = c.X25519();
    
    // Alice generates keypair
    final aliceKeyPair = await x25519.newKeyPair();
    final alicePubKey = await aliceKeyPair.extractPublicKey();
    
    // Bob generates keypair
    final bobKeyPair = await x25519.newKeyPair();
    final bobPubKey = await bobKeyPair.extractPublicKey();
    
    // Alice derives shared secret with Bob's public key
    final aliceSecret = await x25519.sharedSecretKey(
      keyPair: aliceKeyPair,
      remotePublicKey: bobPubKey,
    );
    final aliceSecretBytes = await aliceSecret.extractBytes();
    
    // Bob derives shared secret with Alice's public key
    final bobSecret = await x25519.sharedSecretKey(
      keyPair: bobKeyPair,
      remotePublicKey: alicePubKey,
    );
    final bobSecretBytes = await bobSecret.extractBytes();
    
    expect(aliceSecretBytes, equals(bobSecretBytes));
    expect(aliceSecretBytes.length, 32);
  });
}
