import 'package:latlong2/latlong.dart';
import '../core/geo.dart';
import 'place_stop.dart';
import 'transit_mode.dart';

/// Häiriötiedote.
class TransitAlert {
  final String header;
  final String description;
  final String severity; // INFO / WARNING / SEVERE / UNKNOWN_SEVERITY
  final DateTime? start;
  final DateTime? end;
  final String? routeShortName;
  final String? routeGtfsId;
  final TransitMode? mode;
  final String? stopName;

  const TransitAlert({
    required this.header,
    required this.description,
    required this.severity,
    this.start,
    this.end,
    this.routeShortName,
    this.routeGtfsId,
    this.mode,
    this.stopName,
  });

  bool get isSevere => severity == 'SEVERE';
  bool get isWarning => severity == 'WARNING' || severity == 'SEVERE';

  bool isActive([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (start != null && t.isBefore(start!)) return false;
    if (end != null && t.isAfter(end!)) return false;
    return true;
  }

  factory TransitAlert.fromJson(Map<String, dynamic> j) {
    DateTime? ts(dynamic v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;
    final route = j['route'] as Map<String, dynamic>?;
    final stop = j['stop'] as Map<String, dynamic>?;
    return TransitAlert(
      header: (j['alertHeaderText'] as String?) ?? '',
      description: (j['alertDescriptionText'] as String?) ?? '',
      severity: (j['alertSeverityLevel'] as String?) ?? 'UNKNOWN_SEVERITY',
      start: ts(j['effectiveStartDate']),
      end: ts(j['effectiveEndDate']),
      routeShortName: route?['shortName'] as String?,
      routeGtfsId: route?['gtfsId'] as String?,
      mode: route == null ? null : TransitMode.fromGtfs(route['mode'] as String?),
      stopName: stop?['name'] as String?,
    );
  }
}

/// Linjan yksi kulkusuunta/pattern oikealla geometrialla ja pysäkeillä.
class LinePattern {
  final String code;
  final int directionId;
  final String headsign;
  final List<LatLng> geometry;
  final List<Stop> stops;

  const LinePattern({
    required this.code,
    required this.directionId,
    required this.headsign,
    required this.geometry,
    required this.stops,
  });

  factory LinePattern.fromJson(Map<String, dynamic> j) {
    final points = (j['patternGeometry'] as Map<String, dynamic>?)?['points'] as String?;
    final stops = ((j['stops'] as List?) ?? const [])
        .map((s) => Stop.fromJson(s as Map<String, dynamic>))
        .toList();
    final dir = parseDirectionId(j['directionId']) ?? 0;
    final rawHead = (j['headsign'] as String?) ?? '';
    final lastStopName = stops.isNotEmpty ? stops.last.name : '';
    return LinePattern(
      code: j['code'] as String,
      directionId: dir,
      headsign: resolveDestinationHeadsign(
        headsign: rawHead.isNotEmpty ? rawHead : lastStopName,
        directionId: dir,
      ),
      geometry: points == null ? const [] : decodePolyline(points),
      stops: stops,
    );
  }
}

/// Linja (route) ja sen patternit.
class LineInfo {
  final String gtfsId;
  final String shortName;
  final String longName;
  final TransitMode mode;
  final List<LinePattern> patterns;

  const LineInfo({
    required this.gtfsId,
    required this.shortName,
    required this.longName,
    required this.mode,
    this.patterns = const [],
  });

  factory LineInfo.fromJson(Map<String, dynamic> j) => LineInfo(
        gtfsId: j['gtfsId'] as String,
        shortName: (j['shortName'] as String?) ?? '',
        longName: (j['longName'] as String?) ?? '',
        mode: TransitMode.fromGtfs(j['mode'] as String?),
        patterns: ((j['patterns'] as List?) ?? const [])
            .map((p) => LinePattern.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  /// Valitsee ajoneuvon suuntaa parhaiten vastaavan patternin (pisin suunnan pattern).
  LinePattern? patternFor(int direction, {String? headsign}) {
    final same = patterns.where((p) => p.directionId == direction).toList();
    if (same.isEmpty) return patterns.isEmpty ? null : patterns.first;
    if (headsign != null && headsign.isNotEmpty) {
      final byHead = same.where((p) => p.headsign.toLowerCase().contains(headsign.toLowerCase())).toList();
      if (byHead.isNotEmpty) {
        byHead.sort((a, b) => b.stops.length.compareTo(a.stops.length));
        return byHead.first;
      }
    }
    same.sort((a, b) => b.stops.length.compareTo(a.stops.length));
    return same.first;
  }

  /// Palauttaa suunnan (0 tai 1) mukaisen määränpään nimen (esim. "Ilmala" tai "Länsisatama")
  /// linjan kaksisuuntaisen yleisnimen ("Ilmala - Länsisatama") sijaan.
  String destinationFor(int direction, {String? fallbackHeadsign}) {
    final pat = patternFor(direction, headsign: fallbackHeadsign);
    if (pat != null) {
      final fromPat = resolveDestinationHeadsign(
        headsign: pat.headsign,
        routeLongName: longName,
        directionId: direction,
      );
      if (fromPat.isNotEmpty) return fromPat;
      if (pat.stops.isNotEmpty && pat.stops.last.name.isNotEmpty) {
        return pat.stops.last.name;
      }
    }
    return resolveDestinationHeadsign(
      headsign: fallbackHeadsign,
      routeLongName: longName,
      directionId: direction,
    );
  }
}

/// Aikataulu-/ennustepiste yhdellä pysäkillä ajoneuvon matkalla.
class TripStopTime {
  final Stop stop;
  final DateTime scheduled;
  final DateTime realtime;
  const TripStopTime(this.stop, this.scheduled, this.realtime);
}
