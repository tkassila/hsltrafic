import 'package:latlong2/latlong.dart';
import '../core/geo.dart';
import 'transit_mode.dart';

/// Yksi reitin osuus (kävely, bussi, metro...).
class Leg {
  final TransitMode mode;
  final String fromName;
  final LatLng fromPos;
  final String? fromStopId;
  final String toName;
  final LatLng toPos;
  final String? toStopId;
  final DateTime start;
  final DateTime end;
  final int delaySeconds;
  final bool realTime;
  final String? line;
  final String? routeGtfsId;
  final String headsign;
  final List<LatLng> geometry;
  final List<({String name, LatLng pos})> intermediate;
  final double distance;
  final List<String> alerts;

  const Leg({
    required this.mode,
    required this.fromName,
    required this.fromPos,
    required this.toName,
    required this.toPos,
    required this.start,
    required this.end,
    this.fromStopId,
    this.toStopId,
    this.delaySeconds = 0,
    this.realTime = false,
    this.line,
    this.routeGtfsId,
    this.headsign = '',
    this.geometry = const [],
    this.intermediate = const [],
    this.distance = 0,
    this.alerts = const [],
  });

  Duration get duration => end.difference(start);
  bool get isTransit => mode.isTransit;

  static LatLng _pos(Map<String, dynamic> m) =>
      LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());

  static DateTime _time(Map<String, dynamic> p) {
    final est = (p['estimated'] as Map<String, dynamic>?)?['time'] as String?;
    final sched = (p['scheduledTime'] as String);
    return DateTime.parse(est ?? sched).toLocal();
  }

  static int _delay(Map<String, dynamic> p) {
    final est = p['estimated'] as Map<String, dynamic>?;
    final d = est?['delay'];
    // delay voi olla ISO-8601-kesto (PT1M) tai sekunnit
    if (d is num) return d.toInt();
    if (d is String) {
      final m = RegExp(r'^(-?)PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(d);
      if (m != null) {
        final s = (int.tryParse(m[2] ?? '0') ?? 0) * 3600 +
            (int.tryParse(m[3] ?? '0') ?? 0) * 60 +
            (int.tryParse(m[4] ?? '0') ?? 0);
        return m[1] == '-' ? -s : s;
      }
    }
    return 0;
  }

  factory Leg.fromJson(Map<String, dynamic> j) {
    final from = j['from'] as Map<String, dynamic>;
    final to = j['to'] as Map<String, dynamic>;
    final route = j['route'] as Map<String, dynamic>?;
    final points = (j['legGeometry'] as Map<String, dynamic>?)?['points'] as String?;
    return Leg(
      mode: TransitMode.fromGtfs(j['mode'] as String?),
      fromName: (from['name'] as String?) ?? '',
      fromPos: _pos(from),
      fromStopId: (from['stop'] as Map<String, dynamic>?)?['gtfsId'] as String?,
      toName: (to['name'] as String?) ?? '',
      toPos: _pos(to),
      toStopId: (to['stop'] as Map<String, dynamic>?)?['gtfsId'] as String?,
      start: _time(j['start'] as Map<String, dynamic>),
      end: _time(j['end'] as Map<String, dynamic>),
      delaySeconds: _delay(j['start'] as Map<String, dynamic>),
      realTime: (j['realtime'] as bool?) ?? (j['realTime'] as bool?) ?? false,
      line: route?['shortName'] as String?,
      routeGtfsId: route?['gtfsId'] as String?,
      headsign: (j['headsign'] as String?) ?? '',
      geometry: points == null ? const [] : decodePolyline(points),
      intermediate: ((j['intermediatePlaces'] as List?) ?? const [])
          .map((e) => (
                name: ((e as Map<String, dynamic>)['name'] as String?) ?? '',
                pos: _pos(e),
              ))
          .toList(),
      distance: (j['distance'] as num?)?.toDouble() ?? 0,
      alerts: ((j['alerts'] as List?) ?? const [])
          .map((a) => ((a as Map<String, dynamic>)['alertHeaderText'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}

/// Yksi reittivaihtoehto.
class Itinerary {
  final DateTime start;
  final DateTime end;
  final int walkDistance;
  final int transfers;
  final List<Leg> legs;

  const Itinerary({
    required this.start,
    required this.end,
    required this.walkDistance,
    required this.transfers,
    required this.legs,
  });

  Duration get duration => end.difference(start);
  List<String> get alerts => [for (final l in legs) ...l.alerts];
  bool get hasAlerts => legs.any((l) => l.alerts.isNotEmpty);
  List<LatLng> get allPoints => [
        for (final l in legs)
          if (l.geometry.isNotEmpty) ...l.geometry else ...[l.fromPos, l.toPos],
      ];

  factory Itinerary.fromJson(Map<String, dynamic> j) => Itinerary(
        start: DateTime.parse(j['start'] as String).toLocal(),
        end: DateTime.parse(j['end'] as String).toLocal(),
        walkDistance: ((j['walkDistance'] as num?) ?? 0).round(),
        transfers: (j['numberOfTransfers'] as num?)?.toInt() ?? 0,
        legs: ((j['legs'] as List?) ?? const [])
            .map((l) => Leg.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}
