import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/location_service.dart';
import '../models/journey.dart';
import '../models/place_stop.dart';
import '../models/transit_mode.dart';
import 'app_state.dart';

/// Reittioppaan tila: lähtö, määränpää, välipisteet, aika, kulkumuodot ja tulokset.
class PlannerController extends ChangeNotifier {
  final Services s;
  final LocationController loc;

  GeoPlace? from;
  GeoPlace? to;
  final List<GeoPlace> via = [];
  DateTime? time; // null = nyt
  bool arriveBy = false;
  final Set<TransitMode> modes = {};

  List<Itinerary> results = const [];
  int selectedIndex = 0;
  bool loading = false;
  String? error;
  bool searched = false;

  PlannerController(this.s, this.loc) {
    from = currentLocationPlace;
  }

  Itinerary? get selected => results.isEmpty ? null : results[selectedIndex.clamp(0, results.length - 1)];

  GeoPlace get currentLocationPlace => GeoPlace(
        label: 'Oma sijainti',
        position: loc.positionOrDefault,
        isCurrentLocation: true,
      );

  /// Jos lähtöpaikkaa ei ole annettu (tai se on oma sijainti), käytetään oletuksena omaa sijaintia.
  GeoPlace get effectiveFrom =>
      (from == null || from!.isCurrentLocation) ? currentLocationPlace : from!;

  void setFrom(GeoPlace? p) {
    from = p ?? currentLocationPlace;
    notifyListeners();
  }

  void setTo(GeoPlace? p) {
    to = p;
    notifyListeners();
  }

  void addVia(GeoPlace p) {
    via.add(p);
    notifyListeners();
  }

  void removeVia(int i) {
    via.removeAt(i);
    notifyListeners();
  }

  void swap() {
    final f = effectiveFrom;
    from = to ?? currentLocationPlace;
    to = f;
    notifyListeners();
  }

  void setTime(DateTime? t, {bool? arrive}) {
    time = t;
    if (arrive != null) arriveBy = arrive;
    notifyListeners();
  }

  void toggleMode(TransitMode m) {
    modes.contains(m) ? modes.remove(m) : modes.add(m);
    notifyListeners();
  }

  void select(int i) {
    selectedIndex = i;
    notifyListeners();
  }

  Future<void> search() async {
    from ??= currentLocationPlace;
    final usesCurrentLocation =
        from!.isCurrentLocation || (to?.isCurrentLocation == true);
    if (usesCurrentLocation && loc.position == null && loc.state == LocationState.unknown) {
      await loc.locate();
    }
    final f = effectiveFrom;
    final t = to?.isCurrentLocation == true ? currentLocationPlace : to;
    if (t == null) {
      error = 'Valitse määränpää.';
      notifyListeners();
      return;
    }
    from = f;
    loading = true;
    error = null;
    searched = true;
    notifyListeners();
    try {
      results = await s.api.plan(
        from: f.position,
        to: t.position,
        via: via.map((e) => e.position).toList(),
        time: time,
        arriveBy: arriveBy,
        modes: modes,
      );
      selectedIndex = 0;
    } catch (e) {
      error = e.toString();
      results = const [];
    }
    loading = false;
    notifyListeners();
  }

  /// Aseta määränpää ja hae heti (esim. pysäkiltä "Reitti tänne").
  Future<void> routeTo(GeoPlace dest) async {
    to = dest;
    from ??= currentLocationPlace;
    await search();
  }

  Future<List<GeoPlace>> suggest(String text) =>
      s.api.autocomplete(text, focus: loc.position);

  Future<GeoPlace?> reverse(LatLng p) async {
    try {
      return await s.api.reverse(p) ??
          GeoPlace(label: '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}', position: p);
    } catch (_) {
      return GeoPlace(label: '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}', position: p);
    }
  }
}
