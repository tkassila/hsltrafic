/// Kulkumuoto – yhteinen GTFS-, GraphQL- ja HFP-tulkinnalle (puhdas Dart, ei UI-riippuvuuksia).
enum TransitMode {
  bus,
  tram,
  metro,
  rail,
  ferry,
  walk,
  bike,
  other;

  String get label {
    switch (this) {
      case TransitMode.bus:
        return 'Bussi';
      case TransitMode.tram:
        return 'Raitiovaunu';
      case TransitMode.metro:
        return 'Metro';
      case TransitMode.rail:
        return 'Juna';
      case TransitMode.ferry:
        return 'Lautta';
      case TransitMode.walk:
        return 'Kävely';
      case TransitMode.bike:
        return 'Pyörä';
      case TransitMode.other:
        return 'Muu';
    }
  }

  /// Onko kulkumuoto liikenneväline (ei kävely/pyörä).
  bool get isTransit =>
      this != TransitMode.walk && this != TransitMode.bike && this != TransitMode.other;

  /// GTFS-/GraphQL-kulkumuoto (BUS, TRAM, SUBWAY, RAIL, FERRY, WALK, BICYCLE).
  static TransitMode fromGtfs(String? s) {
    switch ((s ?? '').toUpperCase()) {
      case 'BUS':
      case 'COACH':
        return TransitMode.bus;
      case 'TRAM':
        return TransitMode.tram;
      case 'SUBWAY':
      case 'METRO':
        return TransitMode.metro;
      case 'RAIL':
        return TransitMode.rail;
      case 'FERRY':
        return TransitMode.ferry;
      case 'WALK':
        return TransitMode.walk;
      case 'BICYCLE':
      case 'BIKE':
        return TransitMode.bike;
      default:
        return TransitMode.other;
    }
  }

  /// HFP-topicin kulkumuoto (bus, tram, train, rail, metro, ferry, ubus, robot).
  static TransitMode fromHfp(String s) {
    switch (s.toLowerCase()) {
      case 'bus':
      case 'ubus':
      case 'robot':
        return TransitMode.bus;
      case 'tram':
      case 'lightrail':
        return TransitMode.tram;
      case 'train':
      case 'rail':
        return TransitMode.rail;
      case 'metro':
      case 'subway':
        return TransitMode.metro;
      case 'ferry':
        return TransitMode.ferry;
      default:
        return TransitMode.other;
    }
  }

  /// Digitransit-moodin nimi reittihaun `modes`-parametriin.
  String? get gtfsName {
    switch (this) {
      case TransitMode.bus:
        return 'BUS';
      case TransitMode.tram:
        return 'TRAM';
      case TransitMode.metro:
        return 'SUBWAY';
      case TransitMode.rail:
        return 'RAIL';
      case TransitMode.ferry:
        return 'FERRY';
      default:
        return null;
    }
  }
}
