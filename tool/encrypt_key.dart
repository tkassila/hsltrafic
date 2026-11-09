// ignore_for_file: avoid_print
import 'dart:convert';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Käyttö: dart run tool/encrypt_key.dart <OMA_API_AVAIN>');
    print('Esimerkki: dart run tool/encrypt_key.dart a1b2c3d4e5f6789012345678abcdef01');
    return;
  }

  final plainText = args[0].trim();
  const xorMask = 'HsL_TrAfFiC_2026_SeCrEt_SaLt';

  final bytes = utf8.encode(plainText);
  final maskBytes = utf8.encode(xorMask);

  final encrypted = <int>[];
  for (int i = 0; i < bytes.length; i++) {
    encrypted.add(bytes[i] ^ maskBytes[i % maskBytes.length]);
  }

  print('\n=== AVAIN SALATTU ONNISTUNEESTI ===');
  print('Kopioi alla oleva rivi tiedostoon: lib/config/app_config.dart\n');
  print('  static const List<int> encryptedKeyBytes = $encrypted;\n');
  print('Näin selkokielinen avain ei koskaan päädy binääriin merkkijonona.');
}
