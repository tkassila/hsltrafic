import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../models/line.dart';
import '../models/place_stop.dart';
import '../models/transit_mode.dart';
import 'app_state.dart';

/// Lähipysäkit osoitteen/sijainnin ympäriltä käyttäjän valitsemalla säteellä (oletus 100 m).
class NearbyController extends ChangeNotifier {
  final Services s;
  final LocationController loc;
  final SettingsController settings;

  GeoPlace? origin; // null = oma sijainti
  List<NearbyStop> results = const [];
  bool loading = false;
  String? error;
  Timer? _debounce;
  int _seq = 0;
  int _stopSelectSeq = 0;
  LatLng? _lastSearchedOrigin;

  // Valitun pysäkin ja linjan tila
  Stop? selectedStop;
  String? selectedLine;
  TransitMode? selectedLineMode;
  String? selectedHeadsign;
  int? selectedDepartureIndex;
  LinePattern? selectedLinePattern;
  bool loadingLineRoute = false;
  List<Departure> lineHourDepartures = const [];
  bool loadingHourDepartures = false;
  String? loadingStopId;

  NearbyController(this.s, this.loc, this.settings) {
    loc.addListener(_onLocationChanged);
  }

  bool isStopLoading(String stopId) => loadingStopId == stopId;

  void _onLocationChanged() {
    if (origin != null) return;
    final pos = loc.positionOrDefault;
    if (_lastSearchedOrigin == null || distanceMeters(_lastSearchedOrigin!, pos) >= 20) {
      search();
    }
  }

  int get searchSeq => _seq;
  int get radius => settings.nearbyRadius;
  String? get selectedStopId => selectedStop?.gtfsId;

  GeoPlace get effectiveOrigin =>
      origin ??
      GeoPlace(label: 'Oma sijainti', position: loc.positionOrDefault, isCurrentLocation: true);

  void setOrigin(GeoPlace? p) {
    origin = p;
    clearSelection();
    search();
  }

  void setRadius(int r, {bool immediate = false}) {
    settings.setNearbyRadius(r);
    notifyListeners();
    _debounce?.cancel();
    if (immediate) {
      search();
    } else {
      _debounce = Timer(const Duration(milliseconds: 500), search);
    }
  }

  /// Valitsee pysäkin kartalle.
  /// Jos [fetchDepartures] on true (kartalta klikattaessa), haetaan pysäkin tuoreet
  /// vuorot ja aikataulut Digitransitista ja siirretään pysäkki listan kärkeen.
  /// Jos [fetchDepartures] on false (pysäkkilistalta klikattaessa), vain aktivoidaan
  /// pysäkki kartalla ilman uutta hakukyselyä.
  Future<void> selectStop(
    Stop? stop, {
    bool toggle = false,
    bool fetchDepartures = true,
  }) async {
    final reqId = ++_stopSelectSeq;

    if (stop == null) {
      selectedStop = null;
      loadingStopId = null;
      clearLineRoute();
      return;
    }

    if (toggle && selectedStop?.gtfsId == stop.gtfsId && selectedLinePattern == null) {
      selectedStop = null;
      loadingStopId = null;
      clearLineRoute();
      return;
    }

    selectedStop = stop;
    selectedLine = null;
    selectedLineMode = null;
    selectedHeadsign = null;
    selectedDepartureIndex = null;
    selectedLinePattern = null;
    lineHourDepartures = const [];
    loadingHourDepartures = false;

    if (!fetchDepartures) {
      loadingStopId = null;
      notifyListeners();
      return;
    }

    // Kartalta klikattaessa siirretään valittu pysäkki heti listan kärkeen,
    // jotta sen vuorot ovat välittömästi näkyvissä kartan alla.
    final existingIdx = results.indexWhere((r) => r.stop.gtfsId == stop.gtfsId);
    if (existingIdx > 0) {
      final currentItem = results[existingIdx];
      final updated = List<NearbyStop>.from(results)..removeAt(existingIdx);
      results = [currentItem, ...updated];
    } else if (existingIdx == -1) {
      results = [NearbyStop(stop, const []), ...results];
    }

    loadingStopId = stop.gtfsId;
    notifyListeners();

    try {
      final deps = await s.api.departures(stop.gtfsId, count: 10);
      if (reqId != _stopSelectSeq) return;

      Stop resolvedStop = stop;
      if (resolvedStop.routes.isEmpty) {
        final curIdx = results.indexWhere((r) => r.stop.gtfsId == stop.gtfsId);
        if (curIdx != -1 && results[curIdx].stop.routes.isNotEmpty) {
          resolvedStop = results[curIdx].stop;
        } else {
          try {
            final detailed = await s.api.stop(stop.gtfsId);
            if (reqId != _stopSelectSeq) return;
            if (detailed != null) {
              resolvedStop = Stop(
                gtfsId: detailed.gtfsId,
                name: detailed.name,
                position: detailed.position,
                code: detailed.code ?? stop.code,
                platformCode: detailed.platformCode ?? stop.platformCode,
                mode: detailed.mode,
                distance: stop.distance ?? detailed.distance,
                routes: detailed.routes,
              );
            }
          } catch (_) {}
        }
      }

      final newEntry = NearbyStop(resolvedStop, deps);
      final targetIdx = results.indexWhere((r) => r.stop.gtfsId == stop.gtfsId);
      if (targetIdx != -1) {
        final updated = List<NearbyStop>.from(results)..removeAt(targetIdx);
        results = [newEntry, ...updated];
      } else {
        results = [newEntry, ...results];
      }
    } catch (_) {
      // Pidetään nykyinen tila virheen sattuessa
    } finally {
      if (reqId == _stopSelectSeq) {
        loadingStopId = null;
        notifyListeners();
      }
    }
  }

  /// Valitsee pysäkin alla olevan linjan ja hakee sen katureitin sekä 2 tunnin vuorot.
  /// Jos sama linja on jo valittu, sulkee sen.
  Future<void> selectLineRoute({
    required Stop stop,
    required String line,
    required TransitMode mode,
    required String headsign,
    String? routeGtfsId,
    int? departureIndex,
  }) async {
    final isSameSelection = selectedStop?.gtfsId == stop.gtfsId &&
        selectedLine == line &&
        selectedHeadsign == headsign &&
        (departureIndex == null || selectedDepartureIndex == departureIndex);
    if (isSameSelection) {
      clearLineRoute();
      return;
    }

    selectedStop = stop;
    selectedLine = line;
    selectedLineMode = mode;
    selectedHeadsign = headsign;
    selectedDepartureIndex = departureIndex;
    selectedLinePattern = null;
    lineHourDepartures = const [];
    loadingLineRoute = true;
    loadingHourDepartures = true;
    notifyListeners();

    // 1. Haetaan linjan katureitti Digitransitista
    try {
      String? targetGtfsId = routeGtfsId;
      if (targetGtfsId == null || targetGtfsId.isEmpty) {
        final found = await s.api.searchLines(line);
        if (found.isNotEmpty) {
          targetGtfsId = found.first.gtfsId;
        }
      }

      if (targetGtfsId != null) {
        final info = await s.api.routeWithPatterns(targetGtfsId);
        if (info != null && info.patterns.isNotEmpty) {
          // Etsitään pattern, joka kulkee tämän pysäkin kautta
          LinePattern? matched;
          for (final pat in info.patterns) {
            if (pat.stops.any((st) => st.gtfsId == stop.gtfsId)) {
              matched = pat;
              break;
            }
          }
          // Jos ei löytynyt suoraan pysäkin kautta, kokeillaan headsignilla
          if (matched == null && headsign.isNotEmpty) {
            for (final pat in info.patterns) {
              if (pat.headsign.toLowerCase() == headsign.toLowerCase()) {
                matched = pat;
                break;
              }
            }
          }
          selectedLinePattern = matched ?? info.patterns.first;
        }
      }
    } catch (_) {
      selectedLinePattern = null;
    } finally {
      loadingLineRoute = false;
      notifyListeners();
    }

    // 2. Haetaan kyseisen linjan seuraavat vuorot seuraavan 2 tunnin ajalta
    try {
      final hourDeps = await s.api.departuresForStopAndLine(stop.gtfsId, line, timeRangeSeconds: 7200);
      lineHourDepartures = hourDeps;
    } catch (_) {
      lineHourDepartures = const [];
    } finally {
      loadingHourDepartures = false;
      notifyListeners();
    }
  }

  void clearLineRoute() {
    selectedLine = null;
    selectedLineMode = null;
    selectedHeadsign = null;
    selectedDepartureIndex = null;
    selectedLinePattern = null;
    lineHourDepartures = const [];
    loadingHourDepartures = false;
    notifyListeners();
  }

  void clearSelection() {
    selectedStop = null;
    selectedLine = null;
    selectedLineMode = null;
    selectedHeadsign = null;
    selectedDepartureIndex = null;
    selectedLinePattern = null;
    lineHourDepartures = const [];
    loadingHourDepartures = false;
    notifyListeners();
  }

  Future<void> search() async {
    final id = ++_seq;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final o = effectiveOrigin;
      _lastSearchedOrigin = o.position;
      final stops = await s.api.stopsByRadius(o.position, radius);
      if (id != _seq) return;

      // Listataan kaikki asetetun säteen sisällä olevat pysäkit heti,
      // silloinkin kun vuoroja ei ole kyseisenä ajankohtana tai lähtökysely epäonnistuu.
      results = [for (final st in stops) NearbyStop(st, const [])];

      if (stops.isNotEmpty) {
        try {
          final deps = await s.api.departuresForStops(
            stops.take(30).map((e) => e.gtfsId).toList(),
            count: 5,
          );
          if (id != _seq) return;
          results = [for (final st in stops) NearbyStop(st, deps[st.gtfsId] ?? const [])];
        } catch (_) {
          // Pidetään pysäkit listalla vaikka lähtöjen haku epäonnistuisi
        }
      }

      // Jos aiemmin valittu pysäkki ei ole enää listalla, nollataan se
      if (selectedStop != null && !stops.any((s) => s.gtfsId == selectedStop!.gtfsId)) {
        clearSelection();
      }
    } catch (e) {
      if (id != _seq) return;
      error = e.toString();
      results = const [];
    }
    if (id == _seq) {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    loc.removeListener(_onLocationChanged);
    _debounce?.cancel();
    super.dispose();
  }
}
