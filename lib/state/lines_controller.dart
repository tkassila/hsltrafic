import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/line.dart';
import '../models/place_stop.dart';
import 'app_state.dart';

enum LinesSearchMode {
  line,
  stop,
}

enum TimetableDayType {
  today,
  weekday,
  saturday,
  sunday,
}

class LinesController extends ChangeNotifier {
  final Services s;
  final LocationController loc;

  LinesSearchMode searchMode = LinesSearchMode.line;
  TimetableDayType dayType = TimetableDayType.today;

  String query = '';
  bool isLoading = false;
  bool isLoadingTimetable = false;
  String? errorMessage;

  // Linjahaku
  List<LineInfo> matchingLines = [];
  LineInfo? selectedLine;
  LinePattern? selectedPattern;

  // Pysäkkihaku
  List<Stop> matchingStops = [];
  Stop? selectedStop;
  StopRoute? selectedStopRoute;

  // Pysäkin aikataululista
  List<Departure> departures = [];
  bool isTimetableVisible = false;

  // Kartan tila
  LatLng? center;
  double zoom = 14.5;

  LinesController(this.s, this.loc) {
    center = loc.position ?? loc.positionOrDefault;
    s.settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (!loc.hasRealGps && s.settings.region.center != null) {
      center = s.settings.region.center;
      query = '';
      errorMessage = null;
      matchingLines = [];
      matchingStops = [];
      selectedLine = null;
      selectedPattern = null;
      selectedStop = null;
      selectedStopRoute = null;
      isTimetableVisible = false;
      departures = [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    s.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void setSearchMode(LinesSearchMode mode) {
    if (searchMode == mode) return;
    searchMode = mode;
    query = '';
    errorMessage = null;
    matchingLines = [];
    matchingStops = [];
    selectedStop = null;
    selectedStopRoute = null;
    isTimetableVisible = false;
    departures = [];
    notifyListeners();
  }

  void setDayType(TimetableDayType type) {
    if (dayType == type) return;
    dayType = type;
    notifyListeners();
    if (selectedStop != null) {
      fetchTimetableForSelectedStop();
    }
  }

  DateTime _dateForDayType(TimetableDayType type) {
    final now = DateTime.now();
    switch (type) {
      case TimetableDayType.today:
        return now;
      case TimetableDayType.weekday:
        // Seuraava arkipäivä (ma–pe)
        var d = now;
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      case TimetableDayType.saturday:
        // Seuraava lauantai
        var d = now;
        while (d.weekday != DateTime.saturday) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      case TimetableDayType.sunday:
        // Seuraava sunnuntai
        var d = now;
        while (d.weekday != DateTime.sunday) {
          d = d.add(const Duration(days: 1));
        }
        return d;
    }
  }

  /// Suorittaa haun nykyisessä tilassa (Linja tai Pysäkki)
  Future<void> search(String text) async {
    final q = text.trim();
    query = q;
    errorMessage = null;
    if (q.isEmpty) {
      clearSearch();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      if (searchMode == LinesSearchMode.line) {
        await _searchLines(q);
      } else {
        await _searchStops(q);
      }
    } catch (e) {
      errorMessage = 'Haussa tapahtui virhe: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _searchLines(String q) async {
    matchingLines = [];
    final lines = await s.api.searchLines(q);
    if (lines.isEmpty) {
      errorMessage = 'Linjaa "$q" ei löytynyt.';
      selectedLine = null;
      selectedPattern = null;
      return;
    }

    // Etsitään tarkin vastaavuus (suositaan aktiivisen alueen feedId:tä, esim. Tampereella tampere:3)
    final targetFeed = s.settings.region.feedId?.toLowerCase();
    LineInfo? best;
    for (final l in lines) {
      final matchesName = l.shortName.toLowerCase() == q.toLowerCase();
      final matchesFeed = targetFeed != null && l.gtfsId.toLowerCase().startsWith('$targetFeed:');
      if (matchesName && matchesFeed) {
        best = l;
        break;
      }
    }
    if (best == null) {
      for (final l in lines) {
        if (l.shortName.toLowerCase() == q.toLowerCase()) {
          best = l;
          break;
        }
      }
    }
    best ??= lines.first;
    matchingLines = lines;

    // Haetaan linjan täydet reittikuviot ja pysäkit
    final full = await s.api.routeWithPatterns(best.gtfsId);
    selectedLine = full ?? best;
    if (selectedLine != null && selectedLine!.patterns.isNotEmpty) {
      selectedPattern = selectedLine!.patterns.first;
      if (selectedPattern!.geometry.isNotEmpty) {
        center = selectedPattern!.geometry.first;
      } else if (selectedPattern!.stops.isNotEmpty) {
        center = selectedPattern!.stops.first.position;
      }
    }
  }

  Future<void> _searchStops(String q) async {
    matchingStops = [];
    final stops = await s.api.searchStops(q);
    if (stops.isEmpty) {
      errorMessage = 'Pysäkkiä "$q" ei löytynyt.';
      selectedStop = null;
      departures = [];
      return;
    }

    matchingStops = stops;
    // Valitaan ensimmäinen pysäkki ja ladataan sen aikataulu
    await selectStop(stops.first);
  }

  /// Valitsee linjan toisen suunnan/reittikuvion
  void selectPattern(LinePattern pattern) {
    selectedPattern = pattern;
    // Jos aiemmin valittu pysäkki ei ole tällä reitillä, nollataan se
    if (selectedStop != null &&
        !pattern.stops.any((s) => s.gtfsId == selectedStop!.gtfsId)) {
      selectedStop = null;
      departures = [];
    }
    notifyListeners();
  }

  /// Valitsee pysäkin kartalta tai listalta ja hakee sen aikataulun
  Future<void> selectStop(Stop stop) async {
    selectedStop = stop;
    selectedStopRoute = null;
    isTimetableVisible = true;
    center = stop.position;
    notifyListeners();
    await fetchTimetableForSelectedStop();
  }

  /// Hakee valitun pysäkin aikataulutiedot
  Future<void> fetchTimetableForSelectedStop() async {
    if (selectedStop == null) return;
    isLoadingTimetable = true;
    notifyListeners();

    try {
      final targetDate = _dateForDayType(dayType);
      final deps = await s.api.stopTimetable(selectedStop!.gtfsId, date: targetDate);
      departures = deps;
    } catch (_) {
      departures = [];
    } finally {
      isLoadingTimetable = false;
      notifyListeners();
    }
  }

  /// 7) Kun pysäkin listalta valitaan tietty linja:
  /// Näytetään sen linjan reitti kartalla korostaen valittua pysäkkiä.
  Future<void> selectLineFromStop(StopRoute route) async {
    selectedStopRoute = route;
    isLoading = true;
    notifyListeners();

    try {
      final fullLine = await s.api.routeWithPatterns(route.gtfsId);
      if (fullLine != null) {
        selectedLine = fullLine;
        // Etsitään pattern, joka kulkee tämän pysäkin kautta
        LinePattern? matchingPattern;
        for (final p in fullLine.patterns) {
          if (selectedStop != null && p.stops.any((s) => s.gtfsId == selectedStop!.gtfsId)) {
            matchingPattern = p;
            break;
          }
        }
        matchingPattern ??= fullLine.patterns.firstOrNull;
        selectedPattern = matchingPattern;
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Avaa valitun pysäkin aikataululistan uudelleen
  void openTimetable() {
    if (selectedStop != null) {
      isTimetableVisible = true;
      notifyListeners();
      if (departures.isEmpty) {
        fetchTimetableForSelectedStop();
      }
    }
  }

  /// Sulkee valitun pysäkin aikataululistan (x-ruksi).
  /// 2) Jättää valitun pysäkin markeerauksen näkyviin kartalle (selectedStop säilyy, isTimetableVisible = false).
  void clearSelectedStop({bool unmarkStop = false}) {
    isTimetableVisible = false;
    if (unmarkStop) {
      selectedStop = null;
      selectedStopRoute = null;
      departures = [];
    }
    notifyListeners();
  }

  /// Nollaa haun ja tyhjentää valinnat (hakukentän x-ruksi)
  void clearSearch() {
    query = '';
    errorMessage = null;
    matchingLines = [];
    matchingStops = [];
    selectedLine = null;
    selectedPattern = null;
    selectedStop = null;
    selectedStopRoute = null;
    isTimetableVisible = false;
    departures = [];
    notifyListeners();
  }
}

