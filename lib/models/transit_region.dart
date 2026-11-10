import 'package:latlong2/latlong.dart';
import '../core/geo.dart';

/// Joukkoliikennealue ja sitä vastaava Digitransit GraphQL -reitityspalvelin.
enum TransitRegion {
  auto(
    id: 'auto',
    name: 'Automaattinen (GPS)',
    description: 'Tunnistaa paikkakunnan automaattisesti laitteen sijainnin mukaan',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/hsl/gtfs/v1',
    center: null,
    feedId: null,
  ),
  hsl(
    id: 'hsl',
    name: 'Pääkaupunkiseutu (HSL)',
    description: 'Helsinki, Espoo, Vantaa, Kauniainen, lähialueet',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/hsl/gtfs/v1',
    center: LatLng(60.1699, 24.9384),
    feedId: 'HSL',
  ),
  waltti(
    id: 'waltti',
    name: 'Waltti-kaupungit',
    description: 'Tampere, Turku, Oulu, Jyväskylä, Kuopio, Lahti ym.',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/waltti/gtfs/v1',
    center: LatLng(61.4978, 23.7610),
    feedId: null,
  ),
  tampere(
    id: 'tampere',
    name: 'Tampere (Nysse)',
    description: 'Tampereen seudun joukkoliikenne',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/waltti/gtfs/v1',
    center: LatLng(61.4978, 23.7610),
    feedId: 'tampere',
  ),
  turku(
    id: 'turku',
    name: 'Turku (Föli)',
    description: 'Turun seudun joukkoliikenne',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/waltti/gtfs/v1',
    center: LatLng(60.4518, 22.2666),
    feedId: 'FOLI',
  ),
  oulu(
    id: 'oulu',
    name: 'Oulu',
    description: 'Oulun seudun joukkoliikenne',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/waltti/gtfs/v1',
    center: LatLng(65.0121, 25.4651),
    feedId: 'OULU',
  ),
  jyvaskyla(
    id: 'jyvaskyla',
    name: 'Jyväskylä (Linkki)',
    description: 'Jyväskylän seudun joukkoliikenne',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/waltti/gtfs/v1',
    center: LatLng(62.2426, 25.7473),
    feedId: 'LINKKI',
  ),
  finland(
    id: 'finland',
    name: 'Koko Suomi (VR & Kaukoliikenne)',
    description: 'Koko valtakunnan kaukojunat, bussit ja seutuliikenne',
    graphqlUrl: 'https://api.digitransit.fi/routing/v2/finland/gtfs/v1',
    center: null,
    feedId: null,
  );

  final String id;
  final String name;
  final String description;
  final String graphqlUrl;
  final LatLng? center;
  final String? feedId;

  const TransitRegion({
    required this.id,
    required this.name,
    required this.description,
    required this.graphqlUrl,
    required this.center,
    required this.feedId,
  });

  static TransitRegion byId(String? id) =>
      TransitRegion.values.firstWhere((r) => r.id == id, orElse: () => TransitRegion.auto);

  /// Tarkistaa onko piste pääkaupunkiseudun (HSL) aluerajojen sisällä.
  static bool isInHsl(LatLng p) =>
      p.latitude >= 59.9 && p.latitude <= 60.6 && p.longitude >= 24.2 && p.longitude <= 25.6;

  /// Tunnistaa kuuluuko koordinaatti tiettyyn Waltti-kaupunkiseutuun.
  static String? walttiRegionFor(LatLng p) {
    final lat = p.latitude;
    final lon = p.longitude;
    if (lat >= 61.2 && lat <= 61.8 && lon >= 23.2 && lon <= 24.5) return 'tampere';
    if (lat >= 60.2 && lat <= 60.8 && lon >= 21.8 && lon <= 22.8) return 'turku';
    if (lat >= 64.7 && lat <= 65.4 && lon >= 25.0 && lon <= 26.2) return 'oulu';
    if (lat >= 62.0 && lat <= 62.6 && lon >= 25.3 && lon <= 26.2) return 'jyvaskyla';
    if (lat >= 60.8 && lat <= 61.2 && lon >= 25.4 && lon <= 26.0) return 'lahti';
    if (lat >= 62.7 && lat <= 63.2 && lon >= 27.4 && lon <= 28.0) return 'kuopio';
    return null;
  }

  /// Päättelee tehollisen GraphQL-endpointin yleisille kyselyille (pysäkit, linjat)
  /// annetun sijainnin perusteella.
  String resolveGraphqlUrl(LatLng? pos) {
    if (this != TransitRegion.auto || pos == null) {
      return graphqlUrl;
    }
    if (isInHsl(pos)) {
      return TransitRegion.hsl.graphqlUrl;
    }
    if (walttiRegionFor(pos) != null) {
      return TransitRegion.waltti.graphqlUrl;
    }
    return TransitRegion.finland.graphqlUrl;
  }

  /// Päättelee optimaalisen GraphQL-reitityspalvelimen kahden pisteen väliselle reitille.
  /// Jos matka on kaupunkien välinen (esim. Helsinki-Tampere, Tampere-Turku, etäisyys > 38 km)
  /// tai pisteet ovat eri liikennejärjestelmissä, reititykseen käytetään valtakunnallista
  /// Koko Suomi -palvelinta (VR-kaukojunat, kaukobussit).
  String resolvePlanGraphqlUrl({required LatLng from, required LatLng to}) {
    if (this == TransitRegion.finland) {
      return TransitRegion.finland.graphqlUrl;
    }

    final dist = distanceMeters(from, to);
    if (dist > 38000) {
      return TransitRegion.finland.graphqlUrl;
    }

    final fromHsl = isInHsl(from);
    final toHsl = isInHsl(to);
    if (fromHsl && toHsl && (this == TransitRegion.hsl || this == TransitRegion.auto)) {
      return TransitRegion.hsl.graphqlUrl;
    }
    if (fromHsl != toHsl) {
      return TransitRegion.finland.graphqlUrl;
    }

    final fromWaltti = walttiRegionFor(from);
    final toWaltti = walttiRegionFor(to);
    if (fromWaltti != null && fromWaltti == toWaltti) {
      return TransitRegion.waltti.graphqlUrl;
    }

    if (this == TransitRegion.waltti && fromWaltti != null && toWaltti != null && fromWaltti == toWaltti) {
      return TransitRegion.waltti.graphqlUrl;
    }

    return TransitRegion.finland.graphqlUrl;
  }

  /// Palauttaa ihmiselle selkeän näyttönimen (huomioi myös automaattisen tunnistuksen)
  String effectiveDisplayName(LatLng? pos) {
    if (this != TransitRegion.auto || pos == null) {
      return name;
    }
    if (isInHsl(pos)) {
      return 'Automaattinen: HSL';
    }
    final walttiCity = walttiRegionFor(pos);
    if (walttiCity == 'tampere') return 'Automaattinen: Tampere';
    if (walttiCity == 'turku') return 'Automaattinen: Turku';
    if (walttiCity == 'oulu') return 'Automaattinen: Oulu';
    if (walttiCity == 'jyvaskyla') return 'Automaattinen: Jyväskylä';
    if (walttiCity == 'lahti') return 'Automaattinen: Lahti';
    if (walttiCity == 'kuopio') return 'Automaattinen: Kuopio';
    return 'Automaattinen: Koko Suomi';
  }
}
