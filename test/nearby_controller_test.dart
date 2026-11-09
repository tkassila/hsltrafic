import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/state/app_state.dart';
import 'package:hsltrafic/state/nearby_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NearbyController selection tests', () {
    late Services services;
    late LocationController loc;
    late SettingsController settings;
    late NearbyController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: FavoritesRepository(prefs),
      );
      loc = LocationController(services);
      settings = SettingsController(services);
      controller = NearbyController(services, loc, settings);
    });

    test('selectStop sets selected stop and clears line pattern', () {
      const stop = Stop(
        gtfsId: 'HSL:1010101',
        name: 'Rautatieasema',
        position: LatLng(60.171, 24.941),
        mode: TransitMode.tram,
      );

      controller.selectStop(stop);
      expect(controller.selectedStopId, equals('HSL:1010101'));
      expect(controller.selectedStop?.name, equals('Rautatieasema'));
      expect(controller.selectedLine, isNull);
      expect(controller.selectedLinePattern, isNull);

      // Toggling the same stop deselects it
      controller.selectStop(stop, toggle: true);
      expect(controller.selectedStop, isNull);
      expect(controller.selectedStopId, isNull);
    });

    test('clearLineRoute clears line but retains selected stop', () {
      const stop = Stop(
        gtfsId: 'HSL:1010102',
        name: 'Kamppi',
        position: LatLng(60.169, 24.938),
        mode: TransitMode.bus,
      );

      controller.selectStop(stop);
      controller.selectedLine = '550';
      controller.clearLineRoute();

      expect(controller.selectedStopId, equals('HSL:1010102'));
      expect(controller.selectedLine, isNull);
      expect(controller.selectedLinePattern, isNull);
    });

    test('clearSelection clears both stop and line', () {
      const stop = Stop(
        gtfsId: 'HSL:1010103',
        name: 'Pasila',
        position: LatLng(60.198, 24.933),
        mode: TransitMode.rail,
      );

      controller.selectStop(stop);
      controller.clearSelection();

      expect(controller.selectedStop, isNull);
      expect(controller.selectedLine, isNull);
      expect(controller.selectedLinePattern, isNull);
      expect(controller.lineHourDepartures, isEmpty);
    });

    test('lineHourDepartures is cleared on clearLineRoute', () {
      const stop = Stop(
        gtfsId: 'HSL:1010104',
        name: 'Hakaniemi',
        position: LatLng(60.178, 24.950),
        mode: TransitMode.metro,
      );

      controller.selectStop(stop);
      controller.selectedLine = 'M1';
      controller.clearLineRoute();

      expect(controller.lineHourDepartures, isEmpty);
      expect(controller.loadingHourDepartures, isFalse);
    });

    test('selectLineRoute closes 2h departures when the same line is clicked again', () async {
      const stop = Stop(
        gtfsId: 'HSL:1010105',
        name: 'Ooppera',
        position: LatLng(60.181, 24.929),
        mode: TransitMode.tram,
      );

      controller.selectStop(stop);
      controller.selectedLine = '4';
      controller.selectedHeadsign = 'Munkkiniemi';
      controller.selectedDepartureIndex = 0;

      await controller.selectLineRoute(
        stop: stop,
        line: '4',
        mode: TransitMode.tram,
        headsign: 'Munkkiniemi',
        departureIndex: 0,
      );

      expect(controller.selectedStopId, equals('HSL:1010105'));
      expect(controller.selectedLine, isNull);
      expect(controller.selectedHeadsign, isNull);
      expect(controller.selectedDepartureIndex, isNull);
      expect(controller.lineHourDepartures, isEmpty);
    });

    test('Departure time formatting and minutes calculation work correctly', () {
      final now = DateTime.now();
      final dep = Departure(
        line: '550',
        mode: TransitMode.bus,
        headsign: 'Itäkeskus',
        scheduled: now.add(const Duration(minutes: 15)),
        realtime: now.add(const Duration(minutes: 17)),
        isRealtime: true,
      );

      expect(dep.minutesUntil(now), equals(17));
      expect(dep.isRealtime, isTrue);
    });

    test('search lists nearby stops within radius even when there are no departures at that time', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fakeApi = _NoDeparturesDigitransitClient();
      final s = Services(
        api: fakeApi,
        hfp: HfpService(),
        location: LocationService(),
        repo: FavoritesRepository(prefs),
      );
      final l = LocationController(s);
      final st = SettingsController(s)..setNearbyRadius(350);
      final ctrl = NearbyController(s, l, st);

      await ctrl.search();

      expect(fakeApi.lastRadius, equals(350));
      expect(ctrl.results.length, equals(2));
      expect(ctrl.results[0].stop.name, equals('Lasipalatsi'));
      expect(ctrl.results[0].departures, isEmpty);
      expect(ctrl.results[0].stop.routes.first.shortName, equals('9'));
    });

    test('Departure.fromJson handles String directionId from Digitransit GraphQL', () {
      final dep = Departure.fromJson({
        'serviceDay': 1700000000,
        'scheduledDeparture': 3600,
        'realtimeDeparture': 3660,
        'realtime': true,
        'realtimeState': 'UPDATED',
        'headsign': '',
        'trip': {
          'gtfsId': 'HSL:1009_1',
          'directionId': '1', // String in Digitransit GTFS GraphQL
          'tripHeadsign': 'Ilmala - Länsisatama',
          'route': {
            'gtfsId': 'HSL:1009',
            'shortName': '9',
            'longName': 'Ilmala - Länsisatama',
            'mode': 'TRAM',
          },
        },
      });
      expect(dep.directionId, equals(1));
      expect(dep.line, equals('9'));
      expect(dep.headsign, equals('Ilmala'));
    });

    test('selectStop loads departures and adds stop to results when tapped from map pattern', () async {
      final fakeApi = _FakePatternStopClient();
      final s = Services(
        api: fakeApi,
        hfp: HfpService(),
        location: LocationService(),
        repo: services.repo,
      );
      final l = LocationController(s);
      final st = SettingsController(s);
      final ctrl = NearbyController(s, l, st);

      const patternStop = Stop(
        gtfsId: 'HSL:1099999',
        name: 'Kaivokatu',
        position: LatLng(60.170, 24.940),
        mode: TransitMode.tram,
      );

      // Initially results are empty
      expect(ctrl.results, isEmpty);

      // Selecting the stop from map
      await ctrl.selectStop(patternStop);

      expect(ctrl.selectedStop?.gtfsId, equals('HSL:1099999'));
      expect(ctrl.results.length, equals(1));
      expect(ctrl.results.first.stop.name, equals('Kaivokatu'));
      expect(ctrl.results.first.departures.length, equals(1));
      expect(ctrl.results.first.departures.first.line, equals('9'));
      expect(ctrl.results.first.departures.first.headsign, equals('Länsisatama'));
    });

    test('resolveDestinationHeadsign splits two-way general route names into single destination', () {
      // direction 0 -> last endpoint (Länsisatama)
      expect(
        resolveDestinationHeadsign(routeLongName: 'Ilmala - Länsisatama', directionId: 0),
        equals('Länsisatama'),
      );
      // direction 1 -> first endpoint (Ilmala)
      expect(
        resolveDestinationHeadsign(routeLongName: 'Ilmala - Länsisatama', directionId: 1),
        equals('Ilmala'),
      );
      // with slash delimiter
      expect(
        resolveDestinationHeadsign(routeLongName: 'Kamppi / Lauttasaari', directionId: 0),
        equals('Lauttasaari'),
      );
    });

    test('selectStop refreshes departures even when stop already has existing departures', () async {
      final fakeApi = _FakeDynamicStopClient();
      final s = Services(
        api: fakeApi,
        hfp: HfpService(),
        location: LocationService(),
        repo: services.repo,
      );
      final l = LocationController(s);
      final st = SettingsController(s);
      final ctrl = NearbyController(s, l, st);

      const stop = Stop(
        gtfsId: 'HSL:1010101',
        name: 'Rautatieasema',
        position: LatLng(60.171, 24.941),
        mode: TransitMode.tram,
      );

      // Pre-fill results with old departure
      ctrl.results = [
        NearbyStop(stop, [
          Departure(
            line: '9',
            mode: TransitMode.tram,
            headsign: 'Vanha lähtö',
            scheduled: DateTime.now(),
            realtime: DateTime.now(),
            isRealtime: false,
          ),
        ]),
      ];

      expect(ctrl.results.first.departures.first.headsign, equals('Vanha lähtö'));

      // Clicking stop refreshes departures from API
      await ctrl.selectStop(stop);

      expect(ctrl.results.first.departures.first.headsign, equals('Tuore päivitetty lähtö'));
    });

    test('selectStop with fetchDepartures: false activates stop on map without querying API', () async {
      final fakeApi = _FakeDynamicStopClient();
      final s = Services(
        api: fakeApi,
        hfp: HfpService(),
        location: LocationService(),
        repo: services.repo,
      );
      final l = LocationController(s);
      final st = SettingsController(s);
      final ctrl = NearbyController(s, l, st);

      const stop1 = Stop(
        gtfsId: 'HSL:1010101',
        name: 'Rautatieasema',
        position: LatLng(60.171, 24.941),
        mode: TransitMode.tram,
      );
      const stop2 = Stop(
        gtfsId: 'HSL:1010102',
        name: 'Kamppi',
        position: LatLng(60.169, 24.938),
        mode: TransitMode.bus,
      );

      ctrl.results = [
        NearbyStop(stop1, const []),
        NearbyStop(stop2, const []),
      ];

      // Clicking from list (fetchDepartures: false) activates stop on map without querying API or reordering
      await ctrl.selectStop(stop2, fetchDepartures: false);
      expect(ctrl.selectedStopId, equals('HSL:1010102'));
      expect(fakeApi.callCount, equals(0));
      expect(ctrl.results.first.stop.gtfsId, equals('HSL:1010101'));

      // Clicking from map (fetchDepartures: true) queries API and moves stop to top of list repeatedly
      await ctrl.selectStop(stop2, fetchDepartures: true);
      expect(ctrl.selectedStopId, equals('HSL:1010102'));
      expect(fakeApi.callCount, equals(1));
      expect(ctrl.results.first.stop.gtfsId, equals('HSL:1010102'));
      expect(ctrl.results.first.departures.length, equals(1));

      await ctrl.selectStop(stop1, fetchDepartures: true);
      expect(ctrl.selectedStopId, equals('HSL:1010101'));
      expect(fakeApi.callCount, equals(2));
      expect(ctrl.results.first.stop.gtfsId, equals('HSL:1010101'));
      expect(ctrl.results.first.departures.length, equals(1));
    });
  });
}

class _NoDeparturesDigitransitClient extends DigitransitClient {
  int? lastRadius;

  @override
  Future<List<Stop>> stopsByRadius(LatLng c, int radius, {int max = 100}) async {
    lastRadius = radius;
    return [
      Stop.fromJson({
        'gtfsId': 'HSL:1020450',
        'name': 'Lasipalatsi',
        'code': 'H0401',
        'vehicleMode': 'TRAM',
        'lat': 60.1695,
        'lon': 24.9365,
        'routes': [
          {
            'gtfsId': 'HSL:1009',
            'shortName': '9',
            'longName': 'Ilmala - Länsisatama',
            'mode': 'TRAM',
          },
        ],
      }, distance: 120),
      Stop.fromJson({
        'gtfsId': 'HSL:1020102',
        'name': 'Kamppi',
        'code': 'H1201',
        'vehicleMode': 'BUS',
        'lat': 60.1688,
        'lon': 24.9320,
      }, distance: 280),
    ];
  }

  @override
  Future<Map<String, List<Departure>>> departuresForStops(
    List<String> ids, {
    int count = 3,
  }) async {
    // Ei vuoroja kyseisenä ajankohtana (esim. yöaika)
    return {for (final id in ids) id: const []};
  }
}

class _FakePatternStopClient extends DigitransitClient {
  @override
  Future<List<Departure>> departures(String stopId, {int count = 10}) async {
    return [
      Departure.fromJson({
        'serviceDay': 1700000000,
        'scheduledDeparture': 3600,
        'realtimeDeparture': 3600,
        'realtime': true,
        'realtimeState': 'SCHEDULED',
        'headsign': 'Länsisatama',
        'trip': {
          'gtfsId': 'HSL:1009_2',
          'directionId': 0,
          'tripHeadsign': 'Länsisatama',
          'route': {
            'gtfsId': 'HSL:1009',
            'shortName': '9',
            'longName': 'Ilmala - Länsisatama',
            'mode': 'TRAM',
          },
        },
      }),
    ];
  }
}

class _FakeDynamicStopClient extends DigitransitClient {
  int callCount = 0;

  @override
  Future<List<Departure>> departures(String stopId, {int count = 10}) async {
    callCount++;
    return [
      Departure(
        line: '9',
        mode: TransitMode.tram,
        headsign: 'Tuore päivitetty lähtö',
        scheduled: DateTime.now(),
        realtime: DateTime.now(),
        isRealtime: true,
      ),
    ];
  }
}
