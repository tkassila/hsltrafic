import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/digitransit_client.dart';
import '../data/favorites_repository.dart';
import '../data/hfp_service.dart';
import '../data/location_service.dart';
import '../models/line.dart';
import '../models/place_stop.dart';
import '../models/transit_region.dart';

/// Yhteiset palvelut, jotka injektoidaan kaikille kontrollereille.
class Services {
  final DigitransitClient api;
  final HfpService hfp;
  final LocationService location;
  final FavoritesRepository repo;
  SettingsController? _settings;
  SettingsController get settings => _settings ??= SettingsController(this);
  set settings(SettingsController s) => _settings = s;

  Services({required this.api, required this.hfp, required this.location, required this.repo});
}

enum TileSource {
  osm('OpenStreetMap', 'osm'),
  digitransit('Digitransit (HSL)', 'digitransit'),
  carto('CARTO tumma', 'carto');

  final String label;
  final String id;
  const TileSource(this.label, this.id);
  static TileSource byId(String id) =>
      TileSource.values.firstWhere((t) => t.id == id, orElse: () => TileSource.osm);
}

class SettingsController extends ChangeNotifier {
  final Services s;
  late TileSource tile = TileSource.byId(s.repo.tileSource);
  ThemeMode themeMode = ThemeMode.dark;
  late int nearbyRadius = s.repo.nearbyRadius;
  late TransitRegion region = TransitRegion.byId(s.repo.transitRegion);

  SettingsController(this.s) {
    s.settings = this;
    s.api.setEndpointProvider(() => activeGraphqlUrl);
    s.api.setFocusProvider(() => activeFocusPoint);
    s.api.setPlanEndpointResolver((from, to) => region.resolvePlanGraphqlUrl(from: from, to: to));
  }

  /// Aktiivinen GraphQL-osoite huomioiden laitteen sijainti (jos region == auto)
  String get activeGraphqlUrl {
    final pos = s.location.position;
    return region.resolveGraphqlUrl(pos);
  }

  /// Aktiivinen geokoodauksen ja osoitehaun kohdistuspiste (focus point)
  LatLng? get activeFocusPoint {
    if (region != TransitRegion.auto && region.center != null) {
      return region.center;
    }
    return s.location.position ?? region.center;
  }

  void setRegion(TransitRegion r) {
    region = r;
    s.repo.setTransitRegion(r.id);
    notifyListeners();
  }

  void setTile(TileSource t) {
    tile = t;
    s.repo.setTileSource(t.id);
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    s.repo.setThemeMode(m == ThemeMode.light ? 'light' : (m == ThemeMode.system ? 'system' : 'dark'));
    notifyListeners();
  }

  void setNearbyRadius(int r) {
    nearbyRadius = r;
    s.repo.setNearbyRadius(r);
    notifyListeners();
  }
}

class FavoritesController extends ChangeNotifier {
  final Services s;
  late List<Stop> stops = s.repo.loadStops();
  late List<Map<String, dynamic>> lines = s.repo.loadLines();
  late List<GeoPlace> places = s.repo.loadPlaces();

  FavoritesController(this.s);

  bool isFavStop(String id) => stops.any((e) => e.gtfsId == id);
  bool isFavLine(String id) => lines.any((e) => e['gtfsId'] == id);

  void toggleStop(Stop st) {
    if (isFavStop(st.gtfsId)) {
      stops = stops.where((e) => e.gtfsId != st.gtfsId).toList();
    } else {
      stops = [...stops, st];
    }
    s.repo.saveStops(stops);
    notifyListeners();
  }

  void toggleLine(LineInfo l) {
    if (isFavLine(l.gtfsId)) {
      lines = lines.where((e) => e['gtfsId'] != l.gtfsId).toList();
    } else {
      lines = [
        ...lines,
        {'gtfsId': l.gtfsId, 'shortName': l.shortName, 'mode': l.mode.gtfsName, 'longName': l.longName},
      ];
    }
    s.repo.saveLines(lines);
    notifyListeners();
  }

  bool isFavPlace(GeoPlace p) =>
      places.any((e) => e.label == p.label && e.position == p.position);

  void togglePlace(GeoPlace p) {
    if (isFavPlace(p)) {
      places = places.where((e) => !(e.label == p.label && e.position == p.position)).toList();
    } else {
      places = [...places, p];
    }
    s.repo.savePlaces(places);
    notifyListeners();
  }
}

/// Häiriötiedotteet.
class AlertsController extends ChangeNotifier {
  final Services s;
  List<TransitAlert> alerts = const [];
  bool loading = false;
  String? error;

  AlertsController(this.s);

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      alerts = await s.api.alerts();
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  List<TransitAlert> forLine(String? gtfsId) =>
      gtfsId == null ? const [] : alerts.where((a) => a.routeGtfsId == gtfsId).toList();

  int get severeCount => alerts.where((a) => a.isWarning).length;
}

/// Sijainti, jota kaikki välilehdet käyttävät.
class LocationController extends ChangeNotifier {
  final Services s;

  /// Laitteen todellinen GPS-sijainti. Alussa `null`, kunnes oikea GPS-paikannus on saatu
  /// (ei koskaan alusteta Kampin oletuskoordinaateilla).
  LatLng? position;
  LocationState state = LocationState.unknown;
  Future<void>? _locating;
  static const helsinki = LatLng(60.1699, 24.9384);

  LocationController(this.s);

  /// Onko saatu oikea laitteen GPS-sijainti.
  bool get hasRealGps => position != null;

  LatLng get positionOrDefault => position ?? (s.settings.region.center ?? helsinki);

  Future<void> locate() {
    return _locating ??= _doLocate().whenComplete(() => _locating = null);
  }

  Future<void> _doLocate() async {
    try {
      state = await s.location.ensurePermission();
      if (state == LocationState.ready) {
        final pos = await s.location.current();
        if (pos != null) {
          s.location.lastPosition = pos;
          position = pos;
        }
      }
    } catch (_) {
      state = LocationState.serviceOff;
    }
    notifyListeners();
  }
}
