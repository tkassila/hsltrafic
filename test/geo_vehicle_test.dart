import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:hsltrafic/core/geo.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/models/vehicle.dart';
import 'package:hsltrafic/shared/mode_style.dart';

void main() {
  group('Geo Utilities', () {
    test('distanceMeters calculates reasonable distances', () {
      const p1 = LatLng(60.1699, 24.9384); // Kamppi
      const p2 = LatLng(60.1719, 24.9414); // Central station
      final d = distanceMeters(p1, p2);
      expect(d, greaterThan(200));
      expect(d, lessThan(600));
    });

    test('hfpCells returns valid geohash prefixes for Helsinki center', () {
      const p = LatLng(60.1699, 24.9384);
      final cells = hfpCells(p, 1000);
      expect(cells, isNotEmpty);
      expect(cells.first, startsWith('60;24'));
    });

    test('isInGreaterHelsinki boundary check', () {
      expect(isInGreaterHelsinki(const LatLng(60.17, 24.94)), isTrue);
      expect(isInGreaterHelsinki(const LatLng(61.50, 23.77)), isFalse); // Tampere
    });

    test('decodePolyline decodes standard encoded polyline', () {
      // Small test line: 38.5, -120.2 to 40.7, -120.95
      const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final pts = decodePolyline(encoded);
      expect(pts.length, equals(3));
      expect(pts.first.latitude, closeTo(38.5, 0.01));
    });

    test('interpolateAlongPolyline follows road curves instead of cutting across city blocks', () {
      // L-muotoinen tie, joka kiertää korttelin kulman (60.205, 24.940) kautta:
      const startStop = LatLng(60.200, 24.940);
      const corner = LatLng(60.205, 24.940);
      const endStop = LatLng(60.205, 24.950);
      const road = [startStop, corner, endStop];

      final mid = interpolateAlongPolyline(road, startStop, endStop, 0.5);
      // Puolivälissä matkaa ajoneuvon on oltava tien kulmassa (lähellä 60.205, 24.940),
      // eikä oikaistava suoraan korttelin talojen läpi pisteessä (60.2025, 24.945)!
      expect(distanceMeters(mid.point, corner), lessThan(15.0));
      expect(distanceToPolyline(mid.point, road), lessThan(5.0));
    });

    test('snapToPolyline pulls off-road GPS coordinates onto the road centerline', () {
      const road = [
        LatLng(60.200, 24.940),
        LatLng(60.205, 24.940),
      ];
      // Piste ~28 metriä tiestä sivuun korttelin talojen päällä
      const offRoad = LatLng(60.2025, 24.9405);
      final snapped = snapToPolyline(offRoad, road, maxDistanceMeters: 60.0);
      expect(snapped, isNotNull);
      expect(snapped!.point.longitude, closeTo(24.940, 1e-5));
      expect(snapped.point.latitude, closeTo(60.2025, 1e-4));
    });
  });

  group('Vehicle Model HFP parsing', () {
    test('Vehicle.fromHfp correctly parses VP MQTT topic and payload', () {
      const topic = '/hfp/v2/journey/ongoing/vp/bus/0055/01216/1069/1/Malmi/07:20/1130106/2/60;24/19/73/44';
      final payload = {
        'VP': {
          'desi': '69',
          'dir': '1',
          'oper': 55,
          'veh': 1216,
          'tst': '2026-10-28T07:25:00Z',
          'spd': 12.5, // m/s = 45 km/h
          'hdg': 180,
          'lat': 60.182,
          'long': 24.951,
          'dl': -30, // -30 early = 30s late
          'oday': '2026-10-28',
          'start': '07:20',
        }
      };

      final vehicle = Vehicle.fromHfp(topic, payload);
      expect(vehicle, isNotNull);
      expect(vehicle!.line, equals('69'));
      expect(vehicle.mode, equals(TransitMode.bus));
      expect(vehicle.headsign, equals('Malmi'));
      expect(vehicle.delaySeconds, equals(30));
      expect(vehicle.speedKmh, closeTo(45.0, 0.5));
      expect(vehicle.heading, equals(180));
    });

    test('isStale allows standing/terminus vehicles to stay on map for up to 10 minutes', () {
      final now = DateTime.now();

      // Liikkuva ajoneuvo (45 km/h)
      final movingVehicle = Vehicle(
        id: '1/100',
        line: '9',
        routeGtfsId: 'HSL:1009',
        direction: 1,
        mode: TransitMode.tram,
        position: const LatLng(60.18, 24.94),
        updatedAt: now.subtract(const Duration(seconds: 90)),
        speedKmh: 35.0,
        nextStopId: 'HSL:1020',
      );
      // 90 sekunnin jälkeen liikkuva ei ole vielä vanhentunut (120 s raja)
      expect(movingVehicle.isStale(now), isFalse);
      // 130 sekunnin jälkeen liikkuva on vanhentunut
      expect(movingVehicle.isStale(now.add(const Duration(seconds: 45))), isTrue);

      // Päätepysäkillä seisova ajoneuvo (nopeus 0 km/h, odottamassa seuraavaa vuoroa)
      final terminusVehicle = Vehicle(
        id: '1/101',
        line: '9',
        routeGtfsId: 'HSL:1009',
        direction: 1,
        mode: TransitMode.tram,
        position: const LatLng(60.205, 24.921), // Ilmala
        updatedAt: now.subtract(const Duration(minutes: 5)), // Seissyt jo 5 minuuttia
        speedKmh: 0.0,
        nextStopId: null, // Päätepysäkki EOL
      );
      // 5 minuutin kohdalla EI OLE vanhentunut (toisin kuin vanhalla 60 s rajalla)
      expect(terminusVehicle.isStale(now), isFalse);
      // 9 minuutin kohdalla yhä kartalla
      expect(terminusVehicle.isStale(now.add(const Duration(minutes: 4))), isFalse);
      // Vasta 10 minuutin (600 s) jälkeen vanhenee
      expect(terminusVehicle.isStale(now.add(const Duration(minutes: 6))), isTrue);
    });

    test('Päätepysäkillä seisova ajoneuvo (nopeus 0 km/h) ei näy "21 min etuajassa" vaan "Lähtöön 21 min"', () {
      // 1) Ajoneuvo, jolla secondsUntilDeparture on 1260 s (21 min) ja nopeus 0 km/h
      final waitingTerminus = Vehicle(
        id: '1/600',
        line: '600',
        routeGtfsId: 'HSL:4600',
        direction: 0,
        mode: TransitMode.bus,
        position: const LatLng(60.171, 24.941), // Rautatientori
        updatedAt: DateTime.now(),
        speedKmh: 0.0,
        secondsUntilDeparture: 1260,
      );
      expect(waitingTerminus.isWaitingForDeparture, isTrue);
      expect(waitingTerminus.minutesUntilDeparture, equals(21));
      expect(vehicleStatusText(waitingTerminus), equals('Lähtöön 21 min'));

      // 2) delayText suodattaa myös suuret negatiiviset viiveet (esim. -1260 s = -21 min) -> "Lähtöön 21 min"
      expect(delayText(-1260), equals('Lähtöön 21 min'));

      // Pieni etuajassaolo reitillä (esim. 60 s = 1 min) näytetään normaalisti
      expect(delayText(-60), equals('1 min etuajassa'));
      expect(delayText(0), equals('Aikataulussa'));
      expect(delayText(180), equals('+3 min myöhässä'));
    });

    test('Liikkeessä olevalle vuorolle näytetään kulkusuuntanuoli vuororenkaan eteen, mutta päätepysäkillä ja 0 km/h seisovalle nuolta ei näytetä', () {
      final now = DateTime.now();

      // 1) Liikkeessä oleva bussi (nopeus 35 km/h, heading 90 astetta)
      final movingVehicle = Vehicle(
        id: '1/600',
        line: '600',
        routeGtfsId: 'HSL:4600',
        direction: 0,
        mode: TransitMode.bus,
        position: const LatLng(60.20, 24.95),
        updatedAt: now,
        speedKmh: 35.0,
        heading: 90,
        nextStopId: 'HSL:1234',
      );
      expect(movingVehicle.showHeadingArrow, isTrue);

      // 2) Päätepysäkillä lähtöä odottava bussi (nopeus 0 km/h, lähtöön 21 min) -> ei nuolta
      final waitingTerminus = Vehicle(
        id: '2/600',
        line: '600',
        routeGtfsId: 'HSL:4600',
        direction: 0,
        mode: TransitMode.bus,
        position: const LatLng(60.171, 24.941),
        updatedAt: now,
        speedKmh: 0.0,
        heading: 180,
        secondsUntilDeparture: 1260,
      );
      expect(waitingTerminus.isWaitingForDeparture, isTrue);
      expect(waitingTerminus.showHeadingArrow, isFalse);

      // 3) Päätepysäkillä seisova ajoneuvo ilman seuraavaa pysäkkiä ja nopeus 0 km/h -> ei nuolta
      final eolVehicle = Vehicle(
        id: '3/9',
        line: '9',
        routeGtfsId: 'HSL:1009',
        direction: 1,
        mode: TransitMode.tram,
        position: const LatLng(60.205, 24.921),
        updatedAt: now,
        speedKmh: 0.0,
        heading: 270,
        nextStopId: null,
      );
      expect(eolVehicle.showHeadingArrow, isFalse);
    });
  });
}
