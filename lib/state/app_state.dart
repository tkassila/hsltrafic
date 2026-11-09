import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../data/digitransit_client.dart';
import '../data/favorites_repository.dart';
import '../data/hfp_service.dart';
import '../data/location_service.dart';
import '../models/line.dart';
import '../models/place_stop.dart';

/// Yhteiset palvelut, jotka injektoidaan kaikille kontrollereille.
class Services {
  final DigitransitClient api;
  final HfpService hfp;
  final LocationService location;
  final FavoritesRepository repo;
  Services({required this.api, required this.hfp, required this.location, required this.repo});
}

enum TileSource {
  digitransit('Digitransit (HSL)', 'digitransit'),
  osm('OpenStreetMap', 'osm'),
  carto('CARTO tumma', 'carto');

  final String label;
  final String id;
  const TileSource(this.label, this.id);
  static TileSource byId(String id) =>
      TileSource.values.firstWhere((t) => t.id == id, orElse: () => TileSource.digitransit);
}

class SettingsController extends ChangeNotifier {
  final Services s;
  late TileSource tile = TileSource.byId(s.repo.tileSource);
  ThemeMode themeMode = ThemeMode.dark;
  late int nearbyRadius = s.repo.nearbyRadius;

  SettingsController(this.s);

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

  LatLng get positionOrDefault =>
      (position != null && isInGreaterHelsinki(position!)) ? position! : helsinki;

  Future<void> locate() {
    return _locating ??= _doLocate().whenComplete(() => _locating = null);
  }

  Future<void> _doLocate() async {
    try {
      state = await s.location.ensurePermission();
      if (state == LocationState.ready) {
        final pos = await s.location.current();
        if (pos != null && isInGreaterHelsinki(pos)) {
          position = pos;
        }
      }
    } catch (_) {
      state = LocationState.serviceOff;
    }
    notifyListeners();
  }
}
