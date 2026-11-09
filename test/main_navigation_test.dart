import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/features/live_map/live_map_view.dart';
import 'package:hsltrafic/features/more/more_view.dart';
import 'package:hsltrafic/features/nearby/nearby_stops_view.dart';
import 'package:hsltrafic/features/planner/planner_view.dart';
import 'package:hsltrafic/main.dart';
import 'package:hsltrafic/models/journey.dart';
import 'package:hsltrafic/models/line.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/models/vehicle.dart';
import 'package:hsltrafic/state/alarm_controller.dart';
import 'package:hsltrafic/state/app_state.dart';
import 'package:hsltrafic/state/lines_controller.dart';
import 'package:hsltrafic/state/live_map_controller.dart';
import 'package:hsltrafic/state/nearby_controller.dart';
import 'package:hsltrafic/state/planner_controller.dart';
import 'package:hsltrafic/theme/app_theme.dart';
import 'package:hsltrafic/theme/hsl_colors.dart';
import 'package:provider/provider.dart';

class _FakeHfpService extends HfpService {
  final _testStream = StreamController<List<Vehicle>>.broadcast();
  Set<String> lastRouteIds = const {};
  bool lastRouteOnly = false;
  double lastRadius = 0;

  @override
  Stream<List<Vehicle>> get stream => _testStream.stream;

  void emitVehicles(List<Vehicle> list) => _testStream.add(list);

  @override
  Future<void> setArea(
    LatLng center,
    double radiusMeters, {
    Iterable<String>? routeIds,
    bool routeOnly = false,
  }) async {
    lastRadius = radiusMeters;
    if (routeIds != null) {
      lastRouteIds = routeIds.map((e) => e.replaceFirst('HSL:', '')).toSet();
    }
    lastRouteOnly = routeOnly;
  }

  @override
  Future<void> setRoutes(
    Iterable<String> routeIds, {
    bool routeOnly = false,
    LatLng? center,
    double? radiusMeters,
  }) async {
    lastRouteIds = routeIds.map((e) => e.replaceFirst('HSL:', '')).toSet();
    lastRouteOnly = routeOnly;
    if (radiusMeters != null) lastRadius = radiusMeters;
  }
}

class _FakeDigitransitClient extends DigitransitClient {
  LatLng? lastFrom;
  LatLng? lastTo;
  int? lastRoutesNearRadius;

  @override
  Future<List<Itinerary>> plan({
    required LatLng from,
    required LatLng to,
    List<LatLng> via = const [],
    DateTime? time,
    bool arriveBy = false,
    Set<TransitMode> modes = const {},
    int count = 5,
  }) async {
    lastFrom = from;
    lastTo = to;
    return const [];
  }

  @override
  Future<List<TransitAlert>> alerts() async => const [];

  @override
  Future<List<Stop>> stopsByRadius(LatLng c, int radius, {int max = 100}) async => const [];

  @override
  Future<List<LineInfo>> routesNear(LatLng c, {int radius = 2000, int maxStops = 100}) async {
    lastRoutesNearRadius = radius;
    return const [
      LineInfo(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala - Länsisatama', mode: TransitMode.tram),
      LineInfo(gtfsId: 'HSL:1004', shortName: '4', longName: 'Katajanokka - Munkkiniemi', mode: TransitMode.tram),
      LineInfo(gtfsId: 'HSL:2550', shortName: '550', longName: 'Itäkeskus - Westendinasema', mode: TransitMode.bus),
    ];
  }

  @override
  Future<List<LineInfo>> searchLines(String name) async {
    if (name.trim() == '550') {
      return const [
        LineInfo(gtfsId: 'HSL:2550', shortName: '550', longName: 'Itäkeskus - Westendinasema', mode: TransitMode.bus),
      ];
    }
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PlannerView is shown by default on app launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final services = Services(
      api: _FakeDigitransitClient(),
      hfp: _FakeHfpService(),
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final loc = LocationController(services);
    final settings = SettingsController(services);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: loc),
          ChangeNotifierProvider(create: (_) => FavoritesController(services)),
          ChangeNotifierProvider(create: (_) => AlertsController(services)),
          ChangeNotifierProvider(create: (_) => AlarmController(services)),
          ChangeNotifierProvider(create: (_) => LiveMapController(services)),
          ChangeNotifierProvider(create: (_) => LinesController(services, loc)),
          ChangeNotifierProvider(create: (_) => PlannerController(services, loc)),
          ChangeNotifierProvider(create: (_) => NearbyController(services, loc, settings)),
        ],
        child: const HslTrafficApp(),
      ),
    );

    // Initial view should contain PlannerView
    expect(find.byType(PlannerView), findsOneWidget);
  });

  test('PlannerController uses current location by default when only destination is set', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeApi = _FakeDigitransitClient();
    final services = Services(
      api: fakeApi,
      hfp: HfpService(),
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final loc = LocationController(services)
      ..position = const LatLng(60.1700, 24.9400)
      ..state = LocationState.ready;
    final planner = PlannerController(services, loc);

    // Even if from was cleared to null, search defaults to current location
    planner.from = null;
    planner.setTo(const GeoPlace(label: 'Kamppi', position: LatLng(60.1685, 24.9325)));

    await planner.search();

    expect(planner.error, isNull);
    expect(planner.searched, isTrue);
    expect(fakeApi.lastFrom, equals(const LatLng(60.1700, 24.9400)));
    expect(fakeApi.lastTo, equals(const LatLng(60.1685, 24.9325)));
  });

  test('Light theme uses warm light beige background and surface colors', () {
    final light = AppTheme.lightTheme;
    expect(light.scaffoldBackgroundColor, equals(HslColors.backgroundLight));
    expect(light.colorScheme.surface, equals(HslColors.surfaceLight));
  });

  testWidgets('MoreView sections open and close exclusively when headers are tapped', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final services = Services(
      api: _FakeDigitransitClient(),
      hfp: HfpService(),
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final settings = SettingsController(services);
    final alerts = AlertsController(services);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: alerts),
        ],
        child: const MaterialApp(home: MoreView()),
      ),
    );
    await tester.pumpAndSettle();

    // Initially all section sub-items are closed
    expect(find.text('Teema'), findsNothing);
    expect(find.text('Ei aktiivisia liikennehäiriöitä.'), findsNothing);

    // Tap "Asetukset" header -> opens settings sub-items
    await tester.tap(find.text('Asetukset'));
    await tester.pumpAndSettle();
    expect(find.text('Teema'), findsOneWidget);

    // Tap "Liikennehäiriöt & Tiedotteet" header -> closes "Asetukset" and opens alerts
    await tester.tap(find.text('Liikennehäiriöt & Tiedotteet'));
    await tester.pumpAndSettle();
    expect(find.text('Teema'), findsNothing);
    expect(find.text('Ei aktiivisia liikennehäiriöitä.'), findsOneWidget);

    // Tap "Liikennehäiriöt & Tiedotteet" again -> closes it
    await tester.tap(find.text('Liikennehäiriöt & Tiedotteet'));
    await tester.pumpAndSettle();
    expect(find.text('Ei aktiivisia liikennehäiriöitä.'), findsNothing);
  });

  testWidgets('Theme switching and FilterChip toggling on LiveMapView interpolate TextStyles without error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeApi = _FakeDigitransitClient();
    final fakeHfp = _FakeHfpService();
    final services = Services(
      api: fakeApi,
      hfp: fakeHfp,
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final loc = LocationController(services)..state = LocationState.serviceOff;
    final settings = SettingsController(services);
    final live = LiveMapController(services);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: loc),
          ChangeNotifierProvider(create: (_) => FavoritesController(services)),
          ChangeNotifierProvider(create: (_) => AlertsController(services)),
          ChangeNotifierProvider(create: (_) => AlarmController(services)),
          ChangeNotifierProvider.value(value: live),
          ChangeNotifierProvider(create: (_) => LinesController(services, loc)),
          ChangeNotifierProvider(create: (_) => PlannerController(services, loc)),
          ChangeNotifierProvider(create: (_) => NearbyController(services, loc, settings)),
        ],
        child: const HslTrafficApp(),
      ),
    );
    await tester.pump();

    // Navigate to Live-kartta tab
    await tester.tap(find.text('Live-kartta'));
    await tester.pump();

    // Default mode subscribes to 5km radius nearby stops' routes
    await live.start();
    expect(fakeApi.lastRoutesNearRadius, equals(5000));
    expect(fakeHfp.lastRouteIds, containsAll(['1004', '2550']));
    expect(fakeHfp.lastRouteOnly, isFalse);

    // Searching a specific line subscribes specifically to that line
    await live.search('550');
    expect(fakeHfp.lastRouteIds, contains('2550'));
    expect(fakeHfp.lastRouteOnly, isTrue);

    // Toggle a FilterChip on LiveMapView
    await tester.tap(find.text('Bussi'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // Switch theme from dark to light and back during animation frames
    settings.setTheme(ThemeMode.light);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));

    settings.setTheme(ThemeMode.dark);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  test('LiveMapController filters only nearby active routes and resolves specific destination headsign instead of general route name', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeApi = _FakeDigitransitClient();
    final fakeHfp = _FakeHfpService();
    final services = Services(
      api: fakeApi,
      hfp: fakeHfp,
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final live = LiveMapController(services);
    await live.start();

    final now = DateTime.now();
    // Emit two vehicles on nearby route HSL:1009 (dir 0 -> Länsisatama, dir 1 -> Ilmala)
    // and one random vehicle on an unrelated route HSL:9999 within 500m
    fakeHfp.emitVehicles([
      Vehicle(
        id: '1/101',
        line: '9',
        routeGtfsId: 'HSL:1009',
        direction: 0,
        mode: TransitMode.tram,
        position: const LatLng(60.1705, 24.9390),
        updatedAt: now,
        headsign: '', // missing in HFP -> should resolve to 'Länsisatama'
      ),
      Vehicle(
        id: '1/102',
        line: '9',
        routeGtfsId: 'HSL:1009',
        direction: 1,
        mode: TransitMode.tram,
        position: const LatLng(60.1710, 24.9400),
        updatedAt: now,
        headsign: 'Ilmala - Länsisatama', // general name -> should resolve to 'Ilmala'
      ),
      Vehicle(
        id: '1/999',
        line: '615',
        routeGtfsId: 'HSL:9999',
        direction: 0,
        mode: TransitMode.bus,
        position: const LatLng(60.1700, 24.9385),
        updatedAt: now,
        headsign: 'Lentoasema',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    final visible = live.vehicles;
    // Unrelated route HSL:9999 must NOT be included
    expect(visible.map((v) => v.id), equals(['1/101', '1/102']));
    // Direction 0 resolves to 'Länsisatama', direction 1 resolves to 'Ilmala'
    expect(visible[0].line, equals('9'));
    expect(visible[0].headsign, equals('Länsisatama'));
    expect(visible[1].line, equals('9'));
    expect(visible[1].headsign, equals('Ilmala'));
    live.dispose();
  });

  testWidgets('NearbyStopsView toggles query fields card and map visibility via AppBar action buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final services = Services(
      api: _FakeDigitransitClient(),
      hfp: _FakeHfpService(),
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final loc = LocationController(services);
    final settings = SettingsController(services);
    final nearby = NearbyController(services, loc, settings);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: loc),
          ChangeNotifierProvider(create: (_) => AlarmController(services)),
          ChangeNotifierProvider.value(value: nearby),
        ],
        child: const MaterialApp(home: NearbyStopsView()),
      ),
    );
    await tester.pumpAndSettle();

    // Query fields card is initially shown (contains search radius)
    expect(find.textContaining('Hakusäde'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);

    // Tap toggle query fields button
    final queryToggle = find.byTooltip('Piilota kyselykentät');
    expect(queryToggle, findsOneWidget);
    await tester.tap(queryToggle);
    await tester.pumpAndSettle();

    // Query fields card is now hidden
    expect(find.textContaining('Hakusäde'), findsNothing);
    expect(find.byTooltip('Näytä kyselykentät'), findsOneWidget);

    // Tap toggle map button
    final mapToggle = find.byTooltip('Piilota kartta');
    expect(mapToggle, findsOneWidget);
    await tester.tap(mapToggle);
    await tester.pumpAndSettle();

    // Map is now hidden
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byTooltip('Näytä kartta'), findsOneWidget);
  });

  testWidgets('PlannerView toggles query fields card and map visibility via AppBar action buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeApi = _FakeDigitransitClient();
    final services = Services(
      api: fakeApi,
      hfp: _FakeHfpService(),
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final loc = LocationController(services);
    final settings = SettingsController(services);
    final planner = PlannerController(services, loc);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: loc),
          ChangeNotifierProvider(create: (_) => AlarmController(services)),
          ChangeNotifierProvider.value(value: planner),
        ],
        child: const MaterialApp(home: PlannerView()),
      ),
    );
    await tester.pumpAndSettle();

    // Search button is visible initially in the search card
    expect(find.text('Hae reitit'), findsOneWidget);

    // Tap toggle query fields button
    final queryToggle = find.byTooltip('Piilota kyselykentät');
    expect(queryToggle, findsOneWidget);
    await tester.tap(queryToggle);
    await tester.pumpAndSettle();

    // Search card is hidden, placeholder is visible
    expect(find.text('Hae reitit'), findsNothing);
    expect(find.text('Kyselykentät on piilotettu.'), findsOneWidget);
    expect(find.byTooltip('Näytä kyselykentät'), findsOneWidget);

    // Tap to show query fields again
    await tester.tap(find.byTooltip('Näytä kyselykentät'));
    await tester.pumpAndSettle();
    expect(find.text('Hae reitit'), findsOneWidget);
  });

  testWidgets('NearbyStopsView displays stop label with side offset when line pattern is selected', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeApi = _FakeDigitransitClient();
    final fakeHfp = _FakeHfpService();
    final services = Services(
      api: fakeApi,
      hfp: fakeHfp,
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    final loc = LocationController(services);
    final settings = SettingsController(services);
    final nearby = NearbyController(services, loc, settings);

    const stop = Stop(
      gtfsId: 'HSL:1010',
      name: 'Pasilan asema',
      code: 'H0020',
      position: LatLng(60.198, 24.933),
      mode: TransitMode.tram,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: loc),
          ChangeNotifierProvider(create: (_) => AlarmController(services)),
          ChangeNotifierProvider.value(value: nearby),
        ],
        child: const MaterialApp(home: NearbyStopsView()),
      ),
    );
    await tester.pumpAndSettle();

    nearby.selectStop(stop);
    nearby.selectedLine = '9';
    nearby.selectedLineMode = TransitMode.tram;
    nearby.selectedLinePattern = const LinePattern(
      code: '1009:1',
      directionId: 1,
      headsign: 'Ilmala',
      geometry: [],
      stops: [
        Stop(gtfsId: 'HSL:1001', name: 'Jätkäsaari', position: LatLng(60.158, 24.919)),
        Stop(gtfsId: 'HSL:1010', name: 'Pasilan asema', position: LatLng(60.198, 24.933)),
        Stop(gtfsId: 'HSL:1020', name: 'Ilmalan tori', position: LatLng(60.205, 24.921)),
      ],
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    nearby.notifyListeners();
    await tester.pumpAndSettle();

    // Pysäkin label näkyy kartalla
    expect(find.text('Pasilan asema'), findsWidgets);
  });

  testWidgets('Tapping Hae button on LiveMapView locates current position, centers map and executes search', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeApi = _FakeDigitransitClient();
    final fakeHfp = _FakeHfpService();
    final services = Services(
      api: fakeApi,
      hfp: fakeHfp,
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );

    final settings = SettingsController(services);
    final loc = LocationController(services)
      ..position = const LatLng(60.1700, 24.9400)
      ..state = LocationState.ready;
    final live = LiveMapController(services);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: loc),
          ChangeNotifierProvider.value(value: live),
        ],
        child: const MaterialApp(home: LiveMapView()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap "Hae" button
    final haeButton = find.widgetWithText(ElevatedButton, 'Hae');
    expect(haeButton, findsOneWidget);
    await tester.tap(haeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Map and controller center matches current location
    expect(live.center.latitude, closeTo(loc.positionOrDefault.latitude, 0.001));
    expect(live.center.longitude, closeTo(loc.positionOrDefault.longitude, 0.001));
  });
}
