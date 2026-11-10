import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/features/alarms/alarm_management_dialog.dart';
import 'package:hsltrafic/features/nearby/nearby_stops_view.dart';
import 'package:hsltrafic/features/planner/planner_view.dart';
import 'package:hsltrafic/models/journey.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/models/trip_alarm.dart';
import 'package:hsltrafic/shared/widgets.dart';
import 'package:hsltrafic/state/alarm_controller.dart';
import 'package:hsltrafic/state/app_state.dart';
import 'package:hsltrafic/state/nearby_controller.dart';
import 'package:hsltrafic/state/planner_controller.dart';
import 'package:provider/provider.dart';

class _FakeNearbyClient extends DigitransitClient {
  final Stop mockStop;
  final List<Departure> deps;
  _FakeNearbyClient(this.mockStop, this.deps);

  @override
  Future<List<Stop>> stopsByRadius(LatLng c, int radius, {int max = 100}) async => [mockStop];

  @override
  Future<Map<String, List<Departure>>> departuresForStops(
    List<String> ids, {
    int count = 3,
  }) async => {mockStop.gtfsId: deps};

  @override
  Future<List<Departure>> departures(String stopId, {int count = 10}) async => deps;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TripAlarm model & AlarmController', () {
    late Services services;
    late FavoritesRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = FavoritesRepository(prefs);
      services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: repo,
      );
    });

    test('TripAlarm serialization and deserialization work correctly', () {
      final now = DateTime.now();
      final alarm = TripAlarm(
        id: 'alarm_1',
        title: 'Bussi 550',
        line: '550',
        mode: TransitMode.bus,
        destination: 'Itäkeskus',
        stopName: 'Otaniemi',
        departureTime: now.add(const Duration(minutes: 20)),
        walkStartTime: now.add(const Duration(minutes: 15)),
        alarmTime: now.add(const Duration(minutes: 8)),
        source: 'planner',
      );

      final json = alarm.toJson();
      expect(json['id'], equals('alarm_1'));
      expect(json['line'], equals('550'));
      expect(json['mode'], equals('bus'));

      final restored = TripAlarm.fromJson(json);
      expect(restored.id, equals('alarm_1'));
      expect(restored.title, equals('Bussi 550'));
      expect(restored.line, equals('550'));
      expect(restored.mode, equals(TransitMode.bus));
      expect(restored.destination, equals('Itäkeskus'));
      expect(restored.isTriggered, isFalse);
    });

    test('AlarmController adds, persists, and removes alarms', () async {
      final controller = AlarmController(services);
      final now = DateTime.now();

      final alarm1 = TripAlarm(
        id: 'alarm_1',
        title: 'Bussi 550',
        line: '550',
        mode: TransitMode.bus,
        destination: 'Itäkeskus',
        departureTime: now.add(const Duration(minutes: 30)),
        walkStartTime: now.add(const Duration(minutes: 25)),
        alarmTime: now.add(const Duration(minutes: 18)), // 25 - 7
        source: 'planner',
      );

      final count1 = await controller.addAlarm(alarm1);
      expect(count1, equals(1));
      expect(controller.alarms.length, equals(1));
      expect(controller.activeAlarms.length, equals(1));

      // Add second alarm
      final alarm2 = TripAlarm(
        id: 'alarm_2',
        title: 'Raitiovaunu 15',
        line: '15',
        mode: TransitMode.tram,
        destination: 'Keilaniemi',
        departureTime: now.add(const Duration(minutes: 45)),
        walkStartTime: now.add(const Duration(minutes: 40)),
        alarmTime: now.add(const Duration(minutes: 33)), // 40 - 7
        source: 'nearby',
      );

      final count2 = await controller.addAlarm(alarm2);
      expect(count2, equals(2));
      expect(controller.activeAlarms.length, equals(2));

      // Remove first alarm
      await controller.removeAlarm('alarm_1');
      expect(controller.alarms.length, equals(1));
      expect(controller.alarms.first.id, equals('alarm_2'));

      // Clear all
      await controller.clearAllAlarms();
      expect(controller.alarms, isEmpty);

      controller.dispose();
    });

    test('AlarmController triggerAlarm and dismissRinging work', () {
      final controller = AlarmController(services);
      final now = DateTime.now();
      final alarm = TripAlarm(
        id: 'alarm_test',
        title: 'Bussi 550',
        line: '550',
        mode: TransitMode.bus,
        destination: 'Itäkeskus',
        departureTime: now.add(const Duration(minutes: 10)),
        walkStartTime: now.add(const Duration(minutes: 8)),
        alarmTime: now.add(const Duration(minutes: 1)),
        source: 'nearby',
      );

      expect(controller.isRinging, isFalse);
      controller.triggerAlarm(alarm);

      expect(controller.isRinging, isTrue);
      expect(controller.ringingAlarm?.id, equals('alarm_test'));
      expect(alarm.isTriggered, isTrue);

      controller.dismissRinging();
      expect(controller.isRinging, isFalse);
      expect(controller.ringingAlarm, isNull);

      controller.dispose();
    });
  });

  group('Alarm UI integration tests', () {
    late Services services;
    late SettingsController settings;
    late LocationController loc;
    late AlarmController alarmCtrl;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: repo,
      );
      settings = SettingsController(services);
      loc = LocationController(services);
      alarmCtrl = AlarmController(services);
    });

    tearDown(() {
      alarmCtrl.dispose();
    });

    testWidgets('AppBar shows Alarm icon and opens AlarmManagementDialog in PlannerView', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<Services>.value(value: services),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: loc),
            ChangeNotifierProvider.value(value: alarmCtrl),
            ChangeNotifierProvider(create: (_) => PlannerController(services, loc)),
          ],
          child: const MaterialApp(home: PlannerView()),
        ),
      );
      await tester.pumpAndSettle();

      // Find alarm icon in AppBar
      final alarmBtn = find.byTooltip('Hälytysten hallinta');
      expect(alarmBtn, findsOneWidget);

      // Tap alarm icon to open dialog
      await tester.tap(alarmBtn);
      await tester.pumpAndSettle();

      // Verify AlarmManagementDialog is open
      expect(find.byType(AlarmManagementDialog), findsOneWidget);
      expect(find.text('Matkahälytykset'), findsOneWidget);
      expect(find.text('Ei aktiivisia hälytyksiä'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Valmis'));
      await tester.pumpAndSettle();
      expect(find.byType(AlarmManagementDialog), findsNothing);
    });

    testWidgets('AppBar shows Alarm icon and opens AlarmManagementDialog in NearbyStopsView', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<Services>.value(value: services),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: loc),
            ChangeNotifierProvider.value(value: alarmCtrl),
            ChangeNotifierProvider(create: (_) => NearbyController(services, loc, settings)),
          ],
          child: const MaterialApp(home: NearbyStopsView()),
        ),
      );
      await tester.pumpAndSettle();

      // Find alarm icon in AppBar
      final alarmBtn = find.byTooltip('Hälytysten hallinta');
      expect(alarmBtn, findsOneWidget);

      // Tap alarm icon
      await tester.tap(alarmBtn);
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.byType(AlarmManagementDialog), findsOneWidget);
      expect(find.text('Matkahälytykset'), findsOneWidget);
    });

    testWidgets('Long pressing starting route icon in PlannerView sets alarm to walk time - 7 min', (tester) async {
      final now = DateTime.now();
      final itinStart = now.add(const Duration(minutes: 30));
      final plannerCtrl = PlannerController(services, loc);
      plannerCtrl.results = [
        Itinerary(
          start: itinStart,
          end: itinStart.add(const Duration(minutes: 20)),
          walkDistance: 50,
          transfers: 0,
          legs: [
            Leg(
              mode: TransitMode.bus,
              fromName: 'Otaniemi',
              fromPos: const LatLng(60.18, 24.83),
              toName: 'Kamppi',
              toPos: const LatLng(60.17, 24.93),
              start: itinStart,
              end: itinStart.add(const Duration(minutes: 20)),
              line: '550',
              headsign: 'Itäkeskus',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<Services>.value(value: services),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: loc),
            ChangeNotifierProvider.value(value: alarmCtrl),
            ChangeNotifierProvider.value(value: plannerCtrl),
          ],
          child: const MaterialApp(home: PlannerView()),
        ),
      );
      await tester.pumpAndSettle();

      // Find the starting route icon (LineBadge)
      final badgeFinder = find.byType(LineBadge);
      expect(badgeFinder, findsOneWidget);

      // Ensure visible and long press the starting route icon
      await tester.ensureVisible(badgeFinder);
      await tester.pumpAndSettle();
      await tester.longPress(badgeFinder);
      await tester.pumpAndSettle();

      // Verify alarm was created with walkStartTime - 7 min
      expect(alarmCtrl.alarms.length, equals(1));
      final createdAlarm = alarmCtrl.alarms.first;
      expect(createdAlarm.line, equals('550'));
      expect(createdAlarm.walkStartTime, equals(itinStart));
      expect(createdAlarm.alarmTime, equals(itinStart.subtract(const Duration(minutes: 7))));

      // Verify SnackBar was shown
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('7 min ennen kävelyä'), findsOneWidget);
    });

    testWidgets('Long pressing line box in NearbyStopsView sets alarm and notifies user if alarms > 1', (tester) async {
      final now = DateTime.now();
      final depTime = now.add(const Duration(minutes: 25));
      final testStop = Stop(
        gtfsId: 'HSL:1234',
        name: 'Otaniemi',
        code: '2214',
        position: const LatLng(60.18, 24.83),
        distance: 210, // 210 / 70 = 3 min walk
        mode: TransitMode.bus,
      );
      final testDepartures = [
        Departure(
          line: '550',
          mode: TransitMode.bus,
          headsign: 'Itäkeskus',
          scheduled: depTime,
          realtime: depTime,
          isRealtime: true,
        ),
      ];

      final customServices = Services(
        api: _FakeNearbyClient(testStop, testDepartures),
        hfp: HfpService(),
        location: LocationService(),
        repo: services.repo,
      );
      final customNearbyCtrl = NearbyController(customServices, loc, settings);

      // Pre-add an alarm so that when new one is added, count will be > 1
      await alarmCtrl.addAlarm(
        TripAlarm(
          id: 'existing_alarm',
          title: 'Aiempi hälytys',
          line: '10',
          mode: TransitMode.tram,
          destination: 'Pikku Huopalahti',
          departureTime: now.add(const Duration(minutes: 60)),
          walkStartTime: now.add(const Duration(minutes: 55)),
          alarmTime: now.add(const Duration(minutes: 48)),
          source: 'planner',
        ),
      );
      expect(alarmCtrl.activeAlarms.length, equals(1));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<Services>.value(value: customServices),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: loc),
            ChangeNotifierProvider.value(value: alarmCtrl),
            ChangeNotifierProvider.value(value: customNearbyCtrl),
          ],
          child: const MaterialApp(home: NearbyStopsView()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap stop to expand departures
      await tester.tap(find.text('Otaniemi'));
      await tester.pumpAndSettle();

      // Find the LineBadge / departure box
      final lineBadgeFinder = find.byType(LineBadge);
      expect(lineBadgeFinder, findsOneWidget);

      // Long press line box
      await tester.longPress(lineBadgeFinder);
      await tester.pumpAndSettle();

      // Verify alarm was added
      expect(alarmCtrl.alarms.length, equals(2));
      final nearbyAlarm = alarmCtrl.alarms.firstWhere((a) => a.line == '550');
      // Walk time = 3 min, alarm time = 25 - 3 - 7 = 15 min from now
      expect(nearbyAlarm.walkStartTime, equals(depTime.subtract(const Duration(minutes: 3))));
      expect(nearbyAlarm.alarmTime, equals(depTime.subtract(const Duration(minutes: 10))));

      // Verify SnackBar was shown AND alerted about having > 1 alarms active!
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Sinulla on nyt 2 aktiivista hälytystä'), findsOneWidget);
    });
  });
}
