import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/place_stop.dart';

/// Suosikkipysäkit, -linjat ja -paikat sekä asetukset SharedPreferencesissä.
class FavoritesRepository {
  static const _stopsKey = 'fav_stops';
  static const _linesKey = 'fav_lines';
  static const _placesKey = 'fav_places';
  static const _alarmsKey = 'trip_alarms';

  final SharedPreferences _p;
  FavoritesRepository(this._p);

  List<Stop> loadStops() => _decode(_stopsKey).map(Stop.fromJson).toList();
  Future<void> saveStops(List<Stop> s) =>
      _p.setString(_stopsKey, jsonEncode(s.map((e) => e.toJson()).toList()));

  /// Suosikkilinja: {gtfsId, shortName, mode}
  List<Map<String, dynamic>> loadLines() => _decode(_linesKey);
  Future<void> saveLines(List<Map<String, dynamic>> l) =>
      _p.setString(_linesKey, jsonEncode(l));

  List<GeoPlace> loadPlaces() =>
      _decode(_placesKey).map(GeoPlace.fromJson).toList();
  Future<void> savePlaces(List<GeoPlace> l) =>
      _p.setString(_placesKey, jsonEncode(l.map((e) => e.toJson()).toList()));

  List<Map<String, dynamic>> loadAlarms() => _decode(_alarmsKey);
  Future<void> saveAlarms(List<Map<String, dynamic>> a) =>
      _p.setString(_alarmsKey, jsonEncode(a));

  List<Map<String, dynamic>> _decode(String key) {
    final raw = _p.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Asetukset
  String get tileSource => _p.getString('tile_source') ?? 'digitransit';
  Future<void> setTileSource(String v) => _p.setString('tile_source', v);
  String get themeMode => _p.getString('theme_mode') ?? 'dark';
  Future<void> setThemeMode(String v) => _p.setString('theme_mode', v);
  int get nearbyRadius => _p.getInt('nearby_radius') ?? 1000;
  Future<void> setNearbyRadius(int v) => _p.setInt('nearby_radius', v);
  bool get notifications => _p.getBool('notifications') ?? false;
  Future<void> setNotifications(bool v) => _p.setBool('notifications', v);
}
