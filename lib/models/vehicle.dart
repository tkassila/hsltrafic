import 'package:latlong2/latlong.dart';
import 'place_stop.dart';
import 'transit_mode.dart';

/// Ajoneuvon reaaliaikainen sijainti HFP-datasta.
class Vehicle {
  final String id; // operaattori + ajoneuvonumero
  final String line; // linjatunnus (desi)
  final String routeGtfsId; // esim. HSL:1004
  final int direction; // GTFS-suunta 0/1 (HFP dir 1/2 -> 0/1)
  final TransitMode mode;
  final LatLng position;
  final double heading;
  final double speedKmh;
  final int delaySeconds; // positiivinen = myöhässä
  final String headsign;
  final String? startTime; // esim. 07:20
  final String? operatingDay; // YYYY-MM-DD
  final String? nextStopId;
  final String? tripGtfsId; // esim. HSL:3001K_... (Digitransit GraphQL trip ID)
  final int? occupancy; // 0..100 jos saatavilla
  final DateTime updatedAt;
  final int? secondsUntilDeparture; // jos odottaa lähtöpysäkillä

  const Vehicle({
    required this.id,
    required this.line,
    required this.routeGtfsId,
    required this.direction,
    required this.mode,
    required this.position,
    required this.updatedAt,
    this.heading = 0,
    this.speedKmh = 0,
    this.delaySeconds = 0,
    this.headsign = '',
    this.startTime,
    this.operatingDay,
    this.nextStopId,
    this.tripGtfsId,
    this.occupancy,
    this.secondsUntilDeparture,
  });

  /// Onko ajoneuvo pysäkillä tai päätepysäkillä odottamassa lähtöaikaansa.
  bool get isWaitingForDeparture {
    if (secondsUntilDeparture != null && secondsUntilDeparture! > 30 && speedKmh < 5.0) {
      return true;
    }
    if (delaySeconds < -120 && speedKmh < 3.0) {
      return true;
    }
    return false;
  }

  /// Näytetäänkö ajoneuvolle kulkusuuntaa osoittava nuoli:
  /// 1) Liikkeessä olevalle vuorolle (nopeus > 0.5 km/h): näytetään kulkusuuntanuoli vuororenkaan eteen.
  /// 2) Jos vuoro on päätepysäkillä ja 0 km/h (tai odottaa lähtöä): nuolta ei näytetä.
  bool get showHeadingArrow {
    if (isWaitingForDeparture) {
      return false;
    }
    if (nextStopId == null && speedKmh <= 2.0) {
      return false;
    }
    if (speedKmh <= 0.5) {
      return false;
    }
    return true;
  }

  /// Minuuttia lähtöön päätepysäkillä.
  int get minutesUntilDeparture {
    if (secondsUntilDeparture != null && secondsUntilDeparture! > 0) {
      return (secondsUntilDeparture! / 60).round();
    }
    if (delaySeconds < 0) {
      return (-delaySeconds / 60).round();
    }
    return 0;
  }

  /// Ajoneuvon vanhentumistarkistus:
  /// - Liikkuva ajoneuvo: pidetään kartalla 2 minuuttia (120 s) ilman uusia viestejä (esim. katveet ja viiveet).
  /// - Päätepysäkillä tai pysäkillä seisova ajoneuvo (nopeus < 3 km/h tai päätepysäkki ilman seuraavaa pysäkkiä):
  ///   pidetään kartalla 10 minuuttia (600 s), jotta päätepysäkillä tauolla tai lähtöä odottava vuoro
  ///   pysyy kartalla eikä katoa 60 sekunnin jälkeen!
  bool isStale([DateTime? now]) {
    final diff = (now ?? DateTime.now()).difference(updatedAt).inSeconds;
    final isStanding = speedKmh < 3.0 || nextStopId == null;
    final maxAgeSeconds = isStanding ? 600 : 120;
    return diff > maxAgeSeconds;
  }

  Vehicle copyWith({
    LatLng? position,
    double? heading,
    String? headsign,
    String? line,
    double? speedKmh,
    int? delaySeconds,
    int? secondsUntilDeparture,
  }) =>
      Vehicle(
        id: id,
        line: line ?? this.line,
        routeGtfsId: routeGtfsId,
        direction: direction,
        mode: mode,
        position: position ?? this.position,
        updatedAt: updatedAt,
        heading: heading ?? this.heading,
        speedKmh: speedKmh ?? this.speedKmh,
        delaySeconds: delaySeconds ?? this.delaySeconds,
        headsign: headsign ?? this.headsign,
        startTime: startTime,
        operatingDay: operatingDay,
        nextStopId: nextStopId,
        tripGtfsId: tripGtfsId,
        occupancy: occupancy,
        secondsUntilDeparture: secondsUntilDeparture ?? this.secondsUntilDeparture,
      );

  /// Siivoaa HSL:n sisäisen JORE/GTFS-reittikoodin (esim. lähijuna "3001K" -> "K",
  /// "3002A" -> "A", metro "31M1" -> "M1") ihmisen luettavaksi linjatunnukseksi.
  static String cleanRouteShortName(String raw) {
    final s = raw.replaceFirst('HSL:', '').trim();
    final railMatch = RegExp(r'^300[12]([A-Z])$', caseSensitive: false).firstMatch(s);
    if (railMatch != null) {
      return railMatch.group(1)!.toUpperCase();
    }
    final metroMatch = RegExp(r'^31(M[12])$', caseSensitive: false).firstMatch(s);
    if (metroMatch != null) {
      return metroMatch.group(1)!.toUpperCase();
    }
    return s;
  }

  /// Purkaa HFP-viestin. [topic] esim.
  /// `/hfp/v2/journey/ongoing/vp/bus/0055/01216/1069/1/Malmi/07:20/1130106/2/60;24/19/73/44`.
  /// Palauttaa null jos viesti ei kelpaa.
  static Vehicle? fromHfp(String topic, Map<String, dynamic> json) {
    final vp = json['VP'] as Map<String, dynamic>?;
    if (vp == null) return null;
    final lat = (vp['lat'] as num?)?.toDouble();
    final lon = (vp['long'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final parts = topic.split('/');
    // ['', 'hfp', 'v2', 'journey', temporal, event, mode, operator, vehicle, route, dir, headsign, start, nextStop, ...]
    if (parts.length < 14) return null;
    final mode = TransitMode.fromHfp(parts[6]);
    final route = parts[9];
    final dir = int.tryParse(parts[10]) ?? 1;
    final gtfsDir = dir == 2 ? 1 : 0;
    final oper = (vp['oper'] ?? parts[7]).toString();
    final veh = (vp['veh'] ?? parts[8]).toString();
    final dl = (vp['dl'] as num?)?.toInt() ?? 0; // positiivinen = etuajassa
    final spd = ((vp['spd'] as num?)?.toDouble() ?? 0) * 3.6;
    final rawDesi = (vp['desi'] as String?)?.trim();
    final cleanLine = (rawDesi != null && rawDesi.isNotEmpty)
        ? cleanRouteShortName(rawDesi)
        : cleanRouteShortName(route);
    final start = parts[12];

    int? secsUntilDep;
    if (spd < 3.0 && start.contains(':')) {
      final hmParts = start.split(':');
      if (hmParts.length >= 2) {
        final startH = int.tryParse(hmParts[0]);
        final startM = int.tryParse(hmParts[1]);
        if (startH != null && startM != null) {
          final now = DateTime.now();
          var depTime = DateTime(now.year, now.month, now.day, startH, startM);
          if (depTime.isBefore(now.subtract(const Duration(hours: 12)))) {
            depTime = depTime.add(const Duration(days: 1));
          } else if (depTime.isAfter(now.add(const Duration(hours: 12)))) {
            depTime = depTime.subtract(const Duration(days: 1));
          }
          final diffSec = depTime.difference(now).inSeconds;
          if (diffSec > 30) {
            secsUntilDep = diffSec;
          }
        }
      }
    }
    if (secsUntilDep == null && spd < 3.0) {
      if (dl < -120) {
        secsUntilDep = -dl;
      } else if (dl > 120) {
        secsUntilDep = dl;
      }
    }

    return Vehicle(
      id: '$oper/$veh',
      line: cleanLine,
      routeGtfsId: 'HSL:$route',
      direction: gtfsDir,
      mode: mode,
      position: LatLng(lat, lon),
      heading: ((vp['hdg'] as num?)?.toDouble() ?? 0),
      speedKmh: spd,
      delaySeconds: (secsUntilDep != null && secsUntilDep > 30) ? 0 : -dl,
      secondsUntilDeparture: secsUntilDep,
      headsign: resolveDestinationHeadsign(
        headsign: Uri.decodeComponent(parts[11]),
        directionId: gtfsDir,
      ),
      startTime: parts[12],
      operatingDay: vp['oday'] as String?,
      nextStopId: parts[13].isEmpty || parts[13] == 'EOL' ? null : 'HSL:${parts[13]}',
      occupancy: (vp['occu'] as num?)?.toInt(),
      updatedAt: DateTime.now(),
    );
  }
}
