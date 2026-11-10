import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../core/geo.dart';
import '../models/journey.dart';
import '../models/line.dart';
import '../models/place_stop.dart';
import '../models/transit_mode.dart';
import '../models/vehicle.dart';

class _StopVisit {
  final String stopGtfsId;
  final LatLng position;
  final int arrivalEpoch;
  final int departureEpoch;
  final int delaySeconds;
  final int direction;
  final String headsign;
  final String routeGtfsId;
  final String shortName;
  final TransitMode mode;
  final String tripGtfsId;
  final bool isFullTrip;

  const _StopVisit({
    required this.stopGtfsId,
    required this.position,
    required this.arrivalEpoch,
    required this.departureEpoch,
    required this.delaySeconds,
    required this.direction,
    required this.headsign,
    required this.routeGtfsId,
    required this.shortName,
    required this.mode,
    required this.tripGtfsId,
    this.isFullTrip = false,
  });
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

/// Digitransit GraphQL- ja geokoodauspalvelun asiakas. Puhdas Dart: `http.Client` ja
/// avain ovat injektoitavissa, jolloin sitä voi testata ilman verkkoa.
class DigitransitClient {
  static const _defaultGraphql = 'https://api.digitransit.fi/routing/v2/hsl/gtfs/v1';
  static const _geocode = 'https://api.digitransit.fi/geocoding/v1';

  final http.Client _http;
  final String Function() _key;
  String Function()? _endpointProvider;
  LatLng? Function()? _focusProvider;
  String Function(LatLng from, LatLng to)? _planEndpointResolver;

  String get graphqlUrl => _endpointProvider?.call() ?? _defaultGraphql;

  void setEndpointProvider(String Function()? provider) {
    _endpointProvider = provider;
  }

  void setFocusProvider(LatLng? Function()? provider) {
    _focusProvider = provider;
  }

  void setPlanEndpointResolver(String Function(LatLng from, LatLng to)? resolver) {
    _planEndpointResolver = resolver;
  }

  /// Viimeisimmän `routesNear`-kyselyn yhteydessä 5 km pysäkeiltä poimitut
  /// reaaliaikaiset vuorot (`bussit-flutter`-tyylinen HTTPS GraphQL -paikannus).
  List<Vehicle> lastNearbyVehicles = const [];

  /// Aktiivisten matkojen (`tripGtfsId`) täydet pysäkkiaikataulut (lähtöpysäkiltä päätepysäkille),
  /// joiden avulla vuorojen sijainti interpoloidaan reaaliajassa edellisen (`prev`) ja
  /// seuraavan (`next`) pysäkin välillä sekunnin murto-osan tarkkuudella.
  final Map<String, List<_StopVisit>> _activeTripVisits = {};
  final Map<String, Vehicle> _lastPatternPositions = {};

  /// Matka- ja reittikohtaiset tie-/ratageometriat (`List<LatLng>`), joiden avulla
  /// ajoneuvot kulkevat tarkasti tien keskilinjaa pitkin eivätkä oikaise korttelien läpi.
  final Map<String, List<LatLng>> _tripGeometries = {};
  final Map<String, List<LatLng>> _routeDirectionGeometries = {};

  /// Matkakohtainen oikea `serviceDay` (vuorokauden keskiyön Unix-sekunnit), joka saadaan
  /// `Stop.stoptimesWithoutPatterns`-kyselystä. Digitransitin `Trip.stoptimes`-kentässä
  /// `serviceDay` on `0`, joten ilman tätä tallennusta/päätelmää vuoron aikaleima muuttuisi
  /// vuodeksi 1970 ja vuoro poistettaisiin virheellisesti "päättyneenä" kartalta!
  final Map<String, int> _tripServiceDays = {};

  int _resolveServiceDay(
    int? rawServiceDay,
    String tripId,
    int refSecondsFromMidnight, [
    DateTime? now,
  ]) {
    if (rawServiceDay != null && rawServiceDay > 86400) {
      _tripServiceDays[tripId] = rawServiceDay;
      return rawServiceDay;
    }
    final cached = _tripServiceDays[tripId];
    if (cached != null && cached > 86400) {
      return cached;
    }
    final t = now ?? DateTime.now();
    final nowSec = t.millisecondsSinceEpoch ~/ 1000;
    final todayMidnight = DateTime(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 1000;
    final candidates = <int>[
      todayMidnight - 86400,
      todayMidnight,
      todayMidnight + 86400,
    ];
    int bestMidnight = todayMidnight;
    int bestDiff = 1 << 30;
    for (final m in candidates) {
      final diff = ((m + refSecondsFromMidnight) - nowSec).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestMidnight = m;
      }
    }
    if (tripId.isNotEmpty) {
      _tripServiceDays[tripId] = bestMidnight;
    }
    return bestMidnight;
  }

  /// Palauttaa ajoneuvolle parhaan tunnetun tie-/ratageometrian (matkan tai reitin+suunnan mukaan).
  List<LatLng>? geometryForVehicle({
    String? tripGtfsId,
    required String routeGtfsId,
    required int direction,
  }) {
    if (tripGtfsId != null && tripGtfsId.isNotEmpty) {
      final tg = _tripGeometries[tripGtfsId];
      if (tg != null && tg.length >= 2) return tg;
    }
    final rg = _routeDirectionGeometries['$routeGtfsId:$direction'] ??
        _routeDirectionGeometries['$routeGtfsId:0'] ??
        _routeDirectionGeometries['$routeGtfsId:1'];
    if (rg != null && rg.length >= 2) return rg;
    return null;
  }

  DigitransitClient({
    http.Client? client,
    String Function()? keyProvider,
    String Function()? endpointProvider,
    LatLng? Function()? focusProvider,
    String Function(LatLng from, LatLng to)? planEndpointResolver,
  })  : _http = client ?? http.Client(),
        _key = keyProvider ?? (() => AppConfig.digitransitApiKey) {
    _endpointProvider = endpointProvider;
    _focusProvider = focusProvider;
    _planEndpointResolver = planEndpointResolver;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'digitransit-subscription-key': _key(),
      };

  Future<Map<String, dynamic>> _query(String query) async {
    return _queryWithUrl(graphqlUrl, query);
  }

  Future<Map<String, dynamic>> _queryWithUrl(String url, String query) async {
    if (_key().isEmpty) throw const ApiException('API-avain puuttuu (katso AppConfig).');
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse(url), headers: _headers, body: jsonEncode({'query': query}))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ApiException('Verkkovirhe: $e');
    }
    if (res.statusCode != 200) {
      throw ApiException('Palvelinvirhe ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['errors'] != null && body['data'] == null) {
      throw ApiException('Kyselyvirhe: ${(body['errors'] as List).first['message']}');
    }
    return body['data'] as Map<String, dynamic>;
  }

  static String _s(String v) => jsonEncode(v);

  // ---------------------------------------------------------------- Pysäkit

  /// Pysäkit [radius] metrin säteellä pisteestä, lähin ensin (mukaan lukien pysäkin linjat,
  /// jotta pysäkki ja sen linjat voidaan näyttää silloinkin kun vuoroja ei ole kyseisenä ajankohtana).
  Future<List<Stop>> stopsByRadius(LatLng c, int radius, {int max = 100}) async {
    final data = await _query('''{
      stopsByRadius(lat:${c.latitude}, lon:${c.longitude}, radius:$radius, first:$max){
        edges{node{distance stop{
          gtfsId name code platformCode vehicleMode lat lon
          patterns{headsign directionId route{gtfsId}}
          routes{gtfsId shortName longName mode}
        }}}
      }}''');
    final edges = (data['stopsByRadius']?['edges'] as List?) ?? const [];
    return [
      for (final e in edges)
        if (e['node']?['stop'] != null)
          Stop.fromJson((e['node']['stop'] as Map).cast<String, dynamic>(),
              distance: (e['node']['distance'] as num?)?.toInt()),
    ];
  }

  /// Pysäkit kartan näkymälaatikossa (keskipiste + säde).
  Future<List<Stop>> stopsInView(LatLng c, int radius) => stopsByRadius(c, radius, max: 200);

  /// Hakee annetun säteen (oletus 5000 m = 5 km) sisällä olevien pysäkkien kautta
  /// dynaamisesti kulkevat linjat (tulevien lähtöjen perusteella) sekä niiden määränpäät
  /// ja poimii samalla aktiiviset reaaliaikaiset vuorot (`lastNearbyVehicles`).
  Future<List<LineInfo>> routesNear(LatLng c, {int radius = 5000, int maxStops = 100}) async {
    final data = await _query('''{
      stopsByRadius(lat:${c.latitude}, lon:${c.longitude}, radius:$radius, first:$maxStops){
        edges{node{
          distance
          stop{
            gtfsId name code lat lon
            stoptimesWithoutPatterns(numberOfDepartures:3, timeRange:2700){
              headsign serviceDay scheduledDeparture realtimeDeparture departureDelay realtime
              trip{gtfsId directionId tripHeadsign occupancy{occupancyStatus} route{gtfsId shortName longName mode}}
            }
            routes{gtfsId shortName longName mode}
          }
        }}
      }}''');
    final rawEdges = (data['stopsByRadius']?['edges'] as List?) ?? const [];
    final edges = List<dynamic>.from(rawEdges)
      ..sort((a, b) {
        final da = (a['node']?['distance'] as num?)?.toDouble() ?? double.infinity;
        final db = (b['node']?['distance'] as num?)?.toDouble() ?? double.infinity;
        return da.compareTo(db);
      });
    final routeMaps = <String, Map<String, dynamic>>{};
    final dirHeadsigns = <String, Map<int, String>>{};
    final visitsByTrip = <String, List<_StopVisit>>{};

    // 1. Ensisijaisesti poimitaan ne linjat, joilla on oikeasti dynaamisia tulevia vuoroja lähialueen pysäkeillä
    for (final e in edges) {
      final stop = e['node']?['stop'] as Map?;
      final stopId = (stop?['gtfsId'] as String?) ?? '';
      final stopLat = (stop?['lat'] as num?)?.toDouble();
      final stopLon = (stop?['lon'] as num?)?.toDouble();
      final stoptimes = (stop?['stoptimesWithoutPatterns'] as List?) ?? const [];
      for (final stRaw in stoptimes) {
        final st = (stRaw as Map).cast<String, dynamic>();
        final trip = (st['trip'] as Map?)?.cast<String, dynamic>();
        final route = (trip?['route'] as Map?)?.cast<String, dynamic>();
        final id = route?['gtfsId'] as String?;
        if (id == null || id.isEmpty) continue;

        routeMaps.putIfAbsent(id, () => route!);
        final dir = parseDirectionId(trip?['directionId']) ?? 0;
        final dest = resolveDestinationHeadsign(
          headsign: st['headsign'] as String?,
          tripHeadsign: trip?['tripHeadsign'] as String?,
          routeLongName: route?['longName'] as String?,
          directionId: dir,
        );
        if (dest.isNotEmpty) {
          final byDir = dirHeadsigns.putIfAbsent(id, () => <int, String>{});
          byDir.putIfAbsent(dir, () => dest);
        }

        final tripId = trip?['gtfsId'] as String?;
        final serviceDay = (st['serviceDay'] as num?)?.toInt();
        final rtDep = (st['realtimeDeparture'] as num?)?.toInt() ??
            (st['scheduledDeparture'] as num?)?.toInt();
        if (tripId != null &&
            tripId.isNotEmpty &&
            stopLat != null &&
            stopLon != null &&
            serviceDay != null &&
            rtDep != null) {
          final shortName = Vehicle.cleanRouteShortName((route?['shortName'] as String?) ?? id);
          final mode = TransitMode.fromGtfs(route?['mode'] as String?);
          final delay = (st['departureDelay'] as num?)?.toInt() ?? 0;
          final resolvedDay = _resolveServiceDay(serviceDay, tripId, rtDep);
          visitsByTrip.putIfAbsent(tripId, () => <_StopVisit>[]).add(
                _StopVisit(
                  stopGtfsId: stopId,
                  position: LatLng(stopLat, stopLon),
                  arrivalEpoch: resolvedDay + rtDep,
                  departureEpoch: resolvedDay + rtDep,
                  delaySeconds: delay,
                  direction: dir,
                  headsign: dest,
                  routeGtfsId: id,
                  shortName: shortName,
                  mode: mode,
                  tripGtfsId: tripId,
                ),
              );
        }
      }
    }

    // Tallennetaan osittaiset lähdöt varalle ja haetaan lähimpänä oleville vuoroille
    // täydet trip(id: ...)-pysäkkiaikataulut (mukaan lukien jo ohitetut pysäkit),
    // jotta jokaiselle ajossa olevalle vuorolle saadaan sekä edellinen (prev) että
    // seuraava (next) pysäkki jatkuvaa liikeinterpolointia varten.
    for (final entry in visitsByTrip.entries) {
      final existing = _activeTripVisits[entry.key];
      if (existing == null || existing.isEmpty || !existing.first.isFullTrip) {
        _activeTripVisits[entry.key] = entry.value;
      }
    }

    if (visitsByTrip.isNotEmpty) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sortedTripIds = visitsByTrip.entries.toList()
        ..sort((a, b) {
          final minA = a.value
              .map((v) => (v.arrivalEpoch - nowSec).abs())
              .reduce((x, y) => x < y ? x : y);
          final minB = b.value
              .map((v) => (v.arrivalEpoch - nowSec).abs())
              .reduce((x, y) => x < y ? x : y);
          return minA.compareTo(minB);
        });
      // Poimitaan ensin jokaisen löydetyn linjan lähin vuoro ja sen jälkeen loput (max 24 kpl),
      // jotta jokaisen lähipysäkkilinjan aktiivinen vuoro tarkistetaan.
      final prioritizedTrips = <String>[];
      final seenRoutes = <String>{};
      for (final e in sortedTripIds) {
        final rId = e.value.first.routeGtfsId;
        if (seenRoutes.add(rId)) {
          prioritizedTrips.add(e.key);
        }
      }
      for (final e in sortedTripIds) {
        if (prioritizedTrips.length >= 24) break;
        if (!prioritizedTrips.contains(e.key)) {
          prioritizedTrips.add(e.key);
        }
      }
      await _fetchActiveTripSchedules(prioritizedTrips.take(24));
    }

    lastNearbyVehicles = reinterpolateGraphqlVehicles();
    final activeRouteIds = lastNearbyVehicles.map((v) => v.routeGtfsId).toSet();

    // 1-kohta: Näytetään lähipysäkkien painonapeissa VAIN sellaiset linjat, joilla sillä
    // kyselyn hetkellä on oikeasti vuoroja (ei staattisia reittejä eikä linjoja ilman vuoroja).
    final out = <LineInfo>[];
    for (final entry in routeMaps.entries) {
      final id = entry.key;
      if (visitsByTrip.isNotEmpty &&
          activeRouteIds.isNotEmpty &&
          !activeRouteIds.contains(id)) {
        continue;
      }
      final map = entry.value;
      final longName = (map['longName'] as String?) ?? '';
      final byDir = dirHeadsigns[id] ?? const <int, String>{};
      final patterns = <LinePattern>[
        for (final dir in const [0, 1])
          if ((byDir[dir] ??
                  resolveDestinationHeadsign(routeLongName: longName, directionId: dir))
              .isNotEmpty)
            LinePattern(
              code: '$id:$dir',
              directionId: dir,
              headsign: byDir[dir] ??
                  resolveDestinationHeadsign(routeLongName: longName, directionId: dir),
              geometry: const [],
              stops: const [],
            ),
      ];
      out.add(LineInfo(
        gtfsId: id,
        shortName: (map['shortName'] as String?) ?? '',
        longName: longName,
        mode: TransitMode.fromGtfs(map['mode'] as String?),
        patterns: patterns,
      ));
    }
    return out;
  }

  /// Yksittäisen pysäkin tiedot ja sen kautta kulkevat linjat.
  Future<Stop?> stop(String stopId) async {
    final data = await _query('''{
      stop(id: ${_s(stopId)}) {
        gtfsId name code platformCode vehicleMode zoneId lat lon
        patterns { headsign directionId route { gtfsId shortName longName mode } }
        routes { gtfsId shortName longName mode }
      }
    }''');
    final s = data['stop'] as Map<String, dynamic>?;
    return s == null ? null : Stop.fromJson(s);
  }

  /// Apufunktio pysäkkien GTFS-tunnusten hakemiseen Pelias-geokoodauksesta pysäkkikoodin tai nimen perusteella.
  Future<List<String>> _searchPeliasStopGtfsIds(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final queries = <String>[trimmed];

    // Jos käyttäjä antaa esim. "h 080" tai "h 0801", siivotaan väli pois -> "h080"
    final letterSpaceNum = RegExp(r'^([a-zA-Z]+)\s+(\d+)$');
    final match = letterSpaceNum.firstMatch(trimmed);
    if (match != null) {
      queries.add('${match.group(1)}${match.group(2)}');
    }
    // Jos pelkkä numerokoodi (esim. "080" tai "0801"), kokeillaan myös HSL-etuliitteitä (H=Helsinki, E=Espoo, V=Vantaa)
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      queries.add('H$trimmed');
      queries.add('E$trimmed');
      queries.add('V$trimmed');
    }

    final ids = <String>[];
    final seen = <String>{};
    final effectiveFocus = _focusProvider?.call();

    for (final qText in queries) {
      try {
        final qParams = <String, String>{
          'text': qText,
          'layers': 'stop,station',
          'size': '15',
          'boundary.country': 'FIN',
          if (effectiveFocus != null) 'focus.point.lat': '${effectiveFocus.latitude}',
          if (effectiveFocus != null) 'focus.point.lon': '${effectiveFocus.longitude}',
        };
        final uri = Uri.parse('$_geocode/search').replace(queryParameters: qParams);
        final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        for (final f in (body['features'] as List? ?? const [])) {
          final idProp = (f['properties']?['id'] as String?) ?? '';
          String gtfsId = idProp.split('#').first;
          if (gtfsId.toLowerCase().startsWith('gtfs:')) {
            gtfsId = gtfsId.substring(5);
          } else if (gtfsId.toLowerCase().startsWith('gtfs')) {
            gtfsId = gtfsId.substring(4);
          }
          if (gtfsId.isNotEmpty && seen.add(gtfsId)) {
            ids.add(gtfsId);
          }
        }
      } catch (_) {}
    }
    return ids;
  }

  /// Hakee pysäkkejä nimen tai koodin perusteella (tukee pysäkkikoodeja kuten "h080", "H0801", "0801"
  /// sekä pysäkkien nimiä kuten "Kamppi" tai "Rautatientori"). Siivoaa automaattisesti tyhjät välilyönnit edestä ja takaa.
  Future<List<Stop>> searchStops(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const [];

    try {
      // 1. Haetaan pysäkkikoodien ja nimien GTFS-tunnukset Pelias-geokoodauksesta
      final peliasIdsFuture = _searchPeliasStopGtfsIds(trimmed);

      // 2. Haetaan rinnakkain GraphQL:n stops(name: ...) -kyselystä pysäkit nimen perusteella
      final gqlNameFuture = _query('''{
        stops(name: ${_s(trimmed)}) {
          gtfsId name code platformCode vehicleMode zoneId lat lon
          patterns { headsign directionId route { gtfsId shortName longName mode } }
          routes { gtfsId shortName longName mode }
        }
      }''').then((data) {
        final list = (data['stops'] as List?) ?? const [];
        return [
          for (final s in list)
            if (s is Map && ((s['gtfsId'] as String?)?.isNotEmpty ?? false))
              Stop.fromJson(s.cast<String, dynamic>())
        ];
      }).catchError((_) => <Stop>[]);

      final results = await Future.wait([peliasIdsFuture, gqlNameFuture]);
      final peliasIds = results[0] as List<String>;
      final nameStops = results[1] as List<Stop>;

      final stopMap = <String, Stop>{
        for (final s in nameStops) s.gtfsId: s,
      };

      // 3. Jos Pelias löysi GTFS-tunnuksia, joita ei ollut nimeen perustuvassa vastauksessa,
      // haetaan niiden täydet tiedot (pysäkkikoodi, reitit, linjat jne.) GraphQL stops(ids: ...) -kyselystä.
      final missingIds = peliasIds.where((id) => !stopMap.containsKey(id)).take(20).toList();
      if (missingIds.isNotEmpty) {
        try {
          final idsArg = missingIds.map(_s).join(',');
          final data = await _query('''{
            stops(ids: [$idsArg]) {
              gtfsId name code platformCode vehicleMode zoneId lat lon
              patterns { headsign directionId route { gtfsId shortName longName mode } }
              routes { gtfsId shortName longName mode }
            }
          }''');
          final list = (data['stops'] as List?) ?? const [];
          for (final s in list) {
            if (s is Map && ((s['gtfsId'] as String?)?.isNotEmpty ?? false)) {
              final stop = Stop.fromJson(s.cast<String, dynamic>());
              stopMap[stop.gtfsId] = stop;
            }
          }
        } catch (_) {}
      }

      if (stopMap.isEmpty) return const [];

      // 4. Järjestetään tulokset parhaan osuvuuden mukaan:
      // - Tarkka koodivastaavuus (esim. H0801 haettaessa "h0801" tai "H0801")
      // - Koodi alkaa hakusanalla (esim. H0805, H0801 haettaessa "h080")
      // - Tarkka nimivastaavuus
      // - Nimi alkaa hakusanalla
      // - Pelias-järjestys / löytöjärjestys
      final qLower = trimmed.toLowerCase();
      final qUpper = trimmed.toUpperCase();
      final allStops = stopMap.values.toList();

      allStops.sort((a, b) {
        final aCode = a.code?.toUpperCase() ?? '';
        final bCode = b.code?.toUpperCase() ?? '';
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();

        final aCodeExact = aCode == qUpper;
        final bCodeExact = bCode == qUpper;
        if (aCodeExact != bCodeExact) return aCodeExact ? -1 : 1;

        final aCodeStarts = aCode.startsWith(qUpper);
        final bCodeStarts = bCode.startsWith(qUpper);
        if (aCodeStarts != bCodeStarts) return aCodeStarts ? -1 : 1;

        final aNameExact = aName == qLower;
        final bNameExact = bName == qLower;
        if (aNameExact != bNameExact) return aNameExact ? -1 : 1;

        final aNameStarts = aName.startsWith(qLower);
        final bNameStarts = bName.startsWith(qLower);
        if (aNameStarts != bNameStarts) return aNameStarts ? -1 : 1;

        final aIdx = peliasIds.indexOf(a.gtfsId);
        final bIdx = peliasIds.indexOf(b.gtfsId);
        if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
        if (aIdx != -1) return -1;
        if (bIdx != -1) return 1;

        return a.name.compareTo(b.name);
      });

      return allStops;
    } catch (_) {
      return const [];
    }
  }

  /// Hakee pysäkin koko vuorokauden vuoroaikataulun tietylle päivälle (tai tälle päivälle)
  Future<List<Departure>> stopTimetable(String stopId, {DateTime? date, int count = 250}) async {
    final now = DateTime.now();
    final targetDate = date ?? now;
    final midnight = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final isDifferentDay = targetDate.day != now.day || targetDate.month != now.month || targetDate.year != now.year;
    final startTimeSec = isDifferentDay
        ? (midnight.millisecondsSinceEpoch ~/ 1000)
        : (now.millisecondsSinceEpoch ~/ 1000);

    try {
      final data = await _query('''{
        stop(id: ${_s(stopId)}) {
          stoptimesWithoutPatterns(numberOfDepartures: $count, timeRange: 86400, startTime: $startTimeSec) {
            scheduledDeparture realtimeDeparture departureDelay realtime realtimeState serviceDay headsign
            trip { gtfsId directionId tripHeadsign occupancy{occupancyStatus} route { shortName longName mode gtfsId } }
          }
        }
      }''');
      final stopObj = data['stop'] as Map<String, dynamic>?;
      final list = (stopObj?['stoptimesWithoutPatterns'] as List?) ?? const [];
      final deps = <Departure>[];
      for (final d in list) {
        if (d is Map) {
          try {
            deps.add(Departure.fromJson(d.cast<String, dynamic>()));
          } catch (_) {}
        }
      }
      return deps;
    } catch (_) {
      return const [];
    }
  }

  Future<List<Departure>> departures(String stopId, {int count = 10}) async {
    final m = await departuresForStops([stopId], count: count);
    return m[stopId] ?? const [];
  }

  /// Usean pysäkin lähdöt yhdellä kyselyllä (aliakset).
  Future<Map<String, List<Departure>>> departuresForStops(List<String> ids,
      {int count = 3}) async {
    if (ids.isEmpty) return {};
    final b = StringBuffer('{');
    for (var i = 0; i < ids.length; i++) {
      b.write('''s$i: stop(id:${_s(ids[i])}){
        stoptimesWithoutPatterns(numberOfDepartures:$count, timeRange:7200){
          scheduledDeparture realtimeDeparture departureDelay realtime realtimeState serviceDay headsign
          trip{gtfsId directionId tripHeadsign occupancy{occupancyStatus} route{shortName longName mode gtfsId}}
        }}''');
    }
    b.write('}');
    final data = await _query(b.toString());
    final out = <String, List<Departure>>{};
    for (var i = 0; i < ids.length; i++) {
      final st = data['s$i'] as Map<String, dynamic>?;
      final list = (st?['stoptimesWithoutPatterns'] as List?) ?? const [];
      final parsed = <Departure>[];
      for (final d in list) {
        try {
          parsed.add(Departure.fromJson((d as Map).cast<String, dynamic>()));
        } catch (_) {}
      }
      out[ids[i]] = parsed;
    }
    return out;
  }

  /// Hakee tietyn pysäkin ja linjan kaikki lähdöt seuraavan 2 tunnin (tai annetun aikavälin) ajalta.
  Future<List<Departure>> departuresForStopAndLine(
    String stopId,
    String line, {
    int timeRangeSeconds = 7200,
  }) async {
    final data = await _query('''{
      stop(id: ${_s(stopId)}) {
        stoptimesWithoutPatterns(numberOfDepartures: 150, timeRange: $timeRangeSeconds) {
          scheduledDeparture realtimeDeparture departureDelay realtime realtimeState serviceDay headsign
          trip { gtfsId directionId tripHeadsign occupancy{occupancyStatus} route { shortName longName mode gtfsId } }
        }
      }
    }''');
    final stopObj = data['stop'] as Map<String, dynamic>?;
    final list = (stopObj?['stoptimesWithoutPatterns'] as List?) ?? const [];
    final deps = [
      for (final d in list) Departure.fromJson((d as Map).cast<String, dynamic>()),
    ];
    // Rajataan kyseisen linjan vuoroihin seuraavan 120 min (2 h) sisällä
    final targetLine = line.trim().toLowerCase();
    final maxMinutes = (timeRangeSeconds / 60).round();
    return deps
        .where((d) => d.line.trim().toLowerCase() == targetLine && d.minutesUntil() <= maxMinutes)
        .toList();
  }

  /// Hakee matkan (`tripGtfsId`) reaaliaikaisen kuormitustiedon (`occupancyStatus`).
  Future<String?> tripOccupancy(String tripGtfsId) async {
    if (tripGtfsId.isEmpty) return null;
    try {
      final data = await _query('''{
        trip(id: ${_s(tripGtfsId)}) {
          gtfsId
          occupancy {
            occupancyStatus
          }
        }
      }''');
      final trip = data['trip'] as Map<String, dynamic>?;
      final occ = trip?['occupancy'] as Map<String, dynamic>?;
      return occ?['occupancyStatus'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ Linjat

  Future<List<LineInfo>> searchLines(String name) async {
    final data = await _query('{routes(name:${_s(name)}){gtfsId shortName longName mode}}');
    return [
      for (final r in (data['routes'] as List))
        if ((r['gtfsId'] as String).isNotEmpty)
          LineInfo.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  /// Linja + sen kaikki patternit (geometria ja pysäkit).
  Future<LineInfo?> routeWithPatterns(String gtfsId) async {
    final data = await _query('''{
      route(id:${_s(gtfsId)}){
        gtfsId shortName longName mode
        patterns{code directionId headsign patternGeometry{points} stops{gtfsId name code platformCode vehicleMode lat lon}}
      }}''');
    final r = data['route'] as Map<String, dynamic>?;
    if (r == null) return null;
    final info = LineInfo.fromJson(r);
    for (final p in info.patterns) {
      if (p.geometry.length >= 2) {
        final existing = _routeDirectionGeometries['${info.gtfsId}:${p.directionId}'];
        if (existing == null || p.geometry.length > existing.length) {
          _routeDirectionGeometries['${info.gtfsId}:${p.directionId}'] = p.geometry;
        }
      }
    }
    return info;
  }

  /// Ajoneuvon (matkan) pysäkkikohtaiset ennusteet. Palauttaa tyhjän listan jos matkaa ei löydy.
  Future<List<TripStopTime>> tripStopTimes({
    required String routeGtfsId,
    required int direction,
    required String date, // yyyy-MM-dd
    required String startTime, // HH:mm
  }) async {
    final parts = startTime.split(':');
    var secs = (int.tryParse(parts[0]) ?? 0) * 3600 + (int.tryParse(parts[1]) ?? 0) * 60;
    // HFP:n `start` on seinäkellon aika; yli keskiyön GTFS-sekunnit ylittävät 86400.
    final day = DateTime.tryParse(date);
    if (day != null) {
      final candidate = DateTime(day.year, day.month, day.day).add(Duration(seconds: secs));
      if (DateTime.now().difference(candidate).inHours >= 12) secs += 86400;
    }
    final data = await _query('''{
      fuzzyTrip(route:${_s(routeGtfsId)}, direction:$direction, date:${_s(date)}, time:$secs){
        stoptimes{ stop{gtfsId name code lat lon vehicleMode} serviceDay scheduledArrival realtimeArrival }
      }}''');
    final trip = data['fuzzyTrip'] as Map<String, dynamic>?;
    if (trip == null) return const [];
    return [
      for (final st in (trip['stoptimes'] as List))
        () {
          final schedArr = (st['scheduledArrival'] as num).toInt();
          final rtArr = (st['realtimeArrival'] as num).toInt();
          final sDay = _resolveServiceDay(
            (st['serviceDay'] as num?)?.toInt(),
            '$routeGtfsId:$direction:$date:$startTime',
            rtArr,
          );
          return TripStopTime(
            Stop.fromJson((st['stop'] as Map).cast<String, dynamic>()),
            DateTime.fromMillisecondsSinceEpoch((sDay + schedArr) * 1000),
            DateTime.fromMillisecondsSinceEpoch((sDay + rtArr) * 1000),
          );
        }(),
    ];
  }

  /// Hakee matkan (`trip`) pysäkkikohtaiset ennusteet suoraan GTFS-tunnuksella
  /// (sama `trip(id: $gtfsId)` -kysely kuin `bussit-flutter`-projektin `trip_query.graphql`).
  Future<List<TripStopTime>> tripStopTimesById(String tripGtfsId) async {
    final data = await _query('''{
      trip(id:${_s(tripGtfsId)}){
        stoptimes{ stop{gtfsId name code lat lon vehicleMode} serviceDay scheduledArrival realtimeArrival }
      }}''');
    final trip = data['trip'] as Map<String, dynamic>?;
    if (trip == null) return const [];
    return [
      for (final st in (trip['stoptimes'] as List? ?? const []))
        () {
          final schedArr = (st['scheduledArrival'] as num).toInt();
          final rtArr = (st['realtimeArrival'] as num).toInt();
          final sDay = _resolveServiceDay(
            (st['serviceDay'] as num?)?.toInt(),
            tripGtfsId,
            rtArr,
          );
          return TripStopTime(
            Stop.fromJson((st['stop'] as Map).cast<String, dynamic>()),
            DateTime.fromMillisecondsSinceEpoch((sDay + schedArr) * 1000),
            DateTime.fromMillisecondsSinceEpoch((sDay + rtArr) * 1000),
          );
        }(),
    ];
  }

  /// Hakee annettujen reittien (`routeGtfsIds`) ajossa olevat ajoneuvot suoraan Digitransitin
  /// HTTPS GraphQL -rajapinnasta (`Pattern.vehiclePositions` sekä reaaliaikaiset pysäkkiajat).
  /// Toimii 100 % HTTPS-portissa 443 ilman riippuvuutta MQTT-soketista.
  Future<List<Vehicle>> vehiclesForRoutes(Iterable<String> routeGtfsIds) async {
    final ids = routeGtfsIds
        .map((e) => e.contains(':') ? e : 'HSL:$e')
        .toSet()
        .take(20)
        .toList();
    if (ids.isEmpty) return const [];
    final idSet = ids.toSet();

    final b = StringBuffer('{');
    for (var i = 0; i < ids.length; i++) {
      b.write('''r$i: route(id:${_s(ids[i])}){
        gtfsId shortName longName mode
        patterns{
          directionId headsign
          patternGeometry{points}
          vehiclePositions{
            vehicleId label lat lon heading speed lastUpdated
            stopRelationship{stop{gtfsId name code}}
            trip{gtfsId directionId tripHeadsign routeShortName}
          }
          stops{gtfsId}
        }
      }''');
    }
    b.write('}');

    final out = <String, Vehicle>{};
    final sampledStopIds = <String>{};
    final tripIdsToFetch = <String>{};
    final now = DateTime.now();

    // Päivitetään myös jo tunnettujen aktiivisten matkojen reaaliaikaiset ennusteet
    for (final entry in _activeTripVisits.entries) {
      if (entry.value.isNotEmpty && idSet.contains(entry.value.first.routeGtfsId)) {
        tripIdsToFetch.add(entry.key);
      }
    }

    try {
      final data = await _query(b.toString());
      for (var i = 0; i < ids.length; i++) {
        final r = data['r$i'] as Map<String, dynamic>?;
        if (r == null) continue;
        final routeGtfsId = (r['gtfsId'] as String?) ?? ids[i];
        final shortName = Vehicle.cleanRouteShortName((r['shortName'] as String?) ?? routeGtfsId);
        final longName = (r['longName'] as String?) ?? '';
        final mode = TransitMode.fromGtfs(r['mode'] as String?);
        final patterns = (r['patterns'] as List?) ?? const [];

        for (final patRaw in patterns) {
          final pat = (patRaw as Map).cast<String, dynamic>();
          final patDir = parseDirectionId(pat['directionId']) ?? 0;
          final patHead = (pat['headsign'] as String?) ?? '';
          final polyPts = (pat['patternGeometry'] as Map?)?['points'] as String?;
          List<LatLng>? patGeom;
          if (polyPts != null && polyPts.isNotEmpty) {
            patGeom = decodePolyline(polyPts);
            if (patGeom.length >= 2) {
              final key = '$routeGtfsId:$patDir';
              final existing = _routeDirectionGeometries[key];
              if (existing == null || patGeom.length > existing.length) {
                _routeDirectionGeometries[key] = patGeom;
              }
            }
          }
          final positions = (pat['vehiclePositions'] as List?) ?? const [];

          for (final vpRaw in positions) {
            final vp = (vpRaw as Map).cast<String, dynamic>();
            final lat = (vp['lat'] as num?)?.toDouble();
            final lon = (vp['lon'] as num?)?.toDouble();
            if (lat == null || lon == null) continue;

            final trip = (vp['trip'] as Map?)?.cast<String, dynamic>();
            final tripId = trip?['gtfsId'] as String?;
            if (tripId != null && tripId.isNotEmpty) {
              tripIdsToFetch.add(tripId);
            }
            final dir = parseDirectionId(trip?['directionId']) ?? patDir;
            final headsign = resolveDestinationHeadsign(
              headsign: patHead,
              tripHeadsign: trip?['tripHeadsign'] as String?,
              routeLongName: longName,
              directionId: dir,
            );
            final stopRel = (vp['stopRelationship'] as Map?)?.cast<String, dynamic>();
            final nextStop = (stopRel?['stop'] as Map?)?.cast<String, dynamic>();
            final nextStopId = nextStop?['gtfsId'] as String?;
            final rawVehId = (vp['vehicleId'] as String?) ??
                (vp['label'] as String?) ??
                tripId ??
                '$routeGtfsId:$lat:$lon';
            final vehId = rawVehId.replaceFirst('HSL:', '');
            final spdMs = (vp['speed'] as num?)?.toDouble() ?? 0.0;
            var heading = (vp['heading'] as num?)?.toDouble() ?? 0.0;
            var pos = LatLng(lat, lon);
            final geom = patGeom ?? geometryForVehicle(
              tripGtfsId: tripId,
              routeGtfsId: routeGtfsId,
              direction: dir,
            );
            if (geom != null) {
              final snapped = snapToPolyline(pos, geom);
              if (snapped != null) {
                pos = snapped.point;
                if (heading == 0.0) heading = snapped.heading;
              }
            }

            final v = Vehicle(
              id: vehId,
              line: shortName,
              routeGtfsId: routeGtfsId,
              direction: dir,
              mode: mode,
              position: pos,
              heading: heading,
              speedKmh: spdMs * 3.6,
              headsign: headsign,
              nextStopId: nextStopId,
              tripGtfsId: tripId,
              updatedAt: now,
            );
            out[vehId] = v;
            _lastPatternPositions[vehId] = v;
          }

          // Jos vehiclePositions on tyhjä, poimitaan reittikuvion varrelta (alku-, keski- ja loppupäästä)
          // muutama pysäkki, jotta löydetään kaikki reitillä parhaillaan ajavat vuorot (molempiin suuntiin).
          if (positions.isEmpty && sampledStopIds.length < 24) {
            final stops = (pat['stops'] as List?) ?? const [];
            if (stops.isNotEmpty) {
              final indices = <int>{
                0,
                stops.length ~/ 3,
                (stops.length * 2) ~/ 3,
              };
              for (final idx in indices) {
                if (idx >= 0 && idx < stops.length) {
                  final sId = (stops[idx] as Map?)?['gtfsId'] as String?;
                  if (sId != null && sId.isNotEmpty) {
                    sampledStopIds.add(sId);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // Etsitään reitin näytepysäkeiltä kaikki parhaillaan ajossa olevat tripGtfsId-tunnukset
    if (sampledStopIds.isNotEmpty) {
      final stopList = sampledStopIds.take(18).toList();
      final sb = StringBuffer('{');
      for (var i = 0; i < stopList.length; i++) {
        sb.write('''s$i: stop(id:${_s(stopList[i])}){
          stoptimesWithoutPatterns(numberOfDepartures:6, timeRange:3600){
            serviceDay scheduledDeparture realtimeDeparture
            trip{gtfsId route{gtfsId}}
          }
        }''');
      }
      sb.write('}');
      try {
        final sData = await _query(sb.toString());
        for (var i = 0; i < stopList.length; i++) {
          final stList = (sData['s$i']?['stoptimesWithoutPatterns'] as List?) ?? const [];
          for (final stRaw in stList) {
            final stMap = stRaw as Map?;
            final trip = stMap?['trip'] as Map?;
            final rId = (trip?['route'] as Map?)?['gtfsId'] as String?;
            final tId = trip?['gtfsId'] as String?;
            final sDay = (stMap?['serviceDay'] as num?)?.toInt();
            final rtDep = (stMap?['realtimeDeparture'] as num?)?.toInt() ??
                (stMap?['scheduledDeparture'] as num?)?.toInt() ??
                0;
            if (tId != null && tId.isNotEmpty && rId != null && idSet.contains(rId)) {
              if (sDay != null && sDay > 86400) {
                _resolveServiceDay(sDay, tId, rtDep);
              }
              tripIdsToFetch.add(tId);
            }
          }
        }
      } catch (_) {}
    }

    // Haetaan kaikkien löydettyjen matkojen tuoreet reaaliaikaiset pysäkkiajat (sekä menneet että tulevat pysäkit)
    if (tripIdsToFetch.isNotEmpty) {
      await _fetchActiveTripSchedules(tripIdsToFetch.take(20));
    }

    // Interpoloidaan ajoneuvojen tarkka sijainti tällä sekunnilla edellisen (prev) ja seuraavan (next) pysäkin välille
    final interpolated = reinterpolateGraphqlVehicles(routeFilter: idSet, now: now);

    for (final v in interpolated) {
      final alreadyCovered = out.values.any(
        (existing) =>
            existing.routeGtfsId == v.routeGtfsId &&
            existing.direction == v.direction &&
            (existing.tripGtfsId == v.tripGtfsId ||
                distanceMeters(existing.position, v.position) < 500),
      );
      if (!alreadyCovered) {
        out[v.id] = v;
      }
    }

    return out.values.toList();
  }

  /// Hakee annettujen matkojen (`tripGtfsIds`) täydet pysäkkiaikataulut (`trip(id: ...)`),
  /// joissa ovat mukana sekä jo ohitetut pysäkit (`prev`) että tulevat pysäkit (`next`)
  /// reaaliaikaisine viiveineen (`realtimeArrival`, `realtimeDeparture`).
  Future<void> _fetchActiveTripSchedules(Iterable<String> tripGtfsIds) async {
    final ids = tripGtfsIds.where((e) => e.isNotEmpty).toSet().take(20).toList();
    if (ids.isEmpty) return;

    final b = StringBuffer('{');
    for (var i = 0; i < ids.length; i++) {
      b.write('''t$i: trip(id:${_s(ids[i])}){
        gtfsId directionId tripHeadsign
        route{gtfsId shortName longName mode}
        tripGeometry{points}
        stoptimes{
          serviceDay scheduledArrival realtimeArrival scheduledDeparture realtimeDeparture departureDelay realtime headsign
          stop{gtfsId name code lat lon}
        }
      }''');
    }
    b.write('}');

    try {
      final data = await _query(b.toString());
      for (var i = 0; i < ids.length; i++) {
        final t = data['t$i'] as Map<String, dynamic>?;
        if (t == null) continue;
        final tripId = (t['gtfsId'] as String?) ?? ids[i];
        final route = (t['route'] as Map?)?.cast<String, dynamic>();
        final routeGtfsId = (route?['gtfsId'] as String?) ?? '';
        if (routeGtfsId.isEmpty) continue;

        final dir = parseDirectionId(t['directionId']) ?? 0;
        final polyPts = (t['tripGeometry'] as Map?)?['points'] as String?;
        if (polyPts != null && polyPts.isNotEmpty) {
          final geom = decodePolyline(polyPts);
          if (geom.length >= 2) {
            _tripGeometries[tripId] = geom;
            final key = '$routeGtfsId:$dir';
            final existing = _routeDirectionGeometries[key];
            if (existing == null || geom.length > existing.length) {
              _routeDirectionGeometries[key] = geom;
            }
          }
        }
        final shortName = Vehicle.cleanRouteShortName(
          (route?['shortName'] as String?) ?? routeGtfsId,
        );
        final longName = (route?['longName'] as String?) ?? '';
        final mode = TransitMode.fromGtfs(route?['mode'] as String?);
        final tripHead = (t['tripHeadsign'] as String?) ?? '';
        final stoptimes = (t['stoptimes'] as List?) ?? const [];

        final visits = <_StopVisit>[];
        for (final stRaw in stoptimes) {
          final st = (stRaw as Map).cast<String, dynamic>();
          final stop = (st['stop'] as Map?)?.cast<String, dynamic>();
          final stopId = (stop?['gtfsId'] as String?) ?? '';
          final lat = (stop?['lat'] as num?)?.toDouble();
          final lon = (stop?['lon'] as num?)?.toDouble();
          final rawServiceDay = (st['serviceDay'] as num?)?.toInt();
          final rtArr = (st['realtimeArrival'] as num?)?.toInt() ??
              (st['scheduledArrival'] as num?)?.toInt();
          final rtDep = (st['realtimeDeparture'] as num?)?.toInt() ??
              (st['scheduledDeparture'] as num?)?.toInt() ??
              rtArr;
          if (lat == null || lon == null || rtArr == null || rtDep == null) {
            continue;
          }
          final serviceDay = _resolveServiceDay(rawServiceDay, tripId, rtArr);
          final delay = (st['departureDelay'] as num?)?.toInt() ?? 0;
          final dest = resolveDestinationHeadsign(
            headsign: st['headsign'] as String?,
            tripHeadsign: tripHead,
            routeLongName: longName,
            directionId: dir,
          );
          visits.add(
            _StopVisit(
              stopGtfsId: stopId,
              position: LatLng(lat, lon),
              arrivalEpoch: serviceDay + rtArr,
              departureEpoch: serviceDay + rtDep,
              delaySeconds: delay,
              direction: dir,
              headsign: dest,
              routeGtfsId: routeGtfsId,
              shortName: shortName,
              mode: mode,
              tripGtfsId: tripId,
              isFullTrip: true,
            ),
          );
        }
        if (visits.isNotEmpty) {
          _activeTripVisits[tripId] = visits;
        }
      }
    } catch (_) {}
  }

  /// Laskee kaikkien muistissa olevien aktiivisten GraphQL-matkojen (`_activeTripVisits`)
  /// tämänhetkisen interpoloidun sijainnin (`LatLng`), kulkusuunnan (`heading`) ja nopeuden (`speedKmh`)
  /// sekunnin murto-osan tarkkuudella. Voidaan kutsua tiheästi (esim. 1–2 s välein) ilman verkkoliikennettä,
  /// jolloin ajoneuvot liikkuvat sulavasti pysäkiltä toiselle Live-kartalla.
  List<Vehicle> reinterpolateGraphqlVehicles({
    Set<String>? routeFilter,
    DateTime? now,
  }) {
    if (_activeTripVisits.isEmpty && _lastPatternPositions.isEmpty) return const [];
    final currentTime = now ?? DateTime.now();
    final nowSec = currentTime.millisecondsSinceEpoch / 1000.0;
    final out = <String, Vehicle>{};

    // Poistetaan jo päättyneet vuorot (> 3 min päätepysäkin jälkeen)
    _activeTripVisits.removeWhere((_, visits) {
      if (visits.isEmpty) return true;
      return visits.last.arrivalEpoch < nowSec - 180;
    });

    for (final entry in _activeTripVisits.entries) {
      final visits = List<_StopVisit>.from(entry.value)
        ..sort((a, b) => a.arrivalEpoch.compareTo(b.arrivalEpoch));
      final unique = <_StopVisit>[];
      for (final v in visits) {
        if (unique.isEmpty || unique.last.stopGtfsId != v.stopGtfsId) {
          unique.add(v);
        }
      }
      if (unique.isEmpty) continue;

      final first = unique.first;
      if (routeFilter != null && !routeFilter.contains(first.routeGtfsId)) {
        continue;
      }

      // Sallitaan 15 min (900 s) ennakkoikkuna ennen lähtöpysäkin lähtöä (sekä osittaiselle että
      // täydelle matkalle), jotta `routesNear`-haussa löydetty tai lähtöpysäkillä odottava vuoro
      // ei katoa kartalta, kun `_fetchActiveTripSchedules` päivittää `isFullTrip = true`.
      const maxLeadSec = 900.0;
      if (first.departureEpoch > nowSec + maxLeadSec || unique.last.arrivalEpoch < nowSec - 60) {
        continue;
      }

      _StopVisit? prev;
      _StopVisit? next;
      for (final v in unique) {
        if (v.arrivalEpoch <= nowSec) {
          prev = v;
        } else {
          next = v;
          break;
        }
      }

      LatLng pos;
      double heading = 0;
      double speedKmh = 30;
      _StopVisit ref;
      int? secsUntilDep;

      if (prev != null && next != null) {
        ref = next;
        final geom = geometryForVehicle(
          tripGtfsId: ref.tripGtfsId,
          routeGtfsId: ref.routeGtfsId,
          direction: ref.direction,
        );
        if (distanceMeters(prev.position, next.position) > 8) {
          heading = bearingDegrees(prev.position, next.position);
        }
        // Jos vuoro on juuri pysäkillä (saapunut, mutta ei vielä lähtenyt), se odottaa pysäkillä
        final depEpoch = prev.departureEpoch.toDouble();
        final arrEpoch = next.arrivalEpoch.toDouble();
        if (nowSec <= depEpoch || arrEpoch <= depEpoch) {
          if (geom != null) {
            final snapped = snapToPolyline(prev.position, geom);
            pos = snapped != null ? snapped.point : prev.position;
            if (snapped != null) heading = snapped.heading;
          } else {
            pos = prev.position;
          }
          speedKmh = 0;
        } else {
          final span = (arrEpoch - depEpoch).clamp(8.0, 3600.0);
          final frac = ((nowSec - depEpoch) / span).clamp(0.0, 1.0);
          if (geom != null && geom.length >= 2) {
            // Interpoloidaan tarkasti pitkin tien/radan polyviivaa, jolloin vuoro ei koskaan
            // oikaise korttelien tai talojen yli mutkissa!
            final onRoad = interpolateAlongPolyline(
              geom,
              prev.position,
              next.position,
              frac,
            );
            pos = onRoad.point;
            heading = onRoad.heading;
            speedKmh = ((onRoad.spanMeters / span) * 3.6).clamp(12.0, 110.0);
          } else {
            pos = LatLng(
              prev.position.latitude + (next.position.latitude - prev.position.latitude) * frac,
              prev.position.longitude + (next.position.longitude - prev.position.longitude) * frac,
            );
            final segMeters = distanceMeters(prev.position, next.position);
            speedKmh = ((segMeters / span) * 3.6).clamp(12.0, 110.0);
          }
        }
      } else if (prev == null && next != null) {
        ref = next;
        // Jos täyttä matkaa ei ole vielä saatu ja tiedossa on vain tulevia pysäkkejä,
        // interpoloidaan lähestyminen kohti ensimmäistä tunnettua pysäkkiä, jotta merkki liikkuu!
        if (!first.isFullTrip && unique.length >= 2) {
          final second = unique[1];
          final dLat = second.position.latitude - first.position.latitude;
          final dLon = second.position.longitude - first.position.longitude;
          final span = (second.arrivalEpoch - first.arrivalEpoch).clamp(30, 600).toDouble();
          final secsUntilFirst = (first.arrivalEpoch - nowSec).clamp(0.0, 600.0);
          final backFrac = (secsUntilFirst / span).clamp(0.0, 1.5);
          pos = LatLng(
            first.position.latitude - dLat * backFrac,
            first.position.longitude - dLon * backFrac,
          );
          if (distanceMeters(first.position, second.position) > 8) {
            heading = bearingDegrees(first.position, second.position);
          }
          speedKmh = 35;
        } else {
          pos = first.position;
          speedKmh = 0;
          if (unique.length >= 2 && distanceMeters(first.position, unique[1].position) > 8) {
            heading = bearingDegrees(first.position, unique[1].position);
          }
          final waitSec = (first.departureEpoch - nowSec).round();
          if (waitSec > 30) {
            secsUntilDep = waitSec;
          }
        }
      } else {
        ref = unique.last;
        pos = ref.position;
        speedKmh = 0;
        if (unique.length >= 2 &&
            distanceMeters(unique[unique.length - 2].position, ref.position) > 8) {
          heading = bearingDegrees(unique[unique.length - 2].position, ref.position);
        }
      }

      final id = 'gtfs:${ref.tripGtfsId}';
      out[id] = Vehicle(
        id: id,
        line: ref.shortName,
        routeGtfsId: ref.routeGtfsId,
        direction: ref.direction,
        mode: ref.mode,
        position: pos,
        heading: heading,
        speedKmh: speedKmh,
        delaySeconds: (secsUntilDep != null && secsUntilDep > 30) ? 0 : ref.delaySeconds,
        secondsUntilDeparture: secsUntilDep,
        headsign: ref.headsign,
        nextStopId: ref.stopGtfsId,
        tripGtfsId: ref.tripGtfsId,
        updatedAt: currentTime,
      );
    }

    return out.values.toList();
  }


  // -------------------------------------------------------------- Häiriöt

  Future<List<TransitAlert>> alerts() async {
    final data = await _query('''{
      alerts(feeds:["HSL"]){
        alertHeaderText alertDescriptionText effectiveStartDate effectiveEndDate alertSeverityLevel
        route{shortName mode gtfsId}
        stop{name}
      }}''');
    final list = [
      for (final a in (data['alerts'] as List))
        TransitAlert.fromJson((a as Map).cast<String, dynamic>()),
    ];
    return list.where((a) => a.isActive() && a.header.isNotEmpty).toList()
      ..sort((a, b) => _sev(b).compareTo(_sev(a)));
  }

  static int _sev(TransitAlert a) => a.isSevere ? 2 : (a.isWarning ? 1 : 0);

  // -------------------------------------------------------------- Reittihaku

  /// Reittihaku. [via] on välipisteet järjestyksessä. [arriveBy]: true = [time] on saapumisaika.
  Future<List<Itinerary>> plan({
    required LatLng from,
    required LatLng to,
    List<LatLng> via = const [],
    DateTime? time,
    bool arriveBy = false,
    Set<TransitMode> modes = const {},
    int count = 5,
  }) async {
    String coord(LatLng p) =>
        '{location:{coordinate:{latitude:${p.latitude},longitude:${p.longitude}}}}';

    final args = StringBuffer()
      ..write('origin:${coord(from)}, destination:${coord(to)}, first:$count');
    if (via.isNotEmpty) {
      args.write(', via:[${via.map((p) => '{visit:{coordinate:{latitude:${p.latitude},longitude:${p.longitude}}}}').join(',')}]');
    }
    if (time != null) {
      final iso = time.toUtc().toIso8601String();
      args.write(arriveBy
          ? ', dateTime:{latestArrival:"$iso"}'
          : ', dateTime:{earliestDeparture:"$iso"}');
    }
    final names = modes.map((m) => m.gtfsName).whereType<String>().toList();
    if (names.isNotEmpty) {
      args.write(
          ', modes:{transit:{transit:[${names.map((n) => '{mode:$n}').join(',')}]}}');
    }
    final targetUrl = _planEndpointResolver?.call(from, to) ?? graphqlUrl;
    Map<String, dynamic> data;
    try {
      data = await _queryWithUrl(targetUrl, '''{
        planConnection($args){
          edges{node{
            start end walkDistance numberOfTransfers
            legs{
              mode realTime transitLeg headsign duration distance
              start{scheduledTime estimated{time delay}}
              end{scheduledTime estimated{time delay}}
              from{name lat lon stop{gtfsId code}}
              to{name lat lon stop{gtfsId code}}
              route{shortName gtfsId}
              intermediatePlaces{name lat lon}
              legGeometry{points}
              alerts{alertHeaderText}
            }
          }}
        }}''');
    } catch (_) {
      if (targetUrl != 'https://api.digitransit.fi/routing/v2/finland/gtfs/v1') {
        data = await _queryWithUrl('https://api.digitransit.fi/routing/v2/finland/gtfs/v1', '''{
          planConnection($args){
            edges{node{
              start end walkDistance numberOfTransfers
              legs{
                mode realTime transitLeg headsign duration distance
                start{scheduledTime estimated{time delay}}
                end{scheduledTime estimated{time delay}}
                from{name lat lon stop{gtfsId code}}
                to{name lat lon stop{gtfsId code}}
                route{shortName gtfsId}
                intermediatePlaces{name lat lon}
                legGeometry{points}
                alerts{alertHeaderText}
              }
            }}
          }}''');
      } else {
        rethrow;
      }
    }

    var edges = (data['planConnection']?['edges'] as List?) ?? const [];
    if (edges.isEmpty && targetUrl != 'https://api.digitransit.fi/routing/v2/finland/gtfs/v1') {
      try {
        final fallbackData = await _queryWithUrl('https://api.digitransit.fi/routing/v2/finland/gtfs/v1', '''{
          planConnection($args){
            edges{node{
              start end walkDistance numberOfTransfers
              legs{
                mode realTime transitLeg headsign duration distance
                start{scheduledTime estimated{time delay}}
                end{scheduledTime estimated{time delay}}
                from{name lat lon stop{gtfsId code}}
                to{name lat lon stop{gtfsId code}}
                route{shortName gtfsId}
                intermediatePlaces{name lat lon}
                legGeometry{points}
                alerts{alertHeaderText}
              }
            }}
          }}''');
        final fallbackEdges = (fallbackData['planConnection']?['edges'] as List?) ?? const [];
        if (fallbackEdges.isNotEmpty) {
          edges = fallbackEdges;
        }
      } catch (_) {}
    }

    return [
      for (final e in edges) Itinerary.fromJson((e['node'] as Map).cast<String, dynamic>()),
    ];
  }

  // ------------------------------------------------------------- Geokoodaus

  /// Älykäs geokoodaus- ja paikkahaku koko Suomelle.
  ///
  /// Yhdistää rinnakkain Pelias `/search`-haun (joka löytää kaupungit, kunnat,
  /// rautatieasemat ja kaupunginosat korkealla luottamuksella) ja `/autocomplete`-haun
  /// (joka täydentää reaaliaikaiset kirjoitusmuodot).
  ///
  /// Tulokset deduplikoidaan ja järjestetään älykkäästi:
  /// 1. Kaupunki / kunta täsmähaku (esim. "Tampere", "Turku", "Oulu", "Helsinki") listan kärkeen
  /// 2. Rautatieasemat ja matkakeskukset (erityisesti jos vain juna/VR on valittuna)
  /// 3. Kaupungin/kunnan nimen alkuosa
  /// 4. Kaupunginosat (esim. Hervanta, Pasila, Tikkurila, Kallio, Tapiola)
  /// 5. Kadut ja osoitteet
  /// 6. Yksittäiset bussipysäkit ja toissijaiset yritykset/kohteet
  Future<List<GeoPlace>> autocomplete(
    String text, {
    LatLng? focus,
    int size = 10,
    bool isRailOnly = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.length < 2) return const [];
    final effectiveFocus = focus ?? _focusProvider?.call();
    final q = <String, String>{
      'text': trimmed,
      'size': '${size * 2}',
      'lang': 'fi',
      'boundary.country': 'FIN',
      if (effectiveFocus != null) 'focus.point.lat': '${effectiveFocus.latitude}',
      if (effectiveFocus != null) 'focus.point.lon': '${effectiveFocus.longitude}',
    };

    final searchUri = Uri.parse('$_geocode/search').replace(queryParameters: q);
    final autoUri = Uri.parse('$_geocode/autocomplete').replace(queryParameters: q);

    final responses = await Future.wait([
      _getRawFeatures(searchUri),
      _getRawFeatures(autoUri),
    ]);

    final rawFeatures = <Map<String, dynamic>>[];
    for (final list in responses) {
      rawFeatures.addAll(list);
    }

    final seen = <String>{};
    final uniqueFeatures = <Map<String, dynamic>>[];
    for (final f in rawFeatures) {
      final p = (f['properties'] as Map).cast<String, dynamic>();
      final name = (p['name'] as String? ?? '').trim();
      final label = (p['label'] as String? ?? '').trim();
      final layer = (p['layer'] as String? ?? '').trim();
      final coords = (f['geometry']?['coordinates'] as List?) ?? const [0.0, 0.0];
      final lat = (coords[1] as num).toDouble();
      final lon = (coords[0] as num).toDouble();

      final cityKey = (name.toLowerCase() == label.toLowerCase() &&
              (layer == 'localadmin' || layer == 'locality' || layer == 'venue'))
          ? 'city-${name.toLowerCase()}'
          : '$name-$label-$layer-${lat.toStringAsFixed(3)}-${lon.toStringAsFixed(3)}';

      if (seen.add(cityKey)) {
        uniqueFeatures.add(f);
      }
    }

    int rank(Map<String, dynamic> f) {
      final p = (f['properties'] as Map).cast<String, dynamic>();
      final name = ((p['name'] as String?) ?? '').trim().toLowerCase();
      final label = ((p['label'] as String?) ?? '').trim().toLowerCase();
      final layer = ((p['layer'] as String?) ?? '').toLowerCase();
      final queryLower = trimmed.toLowerCase();

      final isExactName = name == queryLower;
      final isPrefixName = name.startsWith(queryLower);
      final isExactLabel = label == queryLower;
      final isPrefixLabel = label.startsWith(queryLower);

      // 1. Kaupunki tai kunta täsmähaku -> AINA listan ensimmäisenä!
      if (isExactName && (layer == 'locality' || layer == 'localadmin')) return 0;
      if (isExactName && layer == 'venue' && (isExactLabel || !label.contains(','))) return 0;

      // 2. Rautatieasemat ja matkakeskukset
      if (layer == 'station') {
        if (isRailOnly) {
          if (isExactName || isExactLabel) return 0;
          return 1;
        }
        if (isExactName) return 1;
        if (isPrefixName) return 2;
        return 3;
      }

      // 3. Kaupungin tai kunnan nimen alku (esim. "Tamper" -> Tampere)
      if ((layer == 'locality' || layer == 'localadmin') && (isPrefixName || isPrefixLabel)) return 4;

      // 4. Kaupunginosat (esim. Hervanta, Pasila, Tikkurila, Kallio, Tapiola)
      if (layer == 'neighbourhood' || layer == 'borough' || layer == 'macrohood') {
        if (isExactName) return 5;
        if (isPrefixName) return 6;
        return 7;
      }
      if (isExactName && layer == 'venue' && label.contains(',')) return 5;

      // 5. Kadut ja osoitteet
      if (layer == 'address' || layer == 'street') {
        if (isPrefixName) return 8;
        return 10;
      }

      // 6. Yksittäiset pysäkit ja liikepaikat
      if (layer == 'stop') {
        if (isExactName) return 11;
        if (isPrefixName) return 12;
        return 15;
      }

      if (isExactName) return 13;
      if (isPrefixName) return 14;
      return 20;
    }

    uniqueFeatures.sort((a, b) => rank(a).compareTo(rank(b)));

    final out = <GeoPlace>[];
    for (final f in uniqueFeatures.take(size)) {
      final props = (f['properties'] as Map).cast<String, dynamic>();
      final coords = (f['geometry']?['coordinates'] as List?) ?? const [0.0, 0.0];
      final id = props['id'] as String?;
      final layer = props['layer'] as String?;
      out.add(GeoPlace(
        label: (props['name'] as String?) ?? (props['label'] as String? ?? ''),
        secondary: _secondary(props),
        position: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
        stopGtfsId: (layer == 'stop' || layer == 'station') && id != null
            ? id.replaceFirst(RegExp(r'^gtfs:?', caseSensitive: false), '')
            : null,
        layer: layer,
      ));
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _getRawFeatures(Uri uri) async {
    if (_key().isEmpty) return const [];
    try {
      final res = await _http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = body['features'] as List? ?? const [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<GeoPlace?> reverse(LatLng p) async {
    final r = await _geo('$_geocode/reverse', {
      'point.lat': '${p.latitude}',
      'point.lon': '${p.longitude}',
      'size': '1',
      'lang': 'fi',
    });
    return r.isEmpty ? null : r.first;
  }

  Future<List<GeoPlace>> _geo(String url, Map<String, String> q) async {
    if (_key().isEmpty) throw const ApiException('API-avain puuttuu (katso AppConfig).');
    final http.Response res;
    try {
      res = await _http
          .get(Uri.parse(url).replace(queryParameters: q), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiException('Verkkovirhe: $e');
    }
    if (res.statusCode != 200) throw ApiException('Osoitehaku epäonnistui (${res.statusCode})');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final out = <GeoPlace>[];
    for (final f in (body['features'] as List? ?? const [])) {
      final props = (f['properties'] as Map).cast<String, dynamic>();
      final coords = f['geometry']['coordinates'] as List;
      final id = props['id'] as String?; // esim. "gtfsHSL:1234"
      final layer = props['layer'] as String?;
      out.add(GeoPlace(
        label: (props['name'] as String?) ?? (props['label'] as String? ?? ''),
        secondary: _secondary(props),
        position: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
        stopGtfsId: (layer == 'stop' || layer == 'station') && id != null
            ? id.replaceFirst(RegExp(r'^gtfs:?', caseSensitive: false), '')
            : null,
        layer: layer,
      ));
    }
    return out;
  }

  static String? _secondary(Map<String, dynamic> p) {
    final layer = (p['layer'] as String? ?? '').toLowerCase();
    final name = (p['name'] as String? ?? '').trim();
    final label = (p['label'] as String? ?? '').trim();
    final admin = (p['localadmin'] as String?) ?? (p['locality'] as String?);

    if (layer == 'locality' || layer == 'localadmin') {
      return 'Kaupunki / Kunta';
    }
    if (layer == 'station') {
      final fullText = '$name $label'.toLowerCase();
      if (fullText.contains('linja-auto') || fullText.contains('bussi')) {
        return admin != null ? 'Linja-autoasema, $admin' : 'Linja-autoasema';
      }
      if (fullText.contains('metro') || fullText.contains('(m)')) {
        return admin != null ? 'Metroasema, $admin' : 'Metroasema';
      }
      return admin != null ? 'Rautatieasema, $admin' : 'Rautatieasema';
    }
    if (layer == 'neighbourhood' || layer == 'borough' || layer == 'macrohood') {
      return admin != null ? 'Kaupunginosa, $admin' : 'Kaupunginosa';
    }
    if (layer == 'venue' && label.contains(',')) {
      return label;
    }

    final parts = <String>[
      ?admin,
    ];
    final rawLabel = p['label'] as String?;
    if (rawLabel != null && p['name'] != null && rawLabel != p['name']) {
      return rawLabel;
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  void close() => _http.close();
}
