import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../models/line.dart';
import '../models/place_stop.dart';
import '../models/transit_mode.dart';
import '../models/vehicle.dart';
import 'app_state.dart';

/// Live-kartan tila: ajoneuvot HFP:stä, suodattimet, valittu ajoneuvo reitteineen.
/// Pilkkoo hakukyselyn yksittäisiksi linjahakusanoiksi (erottimina pilkku, puolipiste tai välilyönti).
List<String> splitSearchTokens(String query) {
  return query
      .split(RegExp(r'[\s,;]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Tarkistaa täsmääkö annettu linjatunnus (esim. "9", "9N", "69", "69N", "M1", "P")
/// käyttäjän hakukyselyyn (tukee myös usean linjan hakua, esim. "9, 69" tai "550 560").
///
/// Logiikka tukee:
/// - Saman linjan numero- ja kirjainvariantteja symmetrisesti:
///   Esim. haku "9" täsmää linjoihin "9", "9N", "9B" jne.
///   ja haku "9N" täsmää linjoihin "9N", "9" jne.
/// - Samoin linjalle "69" haku "69" ja "69N" ovat yhtä hyviä.
/// - Usean linjan samanaikaista hakua pilkulla tai välilyönnillä erotettuna.
/// - Estää virheelliset etuliiteosumat (esim. haku "9" EI saa täsmätä linjoihin "90", "92", "94").
/// - Erottaa metron ja ratikan (esim. "M1" ei täsmää ratikkaan "1").
/// - Tukee kirjainlinjoja (junat kuten "P", "K" ja metron yleishaku "M").
bool isLineMatching(String candidateLine, String query) {
  final c = candidateLine.trim().toUpperCase();
  if (c.isEmpty) return false;
  final tokens = splitSearchTokens(query);
  if (tokens.isEmpty) return false;
  for (final token in tokens) {
    if (_isSingleLineMatching(c, token.toUpperCase())) return true;
  }
  return false;
}

bool _isSingleLineMatching(String rawC, String rawQ) {
  final c = Vehicle.cleanRouteShortName(rawC).toUpperCase();
  final q = Vehicle.cleanRouteShortName(rawQ).toUpperCase();
  if (c.isEmpty || q.isEmpty) return false;
  if (c == q) return true;

  final cDigits = c.replaceAll(RegExp(r'[^0-9]'), '');
  final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');

  // Jos kyselyssä ei ole lainkaan numeroita (esim. lähijuna "K", "P", "I" tai metro "M")
  if (qDigits.isEmpty) {
    if (q == 'M') {
      return c == 'M' || c == 'M1' || c == 'M2';
    }
    return c == q;
  }

  // Jos kandidaatissa ei ole numeroita, mutta kyselyssä on, ne eivät täsmää
  if (cDigits.isEmpty) return false;

  // Erotellaan numeroiden edessä oleva etuliite (esim. "M" sanassa "M1")
  final cPrefixMatch = RegExp(r'^([^0-9]+)').firstMatch(c);
  final qPrefixMatch = RegExp(r'^([^0-9]+)').firstMatch(q);
  final cPrefix = cPrefixMatch?.group(1) ?? '';
  final qPrefix = qPrefixMatch?.group(1) ?? '';

  if (cPrefix != qPrefix) return false;

  // Verrataan numeerista runko-osaa (esim. "9" == "9", "69" == "69")
  final cNum = int.tryParse(cDigits);
  final qNum = int.tryParse(qDigits);
  if (cNum != null && qNum != null && cNum == qNum) {
    return true;
  }

  return cDigits == qDigits;
}

class LiveMapController extends ChangeNotifier {
  final Services s;
  StreamSubscription<List<Vehicle>>? _sub;
  StreamSubscription<bool>? _connSub;
  Timer? _debounce;

  List<Vehicle> _all = const [];
  List<Vehicle> _graphqlVehicles = const [];
  bool connected = false;
  bool _active = false;
  bool _appPaused = false;
  bool _pollingInFlight = false;
  int _pollTickCount = 0;
  DateTime? _lastRoutesNearFetch;
  Timer? _pollTimer;

  bool get isActive => _active;

  /// Näkyvillä olevat kulkumuodot.
  final Set<TransitMode> modes = {
    TransitMode.bus,
    TransitMode.tram,
    TransitMode.metro,
    TransitMode.rail,
    TransitMode.ferry,
  };
  String lineFilter = '';

  /// Käyttäjän ympäristö (oletus 5000 m = 5 km), jonka pysäkkien kautta kulkevat linjat tilataan.
  double radius = 5000;
  LatLng center = const LatLng(60.1699, 24.9384);

  /// 5 km säteellä olevien pysäkkien kautta kulkevat aktiiviset linjat (oletushaku).
  List<LineInfo> _nearbyRoutes = const [];
  Set<String> _nearbyRouteGtfsIds = const {};
  LatLng? _nearbyRoutesCenter;

  /// Käyttäjän hakeman linjan reitti-ID:t.
  Set<String> _searchedRouteGtfsIds = const {};
  Timer? _filterDebounce;
  Timer? _awaitingVehiclesTimer;
  bool isSearchingRoutes = false;

  /// Tosi silloin, kun käyttäjä on painanut "Kaikkia"-painonappia hakeakseen kaikkien
  /// 1-kohdan lähipysäkkilinjojen live-seurannassa olevat vuorot.
  bool isAllNearbyLinesActive = false;

  /// Tosi silloin, kun uusi linjahaku on juuri tilattu MQTT:stä ja odotetaan ensimmäistä
  /// sijaintiviestiä (varoaika estää virheellisen "Ei vuoroja" -ilmoituksen 0 ms kohdalla).
  bool isAwaitingHfpVehicles = false;

  /// Linjahakujen välimuisti istunnon ajaksi (säästää mobiilidataa ja tekee toistuvista hauista välittömiä).
  final Map<String, List<LineInfo>> _lineSearchCache = {};

  /// Viimeksi haetut linjat pikavalintoja varten (max 6 kpl).
  final List<String> recentSearches = [];

  /// 1) Lähimpien pysäkkien linjanumerot etäisyysjärjestyksessä pikavalintoja varten (max 10 kpl).
  /// Sisältää vain ne linjat, joilla lähipysäkkien kyselyn (`routesNear`) hetkellä on vuoroja.
  List<String> get nearbyShortNames {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _nearbyRoutes) {
      final name = Vehicle.cleanRouteShortName(r.shortName).trim();
      if (name.isEmpty) continue;
      if (seen.add(name)) {
        out.add(name);
        if (out.length >= 10) break;
      }
    }
    return out;
  }

  // Valittu ajoneuvo ja linjatietojen välimuisti (määränpään & reitin selvitykseen)
  String? selectedId;
  LineInfo? selectedLine;
  LinePattern? selectedPattern;
  List<TripStopTime> tripTimes = const [];
  bool loadingSelection = false;
  bool follow = false;

  // Onko vuoron alakortti/pysäkkilista näkyvissä (suljettaessa ruksista linjakartta jää silti näkyviin)
  bool isVehicleCardVisible = true;

  // Käyttäjän valitsema pysäkki vuoron reitiltä kartalla näytettäväksi
  Stop? selectedStop;
  TripStopTime? selectedTripStopTime;
  final Map<String, LineInfo> _lineCache = {};
  final Map<String, LineInfo> _routeInfoByGtfsId = {};
  final Set<String> _fetchingRoutes = {};

  // Pysäkit kartalla
  List<Stop> stops = const [];

  LiveMapController(this.s) {
    s.hfp.lineMatcher = isLineMatching;
    _sub = s.hfp.stream.listen((v) {
      _all = v;
      if (isAwaitingHfpVehicles && vehicles.isNotEmpty) {
        _awaitingVehiclesTimer?.cancel();
        isAwaitingHfpVehicles = false;
      }
      notifyListeners();
    });
    _connSub = s.hfp.connection.listen((c) {
      connected = c;
      notifyListeners();
    });
  }

  /// Rikastaa ajoneuvon tiedot: a) linjan numero, b) tarkka määränpää (esim. "Ilmala" tai "Länsisatama")
  /// linjan kaksisuuntaisen yleisnimen ("Ilmala - Länsisatama") sijaan, sekä c) kiinnittää ("snappaa")
  /// ajoneuvon sijainnin tarkasti tien/radan reittiviivalle, jottei se piirry korttelin talojen päälle.
  Vehicle _enrichVehicle(Vehicle v) {
    final cachedLine = _lineCache[v.routeGtfsId];
    final info = cachedLine ?? _routeInfoByGtfsId[v.routeGtfsId];
    final resolvedHead = info != null
        ? info.destinationFor(v.direction, fallbackHeadsign: v.headsign)
        : resolveDestinationHeadsign(headsign: v.headsign, directionId: v.direction);
    final rawRouteCode = v.routeGtfsId.replaceFirst('HSL:', '');
    final resolvedLine =
        (v.line.isEmpty || v.line == rawRouteCode) && info != null && info.shortName.isNotEmpty
            ? info.shortName
            : v.line;

    final geom = s.api.geometryForVehicle(
          tripGtfsId: v.tripGtfsId,
          routeGtfsId: v.routeGtfsId,
          direction: v.direction,
        ) ??
        cachedLine?.patternFor(v.direction, headsign: resolvedHead)?.geometry;

    if (geom == null && cachedLine == null && _lineCache.length < 30) {
      _ensureRouteInfo(v.routeGtfsId);
    }

    var resolvedPos = v.position;
    var resolvedHeading = v.heading;
    if (geom != null && geom.length >= 2) {
      final snapped = snapToPolyline(v.position, geom, maxDistanceMeters: 60.0);
      if (snapped != null) {
        resolvedPos = snapped.point;
        if (resolvedHeading == 0.0) {
          resolvedHeading = snapped.heading;
        }
      }
    }

    if (resolvedHead == v.headsign &&
        resolvedLine == v.line &&
        resolvedPos == v.position &&
        resolvedHeading == v.heading) {
      return v;
    }
    return v.copyWith(
      line: resolvedLine,
      headsign: resolvedHead,
      position: resolvedPos,
      heading: resolvedHeading,
    );
  }

  Future<void> _ensureRouteInfo(String routeGtfsId) async {
    if (!routeGtfsId.startsWith('HSL:') ||
        _lineCache.containsKey(routeGtfsId) ||
        _fetchingRoutes.contains(routeGtfsId)) {
      return;
    }
    _fetchingRoutes.add(routeGtfsId);
    try {
      final info = await s.api.routeWithPatterns(routeGtfsId);
      if (info != null) {
        _lineCache[routeGtfsId] = info;
        _routeInfoByGtfsId[routeGtfsId] = info;
        if (_active) notifyListeners();
      }
    } catch (_) {
    } finally {
      _fetchingRoutes.remove(routeGtfsId);
    }
  }

  /// Yhdistää HFP MQTT -ajoneuvot ja Digitransitin HTTPS GraphQL -ajoneuvot ilman duplikaatteja.
  List<Vehicle> get _mergedVehicles {
    if (_graphqlVehicles.isEmpty) return _all;
    if (_all.isEmpty) return _graphqlVehicles;
    final merged = List<Vehicle>.from(_all);
    for (final gv in _graphqlVehicles) {
      final duplicate = _all.any((hv) {
        if (hv.id == gv.id) return true;
        if (hv.tripGtfsId != null && hv.tripGtfsId == gv.tripGtfsId) return true;
        final sameLine =
            hv.routeGtfsId == gv.routeGtfsId || isLineMatching(hv.line, gv.line);
        return sameLine &&
            hv.direction == gv.direction &&
            distanceMeters(hv.position, gv.position) < 500;
      });
      if (!duplicate) {
        merged.add(gv);
      }
    }
    return merged;
  }

  List<Vehicle> get vehicles {
    final source = _mergedVehicles;
    final q = lineFilter.trim();
    if (q.isNotEmpty) {
      // 2) Linjahaku: haetaan kaikkialta ja miltä tahansa etäisyydeltä sitä linjaa.
      // Symmetrinen haku: numero (esim. 9 tai 69) ja numero+kirjain (9N, 69N) vastaavat toisiaan.
      return source
          .where((v) {
            if (!modes.contains(v.mode)) return false;
            final isLineMatch = isLineMatching(v.line, q) ||
                _searchedRouteGtfsIds.contains(v.routeGtfsId) ||
                _searchedRouteGtfsIds.contains(v.routeGtfsId.replaceFirst('HSL:', ''));
            return isLineMatch;
          })
          .map(_enrichVehicle)
          .toList();
    }

    if (isAllNearbyLinesActive) {
      // 2) "Kaikkia"-painonappi: näytetään kaikkien 1-kohdan lähipysäkkilinjojen live-seurannassa olevat vuorot.
      final activeNames = nearbyShortNames;
      return source
          .where((v) {
            if (!modes.contains(v.mode)) return false;
            if (_nearbyRouteGtfsIds.isNotEmpty) {
              return _nearbyRouteGtfsIds.contains(v.routeGtfsId) ||
                  activeNames.any((n) => isLineMatching(v.line, n)) ||
                  _nearbyRoutes.any((r) => isLineMatching(v.line, r.shortName));
            }
            return distanceMeters(center, v.position) <= radius;
          })
          .map(_enrichVehicle)
          .toList();
    }

    // 1) Tyhjä tekstikenttä: haetaan 5 km etäisyydeltä.
    // Jos Digitransitin lähilinjalista ei ole vielä latautunut (tai verkkoyhteys Digitransitiin viivästyy),
    // näytetään välittömästi kaikki 5 km säteellä olevat ajoneuvot suoraan HFP geohash-tilauksesta.
    // Kun lähilinjat on saatu, hyväksytään sekä GTFS-tunnus että suora VP.desi-linjanumeron osuma (esim. 69 ja 69N).
    return source
        .where((v) {
          if (!modes.contains(v.mode)) return false;
          if (distanceMeters(center, v.position) > radius) return false;
          if (_nearbyRouteGtfsIds.isNotEmpty) {
            return _nearbyRouteGtfsIds.contains(v.routeGtfsId) ||
                _nearbyRoutes.any((r) => isLineMatching(v.line, r.shortName));
          }
          return true;
        })
        .map(_enrichVehicle)
        .toList();
  }

  int get totalVehicles => _mergedVehicles.length;

  Vehicle? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final v in _mergedVehicles) {
      if (v.id == id) return _enrichVehicle(v);
    }
    return null;
  }

  /// 3) Seuraava pysäkki valitun matkan ennusteista.
  /// Korjaa virheen: ei koskaan palauta reitin alkupään pysäkkiä menneisyydestä,
  /// vaan ensisijaisesti HFP:n seuraavan pysäkin (nextStopId) tai ajoneuvon sijaintia/aikaa vastaavan seuraavan pysäkin.
  TripStopTime? get nextStopTime {
    final v = selected;
    if (v == null || tripTimes.isEmpty) return null;

    // a) Ensisijaisesti HFP-telemetrian ilmoittama seuraava pysäkki
    if (v.nextStopId != null) {
      final cleanId = v.nextStopId!.replaceFirst('HSL:', '').trim();
      for (final t in tripTimes) {
        final tId = t.stop.gtfsId.replaceFirst('HSL:', '').trim();
        if (t.stop.gtfsId == v.nextStopId || tId == cleanId || t.stop.code == cleanId) {
          return t;
        }
      }
    }

    // b) Seuraava tuleva pysäkki reaaliaikaisen saapumisajan perusteella
    final now = DateTime.now().subtract(const Duration(seconds: 40));
    for (final t in tripTimes) {
      if (t.realtime.isAfter(now)) return t;
    }

    // c) Jos kaikki ajat ovat ohitettu, palautetaan lähinnä ajoneuvon tämänhetkistä sijaintia oleva pysäkki
    TripStopTime? closest;
    double minD = double.infinity;
    for (final t in tripTimes) {
      final d = distanceMeters(v.position, t.stop.position);
      if (d < minD) {
        minD = d;
        closest = t;
      }
    }
    return closest ?? tripTimes.last;
  }

  /// Valitun matkan tulevat pysäkit ja niiden ennusteajat (seuraavasta pysäkistä päätepysäkille).
  List<TripStopTime> get upcomingStopTimes {
    if (tripTimes.isEmpty) return const [];
    final next = nextStopTime;
    if (next == null) return tripTimes;
    final idx = tripTimes.indexOf(next);
    return idx >= 0 ? tripTimes.sublist(idx) : tripTimes;
  }

  /// Pysäkkivara seuraavalle pysäkille, jos tripTimes ei ole ladattu (esim. pelkkä reittikuvio ja HFP).
  Stop? get nextStopFallback {
    final v = selected;
    if (v == null) return null;

    final pat = selectedPattern;
    if (pat != null && pat.stops.isNotEmpty) {
      if (v.nextStopId != null) {
        final cleanId = v.nextStopId!.replaceFirst('HSL:', '').trim();
        for (final s in pat.stops) {
          final sId = s.gtfsId.replaceFirst('HSL:', '').trim();
          if (s.gtfsId == v.nextStopId || sId == cleanId || s.code == cleanId) {
            return s;
          }
        }
      }

      // Etsitään lähin pysäkki ajoneuvon sijainnista
      Stop? closest;
      double minD = double.infinity;
      for (final s in pat.stops) {
        final d = distanceMeters(v.position, s.position);
        if (d < minD) {
          minD = d;
          closest = s;
        }
      }
      return closest ?? pat.stops.last;
    }

    return null;
  }

  /// Asettaa Live-kartan aktiiviseksi (kun välilehti on auki) tai keskeyttää taustakyselyt (kun siirrytään muulle sivulle).
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (!active) {
      cancelPendingTimers();
      isAwaitingHfpVehicles = false;
      s.hfp.pause();
    } else {
      _ensurePolling();
      _refreshAreaSubscription(center, radius, forceRoutes: _nearbyRouteGtfsIds.isEmpty);
    }
  }

  /// Elinkaaritietoinen taustakeskeytys (kuten `bussit-flutter`-projektin `useQueryLifecycleAware`):
  /// kun sovellus menee taustalle, pysäytetään polling ja MQTT; kun sovellus palaa etualalle,
  /// haetaan välittömästi tuoreet tiedot.
  void setAppPaused(bool paused) {
    if (_appPaused == paused) return;
    _appPaused = paused;
    if (paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
      s.hfp.pause();
    } else if (_active) {
      _ensurePolling();
      unawaited(_pollGraphqlVehicles());
      _refreshAreaSubscription(center, radius, forceRoutes: _nearbyRouteGtfsIds.isEmpty);
    }
  }

  void _ensurePolling() {
    if (!_active || _appPaused) return;
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_active || _appPaused) return;
      _pollTickCount++;
      // 1) Joka 2. sekunti päivitetään muistissa olevien GraphQL-vuorojen interpoloidut sijainnit
      // sekunnin murto-osan tarkkuudella (0 tavua verkkoliikennettä -> merkit liikkuvat sulavasti!).
      _stepGraphqlPositions();
      // 2) Joka 3. tikki (6 s välein) haetaan tuoreet reaaliaikaiset viiveet ja sijainnit Digitransitista.
      if (_pollTickCount % 3 == 0) {
        unawaited(_pollGraphqlVehicles());
      }
    });
  }

  void _stepGraphqlPositions() {
    if (_graphqlVehicles.isEmpty) return;
    final q = lineFilter.trim();
    final filter = q.isNotEmpty
        ? _searchedRouteGtfsIds
        : (_nearbyRouteGtfsIds.isNotEmpty ? _nearbyRouteGtfsIds : null);
    final reinterpolated = s.api.reinterpolateGraphqlVehicles(routeFilter: filter);
    if (reinterpolated.isEmpty) return;

    final byId = {for (final v in reinterpolated) v.id: v};
    var changed = false;
    final updated = <Vehicle>[];
    for (final old in _graphqlVehicles) {
      final fresh = byId.remove(old.id);
      if (fresh != null) {
        if (distanceMeters(old.position, fresh.position) > 0.5) {
          changed = true;
        }
        updated.add(fresh);
      } else {
        updated.add(old);
      }
    }
    if (byId.isNotEmpty) {
      updated.addAll(byId.values);
      changed = true;
    }
    if (changed) {
      _graphqlVehicles = updated;
      if (_active) notifyListeners();
    }
  }

  Future<void> _pollGraphqlVehicles() async {
    if (!_active || _appPaused || _pollingInFlight) return;
    _pollingInFlight = true;
    try {
      final q = lineFilter.trim();
      if (q.isNotEmpty) {
        if (_searchedRouteGtfsIds.isEmpty) return;
        final v = await s.api.vehiclesForRoutes(_searchedRouteGtfsIds);
        final fallback = s.api.reinterpolateGraphqlVehicles(routeFilter: _searchedRouteGtfsIds);
        final next = v.isNotEmpty
            ? v
            : (fallback.isNotEmpty
                ? fallback
                : _graphqlVehicles.where((old) => !old.isStale()).toList());
        if (next.isNotEmpty || _graphqlVehicles.isNotEmpty) {
          _graphqlVehicles = next;
          if (isAwaitingHfpVehicles && vehicles.isNotEmpty) {
            _awaitingVehiclesTimer?.cancel();
            isAwaitingHfpVehicles = false;
          }
          if (_active) notifyListeners();
        }
      } else {
        final now = DateTime.now();
        if (_lastRoutesNearFetch == null ||
            now.difference(_lastRoutesNearFetch!).inSeconds >= 30) {
          _lastRoutesNearFetch = now;
          final routes = await s.api.routesNear(center, radius: 5000, maxStops: 120);
          if (routes.isNotEmpty) {
            _nearbyRoutes = routes;
            _nearbyRouteGtfsIds = routes.map((e) => e.gtfsId).toSet();
          }
        }
        final routeIds = _nearbyRoutes.take(16).map((e) => e.gtfsId).toList();
        if (routeIds.isEmpty) {
          if (s.api.lastNearbyVehicles.isNotEmpty) {
            _graphqlVehicles = s.api.lastNearbyVehicles;
            if (_active) notifyListeners();
          }
          return;
        }
        final v = await s.api.vehiclesForRoutes(routeIds);
        final fallback = s.api.reinterpolateGraphqlVehicles();
        if (v.isNotEmpty || fallback.isNotEmpty || s.api.lastNearbyVehicles.isNotEmpty) {
          _graphqlVehicles = v.isNotEmpty
              ? v
              : (fallback.isNotEmpty ? fallback : s.api.lastNearbyVehicles);
          if (_active) notifyListeners();
        }
      }
    } catch (_) {
    } finally {
      _pollingInFlight = false;
    }
  }

  void setArea(LatLng c, double r, {bool force = false}) {
    final safeCenter = isInGreaterHelsinki(c) ? c : const LatLng(60.1699, 24.9384);
    final moved = distanceMeters(center, safeCenter);
    center = safeCenter;
    radius = r;
    if (!_active && !force) return;
    if (!force && moved < 250) return;
    _debounce?.cancel();
    if (force) {
      _refreshAreaSubscription(safeCenter, r, forceRoutes: _nearbyRouteGtfsIds.isEmpty);
    } else {
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (_active) _refreshAreaSubscription(safeCenter, r);
      });
    }
  }

  Future<void> start() {
    _active = true;
    _ensurePolling();
    return _refreshAreaSubscription(center, radius, forceRoutes: true);
  }

  Future<void> _refreshAreaSubscription(LatLng c, double r, {bool forceRoutes = false}) async {
    _ensurePolling();
    final q = lineFilter.trim();
    if (q.isNotEmpty) {
      await search(q);
      return;
    }

    // 1) Käynnistetään heti HFP-tilaus nykyisillä reiteillä ja 5 km alueella (sis. suora geohash-tilaus)
    s.hfp.lineQuery = '';
    await s.hfp.setArea(
      c,
      5000,
      routeIds: _nearbyRoutes.map((e) => e.gtfsId),
      routeOnly: false,
    );

    // Haetaan 5 km säteellä olevien pysäkkien kautta dynaamisesti kulkevat linjat
    if (forceRoutes ||
        _nearbyRoutesCenter == null ||
        distanceMeters(_nearbyRoutesCenter!, c) >= 400 ||
        _nearbyRouteGtfsIds.isEmpty) {
      _nearbyRoutesCenter = c;
      _lastRoutesNearFetch = DateTime.now();
      try {
        final routes = await s.api.routesNear(c, radius: 5000, maxStops: 120);
        if (s.api.lastNearbyVehicles.isNotEmpty && lineFilter.trim().isEmpty) {
          _graphqlVehicles = s.api.lastNearbyVehicles;
          if (_active) notifyListeners();
        }
        if (routes.isNotEmpty) {
          _nearbyRoutes = routes;
          _nearbyRouteGtfsIds = routes.map((e) => e.gtfsId).toSet();
          for (final route in routes) {
            _routeInfoByGtfsId[route.gtfsId] = route;
          }
          if (_active && lineFilter.trim().isEmpty) {
            await s.hfp.setArea(
              c,
              5000,
              routeIds: routes.map((e) => e.gtfsId),
              routeOnly: false,
            );
            notifyListeners();
            unawaited(_pollGraphqlVehicles());
          }
        }
      } catch (_) {
        // Jos verkko tai kysely epäonnistuu, geohash-ruututilaus toimii varalla
      }
    }
  }

  void toggleMode(TransitMode m) {
    modes.contains(m) ? modes.remove(m) : modes.add(m);
    notifyListeners();
  }

  void setLineFilter(String v) {
    lineFilter = v;
    if (v.trim().isNotEmpty) {
      isAllNearbyLinesActive = false;
    }
    notifyListeners();
    if (!_active) return;
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_active) search(lineFilter);
    });
  }

  /// Aikaleima / id haun vanhentumisen ja keskeyttämisen hallintaan
  int _searchRequestId = 0;

  /// Keskeyttää nykyisen haun (Kaikkia tai linjakyselyn) ja nollaa tilan.
  void cancelSearch() {
    _searchRequestId++;
    isAllNearbyLinesActive = false;
    isSearchingRoutes = false;
    isAwaitingHfpVehicles = false;
    lineFilter = '';
    s.hfp.lineQuery = '';
    _debounce?.cancel();
    _filterDebounce?.cancel();
    _awaitingVehiclesTimer?.cancel();
    _searchedRouteGtfsIds = const {};
    notifyListeners();
  }

  /// 2) "Kaikkia"-painonappi: hakee 1-kohdan kaikkien lähipysäkkilinjojen live-seurannassa olevat vuorot.
  Future<void> searchAllNearbyLines() async {
    _active = true;
    lineFilter = '';
    isAllNearbyLinesActive = true;
    isSearchingRoutes = true;
    final myReqId = ++_searchRequestId;
    _debounce?.cancel();
    _filterDebounce?.cancel();
    _awaitingVehiclesTimer?.cancel();
    notifyListeners();

    try {
      await _refreshAreaSubscription(center, 5000, forceRoutes: true);
      if (myReqId != _searchRequestId) return;
      final routeIds = _nearbyRoutes.map((e) => e.gtfsId).toSet();
      _searchedRouteGtfsIds = routeIds;
      if (routeIds.isNotEmpty) {
        await s.hfp.setRoutes(
          routeIds,
          routeOnly: false,
          center: center,
          radiusMeters: 5000,
        );
        if (myReqId != _searchRequestId) return;
        try {
          final gqlVehicles = await s.api.vehiclesForRoutes(routeIds);
          if (myReqId != _searchRequestId) return;
          if (gqlVehicles.isNotEmpty) {
            _graphqlVehicles = gqlVehicles;
          } else if (s.api.lastNearbyVehicles.isNotEmpty) {
            _graphqlVehicles = s.api.lastNearbyVehicles;
          }
        } catch (_) {}
      }
    } finally {
      if (myReqId == _searchRequestId) {
        isSearchingRoutes = false;
        isAwaitingHfpVehicles = false;
        _ensurePolling();
        if (_active) notifyListeners();
      }
    }
  }

  /// Käynnistää linja- tai 5 km lähilinjojen haun välittömästi.
  Future<void> search([String? query]) async {
    _active = true;
    if (query != null) {
      lineFilter = query.trim();
    }
    _debounce?.cancel();
    _filterDebounce?.cancel();
    _awaitingVehiclesTimer?.cancel();
    final myReqId = ++_searchRequestId;

    final q = lineFilter.trim();
    if (q.isEmpty) {
      // 1) Jos käyttäjä jättää tekstikentän tyhjäksi, hae 5 km etäisyydeltä ja niitä linjoja,
      // joita tulee lähipysäkeille live hakujen tekemiseen.
      isSearchingRoutes = false;
      isAwaitingHfpVehicles = false;
      _searchedRouteGtfsIds = const {};
      notifyListeners();
      await _refreshAreaSubscription(center, 5000, forceRoutes: _nearbyRouteGtfsIds.isEmpty);
      return;
    }

    isAllNearbyLinesActive = false;

    // Tallennetaan viimeisimpiin hakuihin (max 6 uniikkia)
    final normalizedQuery = splitSearchTokens(q).map((e) => e.toUpperCase()).join(', ');
    if (normalizedQuery.isNotEmpty) {
      recentSearches.remove(normalizedQuery);
      recentSearches.insert(0, normalizedQuery);
      if (recentSearches.length > 6) {
        recentSearches.removeRange(6, recentSearches.length);
      }
    }

    isSearchingRoutes = true;
    notifyListeners();

    // 2) Jos käyttäjä antaa tietyn linjan (tai useita linjoja, esim. "9, 69" tai "K") live hakuun,
    // hae kaikkialta ja miltä tahansa etäisyydeltä niitä linjoja.
    final tokens = splitSearchTokens(q);
    final matchedIds = <String>{};
    final queriesToSearch = <String>{};

    // Priorisoidaan ensimmäiseksi lähimpien pysäkkien oikeat GTFS-reittitunnukset
    // (esim. Käpylän asemalla K-junan HSL:3001K, I-junan HSL:3001I, bussin 69 HSL:1069)
    for (final r in _nearbyRoutes) {
      if (isLineMatching(r.shortName, q)) {
        matchedIds.add(r.gtfsId);
      }
    }

    for (final token in tokens) {
      final tUpper = token.toUpperCase();
      final tDigits = token.replaceAll(RegExp(r'[^0-9]'), '');
      queriesToSearch.add(tUpper);
      if (tDigits.isNotEmpty) {
        queriesToSearch.add(tDigits);
        queriesToSearch.add('${tDigits}N');
      }

      // Lisätään HSL:n standardit GTFS-reittitunnukset suoraan jokaiselle hakusanalle
      // (esim. lähijuna K -> 3001K / 3002K, metro M1 -> 31M1, ratikka 9 -> 1009, bussi 69 -> 1069)
      if (tDigits.isNotEmpty) {
        if (tUpper == 'M1' || tUpper == 'M2') {
          matchedIds.add('HSL:31$tUpper');
        }
        if (tDigits.length == 1) {
          matchedIds.add('HSL:100$tDigits');
          matchedIds.add('HSL:100${tDigits}N');
          matchedIds.add('HSL:10$tDigits');
          matchedIds.add('HSL:10${tDigits}N');
          matchedIds.add('HSL:200$tDigits');
          matchedIds.add('HSL:400$tDigits');
        } else if (tDigits.length == 2) {
          matchedIds.add('HSL:10$tDigits');
          matchedIds.add('HSL:10${tDigits}N');
          matchedIds.add('HSL:20$tDigits');
          matchedIds.add('HSL:20${tDigits}N');
          matchedIds.add('HSL:40$tDigits');
          matchedIds.add('HSL:40${tDigits}N');
          matchedIds.add('HSL:1$tDigits');
          matchedIds.add('HSL:2$tDigits');
        } else {
          matchedIds.add('HSL:1$tDigits');
          matchedIds.add('HSL:1${tDigits}N');
          matchedIds.add('HSL:2$tDigits');
          matchedIds.add('HSL:2${tDigits}N');
          matchedIds.add('HSL:4$tDigits');
          matchedIds.add('HSL:4${tDigits}N');
        }
        matchedIds.add('HSL:$tUpper');
        matchedIds.add('HSL:$tDigits');
        matchedIds.add('HSL:${tDigits}N');
      } else {
        // Kirjainlinjat: HSL:n lähijunat (3001K, 3001I, 3001P, 3001N, 3001T, 3001R, 3002A, 3002E, 3002U, 3002L...)
        // sekä metro (M -> 31M1, 31M2)
        matchedIds.add('HSL:3001$tUpper');
        matchedIds.add('HSL:3002$tUpper');
        if (tUpper == 'M') {
          matchedIds.add('HSL:31M1');
          matchedIds.add('HSL:31M2');
        }
        matchedIds.add('HSL:$tUpper');
      }
    }

    _searchedRouteGtfsIds = Set.of(matchedIds);
    s.hfp.lineQuery = q;
    if (matchedIds.isNotEmpty) {
      unawaited(s.hfp.setRoutes(
        matchedIds,
        routeOnly: true,
        center: center,
      ));
    }

    for (final searchQ in queriesToSearch) {
      if (myReqId != _searchRequestId) return;
      try {
        List<LineInfo> found;
        final cached = _lineSearchCache[searchQ];
        if (cached != null && cached.isNotEmpty) {
          found = cached;
        } else {
          found = await s.api.searchLines(searchQ);
          if (found.isNotEmpty) {
            _lineSearchCache[searchQ] = found;
          }
        }
        for (final r in found) {
          _routeInfoByGtfsId[r.gtfsId] = r;
          if (isLineMatching(r.shortName, q)) {
            matchedIds.add(r.gtfsId);
          }
        }
      } catch (_) {}
    }

    if (myReqId != _searchRequestId) return;
    _searchedRouteGtfsIds = matchedIds;
    isSearchingRoutes = false;
    s.hfp.lineQuery = q;

    if (matchedIds.isNotEmpty) {
      // Haetaan kaikkialta ja miltä tahansa etäisyydeltä, sekä pidetään lähialueen geohash-ruudut rinnalla
      await s.hfp.setRoutes(
        matchedIds,
        routeOnly: true,
        center: center,
      );
      if (myReqId != _searchRequestId) return;
      // Haetaan samalla suoraan Digitransitin HTTPS GraphQL -rajapinnasta ajossa olevat vuorot
      // (bussit-flutter-tyylinen HTTPS-varmistus, jotta vuorot löytyvät vaikka MQTT ei toimisi)
      try {
        final gqlVehicles = await s.api.vehiclesForRoutes(matchedIds);
        if (myReqId != _searchRequestId) return;
        if (gqlVehicles.isNotEmpty) {
          _graphqlVehicles = gqlVehicles;
        }
      } catch (_) {}
    } else {
      await s.hfp.setArea(center, 5000, routeIds: _nearbyRouteGtfsIds, routeOnly: false);
    }

    if (myReqId != _searchRequestId) return;
    _ensurePolling();

    // Jos ajoneuvoja ei ole vielä muistissa, odotetaan varoaika (max 4 s) ensimmäistä
    // MQTT-sijaintipakettia ennen kuin näytetään "Ei ajossa olevia vuoroja" -ilmoitus.
    if (vehicles.isEmpty) {
      isAwaitingHfpVehicles = true;
      _awaitingVehiclesTimer?.cancel();
      _awaitingVehiclesTimer = Timer(const Duration(seconds: 4), () {
        isAwaitingHfpVehicles = false;
        if (_active) notifyListeners();
      });
    } else {
      isAwaitingHfpVehicles = false;
    }
    notifyListeners();
  }

  Future<void> select(Vehicle v) async {
    selectedId = v.id;
    selectedPattern = null;
    selectedLine = null;
    selectedStop = null;
    selectedTripStopTime = null;
    tripTimes = const [];
    loadingSelection = true;
    isVehicleCardVisible = true;
    notifyListeners();
    try {
      var line = _lineCache[v.routeGtfsId];
      line ??= await s.api.routeWithPatterns(v.routeGtfsId);
      if (line != null) _lineCache[v.routeGtfsId] = line;
      if (selectedId != v.id) return;
      selectedLine = line;

      // 3) Selvitetään oikea suunta (directionId) linjan reittikuvioiden ja ajoneuvon määränpään perusteella,
      // jotta paluuvuoron pysäkkejä ei vahingossa listata vastakkaiseen suuntaan ajettaessa.
      int effectiveDirection = v.direction;
      if (line != null && v.headsign.isNotEmpty) {
        final matchingPattern = line.patterns.where((p) {
          final h = p.headsign.toLowerCase();
          final vh = v.headsign.toLowerCase();
          return h.contains(vh) || vh.contains(h);
        }).firstOrNull;
        if (matchingPattern != null) {
          effectiveDirection = matchingPattern.directionId;
        }
      }

      selectedPattern = line?.patternFor(effectiveDirection, headsign: v.headsign);
      notifyListeners();
      if (v.tripGtfsId != null && v.tripGtfsId!.isNotEmpty) {
        final t = await s.api.tripStopTimesById(v.tripGtfsId!);
        if (selectedId == v.id && t.isNotEmpty) {
          tripTimes = t;
        }
      }
      if (tripTimes.isEmpty && v.operatingDay != null && v.startTime != null) {
        final t = await s.api.tripStopTimes(
          routeGtfsId: v.routeGtfsId,
          direction: effectiveDirection,
          date: v.operatingDay!,
          startTime: v.startTime!,
        );
        if (selectedId == v.id) tripTimes = t;
      }
    } catch (_) {/* näytetään ainakin ajoneuvon perustiedot */}
    if (selectedId == v.id) {
      loadingSelection = false;
      notifyListeners();
    }
  }

  void clearSelection() {
    selectedId = null;
    selectedLine = null;
    selectedPattern = null;
    selectedStop = null;
    selectedTripStopTime = null;
    tripTimes = const [];
    follow = false;
    isVehicleCardVisible = false;
    notifyListeners();
  }

  /// 2) Kun live-vuoron listaa x-ruksista laitetaan kiinni, suljetaan vain lista/kortti,
  /// mutta jätetään mahdollinen linjakartta (reittiviiva ja pysäkit) näkyviin.
  void closeVehicleCard() {
    isVehicleCardVisible = false;
    follow = false;
    notifyListeners();
  }

  /// Avaa vuoron listan/kortin uudelleen, jos linja on valittuna.
  void showVehicleCard() {
    isVehicleCardVisible = true;
    notifyListeners();
  }

  /// Valitsee tai poistaa pysäkin valinnan vuoron reitiltä kartalla ja pysäkkiluettelossa.
  void selectStop(Stop? stop, [TripStopTime? tripStopTime]) {
    if (selectedStop?.gtfsId == stop?.gtfsId) {
      selectedStop = null;
      selectedTripStopTime = null;
    } else {
      selectedStop = stop;
      selectedTripStopTime = tripStopTime ??
          (stop != null
              ? tripTimes.where((t) => t.stop.gtfsId == stop.gtfsId).firstOrNull
              : null);
      // Kun käyttäjä valitsee pysäkin tarkastelua varten, keskeytetään vuoron lukitusseuranta,
      // jotta kartta pysyy valitun pysäkin kohdalla
      follow = false;
    }
    notifyListeners();
  }

  void clearSelectedStop() {
    if (selectedStop != null || selectedTripStopTime != null) {
      selectedStop = null;
      selectedTripStopTime = null;
      notifyListeners();
    }
  }

  void toggleFollow() {
    follow = !follow;
    notifyListeners();
  }

  /// Näytä linjan reitti valitsematta ajoneuvoa (esim. haku/suosikki).
  Future<void> showLine(LineInfo l) async {
    selectedId = null;
    selectedStop = null;
    selectedTripStopTime = null;
    follow = false;
    loadingSelection = true;
    notifyListeners();
    try {
      final full = await s.api.routeWithPatterns(l.gtfsId);
      selectedLine = full;
      selectedPattern = full?.patterns.isEmpty ?? true
          ? null
          : (full!.patterns.toList()..sort((a, b) => b.stops.length.compareTo(a.stops.length))).first;
    } catch (_) {}
    loadingSelection = false;
    notifyListeners();
  }

  void cancelPendingTimers() {
    _debounce?.cancel();
    _filterDebounce?.cancel();
    _awaitingVehiclesTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    cancelPendingTimers();
    _sub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
