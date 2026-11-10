import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/models/vehicle.dart';
import 'package:hsltrafic/shared/occupancy_dialog.dart';
import 'package:latlong2/latlong.dart';

class _FakeOccupancyClient extends DigitransitClient {
  String? returnStatus;
  int callCount = 0;

  _FakeOccupancyClient([this.returnStatus]);

  @override
  Future<String?> tripOccupancy(String tripGtfsId) async {
    callCount++;
    return returnStatus;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Departure occupancy model tests', () {
    test('Departure.fromJson correctly parses occupancy { occupancyStatus } from GraphQL', () {
      final json = {
        'serviceDay': 1700000000,
        'scheduledDeparture': 3600,
        'realtimeDeparture': 3660,
        'realtime': true,
        'realtimeState': 'UPDATED',
        'headsign': 'Kamppi',
        'trip': {
          'gtfsId': 'HSL:1009_1',
          'directionId': '0',
          'tripHeadsign': 'Kamppi',
          'occupancy': {
            'occupancyStatus': 'FEW_SEATS_AVAILABLE',
          },
          'route': {
            'gtfsId': 'HSL:1009',
            'shortName': '9',
            'mode': 'TRAM',
          },
        },
      };

      final dep = Departure.fromJson(json);
      expect(dep.line, equals('9'));
      expect(dep.tripGtfsId, equals('HSL:1009_1'));
      expect(dep.occupancyStatus, equals('FEW_SEATS_AVAILABLE'));
      expect(dep.hasOccupancy, isTrue);
      expect(dep.occupancyDescription, equals('Vähän istumapaikkoja vapaana'));
      expect(dep.occupancyColor, equals(const Color(0xFFF57C00)));
      expect(dep.occupancyIcon, equals(Icons.person_rounded));
    });

    test('Departure occupancy status descriptions and colors match HSL guidelines', () {
      final now = DateTime.now();

      final dMany = Departure(
        line: '550',
        mode: TransitMode.bus,
        headsign: 'Itäkeskus',
        scheduled: now,
        realtime: now,
        isRealtime: true,
        occupancyStatus: 'MANY_SEATS_AVAILABLE',
      );
      expect(dMany.hasOccupancy, isTrue);
      expect(dMany.occupancyDescription, equals('Paljon istumapaikkoja vapaana'));
      expect(dMany.occupancyColor, equals(const Color(0xFF2E7D32)));

      final dStanding = Departure(
        line: '550',
        mode: TransitMode.bus,
        headsign: 'Itäkeskus',
        scheduled: now,
        realtime: now,
        isRealtime: true,
        occupancyStatus: 'STANDING_ROOM_ONLY',
      );
      expect(dStanding.hasOccupancy, isTrue);
      expect(dStanding.occupancyDescription, equals('Vain seisomapaikkoja'));

      final dFull = Departure(
        line: '550',
        mode: TransitMode.bus,
        headsign: 'Itäkeskus',
        scheduled: now,
        realtime: now,
        isRealtime: true,
        occupancyStatus: 'FULL',
      );
      expect(dFull.hasOccupancy, isTrue);
      expect(dFull.occupancyDescription, equals('Täynnä'));
      expect(dFull.occupancyColor, equals(const Color(0xFFD32F2F)));

      final dNoData = Departure(
        line: '550',
        mode: TransitMode.bus,
        headsign: 'Itäkeskus',
        scheduled: now,
        realtime: now,
        isRealtime: false,
      );
      expect(dNoData.hasOccupancy, isFalse);
      expect(dNoData.occupancyDescription, equals('Kuormitustietoa ei saatavilla'));
    });

    test('Departure handles percentage-based occupancy from HFP occu', () {
      final now = DateTime.now();
      final d = Departure(
        line: '550',
        mode: TransitMode.bus,
        headsign: 'Itäkeskus',
        scheduled: now,
        realtime: now,
        isRealtime: true,
        occupancyPercentage: 25,
      );
      expect(d.hasOccupancy, isTrue);
      expect(d.occupancyDescription, equals('Paljon tilaa (25 %)'));
      expect(d.occupancyColor, equals(const Color(0xFF2E7D32)));
    });
  });

  group('showDepartureOccupancySheet UI widget tests', () {
    testWidgets('Displays occupancy bottom sheet with status and APC notice', (tester) async {
      final now = DateTime.now();
      final dep = Departure(
        line: '9',
        mode: TransitMode.tram,
        headsign: 'Länsiterminaali',
        tripGtfsId: 'HSL:1009_TRIP1',
        scheduled: now,
        realtime: now,
        isRealtime: true,
        occupancyStatus: 'MANY_SEATS_AVAILABLE',
      );
      const stop = Stop(
        gtfsId: 'HSL:1010101',
        name: 'Rautatieasema',
        code: '0301',
        position: LatLng(60.171, 24.941),
        mode: TransitMode.tram,
      );

      final fakeClient = _FakeOccupancyClient('MANY_SEATS_AVAILABLE');
      final vehicle = Vehicle(
        id: '12/9901',
        line: '9',
        routeGtfsId: 'HSL:1009',
        direction: 0,
        mode: TransitMode.tram,
        position: const LatLng(60.171, 24.941),
        updatedAt: now,
        tripGtfsId: 'HSL:1009_TRIP1',
        occupancy: 20,
      );

      bool alarmCallbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDepartureOccupancySheet(
                    ctx,
                    departure: dep,
                    stop: stop,
                    client: fakeClient,
                    liveVehicles: [vehicle],
                    onSetAlarm: () => alarmCallbackCalled = true,
                  );
                },
                child: const Text('Avaa kuormitus'),
              ),
            ),
          ),
        ),
      );

      // Open bottom sheet
      await tester.tap(find.text('Avaa kuormitus'));
      await tester.pumpAndSettle();

      // Check title and details
      expect(find.text('Vuoron kuormitustieto (täyttöaste)'), findsOneWidget);
      expect(find.text('Länsiterminaali'), findsOneWidget);
      expect(find.text('Rautatieasema (0301)'), findsOneWidget);
      expect(find.text('Paljon istumapaikkoja vapaana'), findsOneWidget);
      expect(find.textContaining('automaattisilla matkustajalaskureilla'), findsOneWidget);
      expect(find.textContaining('Reaaliaikainen ajoneuvo: 12/9901'), findsOneWidget);
      expect(find.textContaining('Kuormitus 20 %'), findsOneWidget);

      // Tap alarm button
      expect(find.text('Aseta lähtöhälytys'), findsOneWidget);
      await tester.tap(find.text('Aseta lähtöhälytys'));
      await tester.pumpAndSettle();

      expect(alarmCallbackCalled, isTrue);
    });
  });
}

