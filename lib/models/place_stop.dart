import 'package:latlong2/latlong.dart';
import 'transit_mode.dart';

/// Osoite, paikka tai oma sijainti (geokoodauksen/GPS:n tulos).
class GeoPlace {
  final String label;
  final String? secondary;
  final LatLng position;
  final bool isCurrentLocation;
  final String? stopGtfsId;

  const GeoPlace({
    required this.label,
    required this.position,
    this.secondary,
    this.isCurrentLocation = false,
    this.stopGtfsId,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'secondary': secondary,
        'lat': position.latitude,
        'lon': position.longitude,
        'stop': stopGtfsId,
      };

  factory GeoPlace.fromJson(Map<String, dynamic> j) => GeoPlace(
        label: j['label'] as String,
        secondary: j['secondary'] as String?,
        position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        stopGtfsId: j['stop'] as String?,
      );
}

/// Muuntaa GTFS directionId -arvon (voi olla int tai String "0"/"1") kokonaisluvuksi.
int? parseDirectionId(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// Pysäkin kautta kulkeva linja (näytetään silloinkin, kun pysäkillä ei ole vuoroja kyseisenä ajankohtana).
class StopRoute {
  final String gtfsId;
  final String shortName;
  final String longName;
  final TransitMode mode;
  final String headsign;

  const StopRoute({
    required this.gtfsId,
    required this.shortName,
    required this.longName,
    required this.mode,
    required this.headsign,
  });

  factory StopRoute.fromJson(Map<String, dynamic> j, {int? directionId, String? patternHeadsign}) {
    final longName = (j['longName'] as String?) ?? '';
    return StopRoute(
      gtfsId: (j['gtfsId'] as String?) ?? '',
      shortName: (j['shortName'] as String?) ?? '?',
      longName: longName,
      mode: TransitMode.fromGtfs(j['mode'] as String?),
      headsign: resolveDestinationHeadsign(
        headsign: patternHeadsign,
        routeLongName: longName,
        directionId: directionId,
      ),
    );
  }
}

/// Pysäkki (tai asema). [distance] on asetettu vain säteellä haetuille pysäkeille.
class Stop {
  final String gtfsId;
  final String name;
  final String? code;
  final String? platformCode;
  final String? zoneId;
  final TransitMode mode;
  final LatLng position;
  final int? distance;
  final List<StopRoute> routes;

  const Stop({
    required this.gtfsId,
    required this.name,
    required this.position,
    this.code,
    this.platformCode,
    this.zoneId,
    this.mode = TransitMode.bus,
    this.distance,
    this.routes = const [],
  });

  factory Stop.fromJson(Map<String, dynamic> j, {int? distance}) {
    final rawPatterns = (j['patterns'] as List?) ?? const [];
    final patternHeadsigns = <String, String>{};
    final patternDirections = <String, int>{};
    for (final p in rawPatterns) {
      if (p is Map) {
        final r = p['route'] as Map?;
        final rId = r?['gtfsId'] as String?;
        final hs = p['headsign'] as String?;
        final dir = parseDirectionId(p['directionId']);
        if (rId != null) {
          if (hs != null && hs.isNotEmpty) patternHeadsigns.putIfAbsent(rId, () => hs);
          if (dir != null) patternDirections.putIfAbsent(rId, () => dir);
        }
      }
    }

    final rawRoutes = (j['routes'] as List?) ?? const [];
    final seenRoutes = <String>{};
    final parsedRoutes = <StopRoute>[];
    for (final r in rawRoutes) {
      if (r is Map) {
        final rMap = r.cast<String, dynamic>();
        final rId = rMap['gtfsId'] as String? ?? '';
        final sr = StopRoute.fromJson(
          rMap,
          patternHeadsign: patternHeadsigns[rId],
          directionId: patternDirections[rId],
        );
        final key = sr.gtfsId.isNotEmpty ? sr.gtfsId : sr.shortName;
        if (key.isNotEmpty && seenRoutes.add(key)) {
          parsedRoutes.add(sr);
        }
      }
    }
    final rawMode = j['vehicleMode'] as String?;
    final resolvedMode = rawMode != null
        ? TransitMode.fromGtfs(rawMode)
        : (parsedRoutes.isNotEmpty ? parsedRoutes.first.mode : TransitMode.bus);

    return Stop(
      gtfsId: j['gtfsId'] as String,
      name: (j['name'] as String?) ?? '',
      code: j['code'] as String?,
      platformCode: j['platformCode'] as String?,
      zoneId: j['zoneId'] as String?,
      mode: resolvedMode,
      position: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
      distance: distance,
      routes: parsedRoutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'gtfsId': gtfsId,
        'name': name,
        'code': code,
        'platformCode': platformCode,
        'zoneId': zoneId,
        'vehicleMode': mode.gtfsName,
        'lat': position.latitude,
        'lon': position.longitude,
      };

  /// Pysäkin kuvaus listaan: "H0102 • laituri 2".
  String get subtitle {
    final parts = <String>[
      if (code != null && code!.isNotEmpty) code!,
      if (platformCode != null && platformCode!.isNotEmpty) 'laituri ${platformCode!}',
    ];
    return parts.join(' • ');
  }
}

/// Palauttaa vuoron tarkan määränpään nimen (esim. "Ilmala" tai "Länsisatama")
/// linjan kaksisuuntaisen yleisnimen (esim. "Ilmala - Länsisatama") sijaan.
String resolveDestinationHeadsign({
  String? headsign,
  String? tripHeadsign,
  String? routeLongName,
  int? directionId,
}) {
  String pick(String? s) {
    if (s == null) return '';
    final trimmed = s.trim();
    if (trimmed.isEmpty || trimmed == 'XXX') return '';
    return trimmed;
  }

  var raw = pick(headsign);
  if (raw.isEmpty) raw = pick(tripHeadsign);
  if (raw.isEmpty) raw = pick(routeLongName);
  if (raw.isEmpty) return '';

  // Jos teksti on linjan kaksisuuntainen yleisnimi (esim. "Ilmala - Länsisatama"),
  // poimitaan kulkusuunnan mukainen määränpää (direction 0 -> jälkimmäinen, 1 -> ensimmäinen).
  final parts = raw.split(RegExp(r'\s+[-–—/]\s+'));
  if (parts.length >= 2) {
    return (directionId == 1 ? parts.first : parts.last).trim();
  }
  return raw;
}

/// Yksittäinen lähtö pysäkiltä.
class Departure {
  final String line;
  final String? routeGtfsId;
  final String? tripGtfsId;
  final int? directionId;
  final TransitMode mode;
  final String headsign;
  final DateTime scheduled;
  final DateTime realtime;
  final bool isRealtime;
  final bool canceled;

  const Departure({
    required this.line,
    required this.mode,
    required this.headsign,
    required this.scheduled,
    required this.realtime,
    required this.isRealtime,
    this.canceled = false,
    this.routeGtfsId,
    this.tripGtfsId,
    this.directionId,
  });

  int get delaySeconds => realtime.difference(scheduled).inSeconds;

  /// Minuutit lähtöön (alaraja 0).
  int minutesUntil([DateTime? now]) {
    final d = realtime.difference(now ?? DateTime.now());
    return d.isNegative ? 0 : (d.inSeconds / 60).round();
  }

  factory Departure.fromJson(Map<String, dynamic> j) {
    final serviceDay = (j['serviceDay'] as num).toInt();
    final sched = (j['scheduledDeparture'] as num).toInt();
    final real = (j['realtimeDeparture'] as num?)?.toInt() ?? sched;
    final trip = j['trip'] as Map<String, dynamic>?;
    final route = trip?['route'] as Map<String, dynamic>?;
    final dir = parseDirectionId(trip?['directionId']);
    return Departure(
      line: (route?['shortName'] as String?) ?? '?',
      routeGtfsId: route?['gtfsId'] as String?,
      tripGtfsId: trip?['gtfsId'] as String?,
      directionId: dir,
      mode: TransitMode.fromGtfs(route?['mode'] as String?),
      headsign: resolveDestinationHeadsign(
        headsign: j['headsign'] as String?,
        tripHeadsign: trip?['tripHeadsign'] as String?,
        routeLongName: route?['longName'] as String?,
        directionId: dir,
      ),
      scheduled: DateTime.fromMillisecondsSinceEpoch((serviceDay + sched) * 1000),
      realtime: DateTime.fromMillisecondsSinceEpoch((serviceDay + real) * 1000),
      isRealtime: (j['realtime'] as bool?) ?? false,
      canceled: j['realtimeState'] == 'CANCELED',
    );
  }
}

/// Pysäkki + sen lähdöt (lähipysäkkihaun tulos).
class NearbyStop {
  final Stop stop;
  final List<Departure> departures;
  const NearbyStop(this.stop, this.departures);
}
