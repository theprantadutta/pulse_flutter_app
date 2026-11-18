import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:pulse/services/net/router/drivers/tplink_driver.dart';

BigInt _big(Uint8List b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

Uint8List _bytes(BigInt v, int len) {
  final out = Uint8List(len);
  for (var i = len - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _keys(int bits) {
  final rnd = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)))));
  final gen = RSAKeyGenerator()
    ..init(ParametersWithRandom(RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64), rnd));
  final p = gen.generateKeyPair();
  return AsymmetricKeyPair(p.publicKey, p.privateKey);
}

String _rsaDecrypt(String hex, RSAPrivateKey key) {
  final k = (key.modulus!.bitLength + 7) ~/ 8;
  final c = PKCS1Encoding(RSAEngine())..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
  return utf8.decode(c.process(_bytes(BigInt.parse(hex, radix: 16), k)));
}

void main() {
  test('RSA PKCS#1 v1.5 encryption decrypts with the private key (1024 and 2048 bit)', () {
    for (final bits in [1024, 2048]) {
      final kp = _keys(bits);
      final hex = TplinkRsa.pkcs1Hex('router-secret', kp.publicKey.modulus!, kp.publicKey.exponent!);
      expect(hex.length, bits ~/ 4);
      expect(_rsaDecrypt(hex, kp.privateKey), 'router-secret');
    }
  });

  test('AES session round-trips and matches a reference CBC/PKCS7 cipher', () {
    final kp = _keys(1024);
    final s = TplinkSession(n: kp.publicKey.modulus!, e: kp.publicKey.exponent!, seq: 100, hash: 'h');
    const plain = '{"operation":"read","name":"Café ✓"}';
    final enc = s.encrypt(plain);
    expect(s.decrypt(enc), plain);

    final ref = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(Uint8List.fromList(utf8.encode(s.key))), Uint8List.fromList(utf8.encode(s.iv))),
          null,
        ),
      );
    expect(enc, base64.encode(ref.process(Uint8List.fromList(utf8.encode(plain)))));
    expect(s.key.length, 16);
    expect(s.iv.length, 16);
  });

  test('envelope signs k/i/h/s in 53-character RSA blocks with seq + data length', () {
    final kp = _keys(1024);
    final s = TplinkSession(n: kp.publicKey.modulus!, e: kp.publicKey.exponent!, seq: 1000, hash: 'abc');
    final env = Uri.splitQueryString(s.envelope('operation=login', login: true));
    final data = env['data']!;
    final sign = env['sign']!;
    final blocks = [for (var i = 0; i < sign.length; i += 256) _rsaDecrypt(sign.substring(i, i + 256), kp.privateKey)];
    expect(blocks.join(), 'k=${s.key}&i=${s.iv}&h=abc&s=${1000 + data.length}');
    expect(blocks.every((b) => b.length <= 53), isTrue);
    expect(s.decrypt(data), 'operation=login');
    expect(_big(Uint8List(0)), BigInt.zero);
  });

  test('SG: digits key/IV, OAEP login sign, HMAC request sign with per-request hash', () {
    final kp = _keys(2048);
    final s = TplinkSession(n: kp.publicKey.modulus!, e: kp.publicKey.exponent!, seq: 500, hash: 'h0', sg: true);
    expect(RegExp(r'^\d{16}$').hasMatch(s.key), isTrue);
    expect(RegExp(r'^\d{16}$').hasMatch(s.iv), isTrue);

    // Login: OAEP blocks of the key size decrypt to k/i/h/s.
    final login = Uri.splitQueryString(s.envelope('operation=login', login: true));
    final oaep = OAEPEncoding(RSAEngine())..init(false, PrivateKeyParameter<RSAPrivateKey>(kp.privateKey));
    final sign = login['sign']!;
    final parts = [
      for (var i = 0; i < sign.length; i += 512)
        utf8.decode(oaep.process(_bytes(BigInt.parse(sign.substring(i, i + 512), radix: 16), 256))),
    ];
    expect(parts.join(), 'k=${s.key}&i=${s.iv}&h=h0&s=${500 + login['data']!.length}');

    // Request: hash = SHA-256(encrypted data), sign = HMAC-SHA256 chunks keyed by k/i.
    final req = Uri.splitQueryString(s.envelope('operation=read'));
    final data = req['data']!;
    final h = sha256.convert(utf8.encode(data)).toString();
    expect(s.hash, h);
    final str = 'h=$h&s=${500 + data.length}';
    final mac = Hmac(sha256, utf8.encode('k=${s.key}&i=${s.iv}'));
    final want = StringBuffer();
    for (var p = 0; p < str.length; p += 53) {
      want.write(mac.convert(utf8.encode(str.substring(p, p + 53 > str.length ? str.length : p + 53))));
    }
    expect(req['sign'], want.toString());
    expect(s.decrypt(data), 'operation=read');
  });
}
