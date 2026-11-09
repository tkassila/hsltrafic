import 'dart:convert';

/// Sovelluksen määritykset ja API-avainten hallinta.
///
/// TÄRKEÄÄ: API-avaimen suojaaminen käännetyssä sovelluksessa:
/// 1. Selkokielinen merkkijono (string literal) binäärissä voidaan lukea
///    'strings'-komennolla tai purkamalla APK/ELF-tiedosto.
/// 2. Tässä luokassa on tuki kolmelle eri suojaustasolle:
///    - Taso A (Suositus / Käännösaikainen): --dart-define=DIGITRANSIT_KEY=oma_avain
///    - Taso B (XOR-salaus koodissa): Avain tallennetaan tavutaulukkona [encryptedKeyBytes],
///      jolloin selkokielistä avainmerkkijonoa EI OLE sovelluksen binäärissä.
///    - Taso C (Suora staattinen muuttuja): Voit kirjoittaa avaimen suoraan [rawApiKey]-kenttään.
class AppConfig {
  // ===========================================================================
  // 1. TAPA: KIRJOITA AVAIN TÄHÄN (Staattinen muuttuja)
  // Voit liittää avaimen suoraan tähän lainausmerkkeihin:
  // Esim: static const String rawApiKey = 'OMA_DIGITRANSIT_AVAIN_TAHAN';
  // ===========================================================================
  static const String rawApiKey = '';

  // ===========================================================================
  // 2. TAPA: SALATTU TAVUTAULUKKO (Estää selkokielisen näkymisen binäärissä)
  // Jos haluat salata avaimen niin, ettei 'strings'-komento löydä sitä binääristä,
  // voit luoda salatun tavutaulukon ja sijoittaa sen tähän.
  // Voit generoida salatut tavut konsolissa komennolla:
  //   dart run tool/encrypt_key.dart OMA_AVAIN
  // ===========================================================================
  static const List<int> encryptedKeyBytes = [
    120,
    70,
    122,
    105,
    102,
    64,
    116,
    82,
    113,
    11,
    34,
    60,
    6,
    86,
    4,
    6,
    102,
    99,
    84,
    38,
    17,
    38,
    66,
    61,
    106,
    86,
    45,
    67,
    126,
    69,
    47,
    110,
  ];
  // Salauksen XOR-avain / maski
  static const String _xorMask = 'HsL_TrAfFiC_2026_SeCrEt_SaLt';

  // 3. TAPA: Käännösaikainen ympäristömuuttuja (--dart-define)
  static const String _compileTimeKey = String.fromEnvironment(
    'DIGITRANSIT_KEY',
  );

  /// Palauttaa aktiivisen API-avaimen suojatusta lähteestä.
  static String get digitransitApiKey {
    // 1. Käännösaikainen lippu (--dart-define=DIGITRANSIT_KEY=...)
    if (_compileTimeKey.trim().isNotEmpty) {
      return _compileTimeKey.trim();
    }

    // 2. Salattu tavutaulukko (puretaan muistissa XOR-maskilla lennossa)
    if (encryptedKeyBytes.isNotEmpty) {
      final decrypted = _decryptBytes(encryptedKeyBytes, _xorMask);
      if (decrypted.trim().isNotEmpty) {
        return decrypted.trim();
      }
    }

    // 3. Suora koodiin kirjoitettu staattinen muuttuja
    return rawApiKey.trim();
  }

  /// Onko API-avain määritetty jossakin lähteessä
  static bool get hasApiKey => digitransitApiKey.isNotEmpty;

  /// Purkaa tavutaulukon selkokieliseksi merkkijonoksi XOR-menetelmällä
  static String _decryptBytes(List<int> bytes, String key) {
    final keyCodes = utf8.encode(key);
    final decrypted = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      decrypted.add(bytes[i] ^ keyCodes[i % keyCodes.length]);
    }
    return utf8.decode(decrypted);
  }

  /// Apufunktio avaimen salaamiseen (käytetään avaimen kryptaamiseen ennen koodiin vientiä)
  static List<int> encryptString(String plainText) {
    final bytes = utf8.encode(plainText);
    final keyCodes = utf8.encode(_xorMask);
    final encrypted = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      encrypted.add(bytes[i] ^ keyCodes[i % keyCodes.length]);
    }
    return encrypted;
  }
}
