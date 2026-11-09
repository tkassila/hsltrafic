import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/models/line.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/models/vehicle.dart';
import 'package:hsltrafic/state/app_state.dart';
import 'package:hsltrafic/state/live_map_controller.dart';

class _MockHfpService extends HfpService {
  final _controller = StreamController<List<Vehicle>>.broadcast();
  Set<String> lastRouteIds = const {};
  bool lastRouteOnly = false;
  double lastRadius = 0;

  @override
  Stream<List<Vehicle>> get stream => _controller.stream;

  void emit(List<Vehicle> vehicles) => _controller.add(vehicles);

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

class _MockDigitransitClient extends DigitransitClient {
  int? requestedRadius;
  List<LineInfo> mockedRoutesNear = [];
  List<LineInfo> mockedLineSearch = [];
  final List<String> searchedNames = [];
  Map<String, LineInfo> mockedRoutesWithPatterns = {};
  Map<String, List<TripStopTime>> mockedTripTimes = {};
  Map<String, List<TripStopTime>> mockedTripTimesById = {};
  List<Vehicle> mockedVehiclesForRoutes = [];

  @override
  Future<List<LineInfo>> routesNear(LatLng c, {int radius = 5000, int maxStops = 120}) async {
    requestedRadius = radius;
    return mockedRoutesNear;
  }

  @override
  Future<List<Vehicle>> vehiclesForRoutes(Iterable<String> routeGtfsIds) async {
    return mockedVehiclesForRoutes;
  }

  @override
  Future<List<TripStopTime>> tripStopTimesById(String tripGtfsId) async {
    return mockedTripTimesById[tripGtfsId] ?? const [];
  }

  @override
  Future<List<LineInfo>> searchLines(String name) async {
    searchedNames.add(name);
    return mockedLineSearch;
  }

  @override
  Future<LineInfo?> routeWithPatterns(String gtfsId) async {
    return mockedRoutesWithPatterns[gtfsId];
  }

  @override
  Future<List<TripStopTime>> tripStopTimes({
    required String routeGtfsId,
    required int direction,
    required String date,
    required String startTime,
  }) async {
    return mockedTripTimes['$routeGtfsId:$direction'] ?? const [];
  }
}

void main() {
  late _MockHfpService fakeHfp;
  late _MockDigitransitClient fakeApi;
  late Services services;
  late LiveMapController controller;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeHfp = _MockHfpService();
    fakeApi = _MockDigitransitClient();
    services = Services(
      api: fakeApi,
      hfp: fakeHfp,
      location: LocationService(),
      repo: FavoritesRepository(prefs),
    );
    controller = LiveMapController(services);
  });

  tearDown(() {
    controller.dispose();
  });

  group('LiveMapController 5km and line search requirements', () {
    test('1) Tyhjä haku hakee 5km etäisyydeltä ja suodattaa ajoneuvot 5km säteelle', () async {
      final center = const LatLng(60.1699, 24.9384); // Kamppi
      controller.setArea(center, 5000, force: true);

      fakeApi.mockedRoutesNear = [
        const LineInfo(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala - Länsisatama', mode: TransitMode.tram),
        const LineInfo(gtfsId: 'HSL:1004', shortName: '4', longName: 'Katajanokka - Munkkiniemi', mode: TransitMode.tram),
      ];

      await controller.start();

      // Varmistetaan että kysely tehtiin 5km säteellä
      expect(fakeApi.requestedRadius, equals(5000));
      expect(fakeHfp.lastRadius, equals(5000));
      expect(fakeHfp.lastRouteOnly, isFalse);
      expect(fakeHfp.lastRouteIds, containsAll(['1009', '1004']));

      // Ajoneuvo 1: 1.5 km päässä keskustasta (Pasila) -> hyväksytään
      final v1 = Vehicle(
        id: '9_1',
        line: '9',
        direction: 1,
        position: const LatLng(60.182, 24.945),
        headsign: 'Ilmala',
        speedKmh: 25,
        heading: 0,
        delaySeconds: 10,
        mode: TransitMode.tram,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009',
      );

      // Ajoneuvo 2: 12 km päässä keskustasta (Espoon Kivenlahti) -> suodatetaan pois tyhjällä haulla
      final v2 = Vehicle(
        id: '9_2',
        line: '9',
        direction: 1,
        position: const LatLng(60.150, 24.640),
        headsign: 'Ilmala',
        speedKmh: 30,
        heading: 0,
        delaySeconds: 0,
        mode: TransitMode.tram,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009',
      );

      fakeHfp.emit([v1, v2]);
      await Future.delayed(const Duration(milliseconds: 20));

      final displayed = controller.vehicles;
      expect(displayed.length, equals(1));
      expect(displayed.first.id, equals('9_1'));
    });

    test('2) Tietyn linjan haku (esim. 9) hakee kaikkialta ja miltä tahansa etäisyydeltä', () async {
      fakeApi.mockedLineSearch = [
        const LineInfo(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala - Länsisatama', mode: TransitMode.tram),
      ];

      await controller.search('9');

      // Linjahaussa ei rajoiteta säteeseen, vaan tilataan reitti koko reitin laajuudelta
      expect(fakeHfp.lastRouteOnly, isTrue);
      expect(fakeHfp.lastRouteIds, contains('1009'));

      // Ajoneuvo kaukana (15 km Kamppista)
      final farVehicle = Vehicle(
        id: '9_far',
        line: '9',
        direction: 1,
        position: const LatLng(60.28, 24.95), // Vantaa
        headsign: 'Ilmala',
        speedKmh: 40,
        heading: 180,
        delaySeconds: 0,
        mode: TransitMode.tram,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009',
      );

      fakeHfp.emit([farVehicle]);
      await Future.delayed(const Duration(milliseconds: 20));

      final displayed = controller.vehicles;
      expect(displayed.length, equals(1));
      expect(displayed.first.id, equals('9_far'));
    });

    test('3) Linja 9 Ilmalassa: seuraava pysäkki ei ole alkupään Jätkäsaari vaan todellinen seuraava pysäkki', () async {
      // Reittikuvio suuntaan Ilmala (direction 1)
      final jatkasaari = const Stop(gtfsId: 'HSL:1010', code: '0010', name: 'Jätkäsaari', position: LatLng(60.158, 24.919));
      final pasila = const Stop(gtfsId: 'HSL:1020', code: '0020', name: 'Pasilan asema', position: LatLng(60.198, 24.933));
      final ilmala = const Stop(gtfsId: 'HSL:1030', code: '0030', name: 'Ilmalan tori', position: LatLng(60.205, 24.921));

      final patternToIlmala = LinePattern(
        code: '1009:1',
        directionId: 1,
        headsign: 'Ilmala',
        geometry: const [],
        stops: [jatkasaari, pasila, ilmala],
      );

      // Paluusuunnan reittikuvio (direction 0)
      final patternToJatkasaari = LinePattern(
        code: '1009:2',
        directionId: 0,
        headsign: 'Jätkäsaari',
        geometry: const [],
        stops: [ilmala, pasila, jatkasaari],
      );

      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = LineInfo(
        gtfsId: 'HSL:1009',
        shortName: '9',
        longName: 'Ilmala - Länsisatama',
        mode: TransitMode.tram,
        patterns: [patternToIlmala, patternToJatkasaari],
      );

      final now = DateTime.now();
      // TripStopTimes matkalle Jätkäsaaresta Ilmalaan (direction 1)
      fakeApi.mockedTripTimes['HSL:1009:1'] = [
        TripStopTime(jatkasaari, now.subtract(const Duration(minutes: 25)), now.subtract(const Duration(minutes: 25))),
        TripStopTime(pasila, now.subtract(const Duration(minutes: 2)), now.subtract(const Duration(minutes: 2))),
        TripStopTime(ilmala, now.add(const Duration(minutes: 3)), now.add(const Duration(minutes: 3))),
      ];

      // Ajoneuvo 9 on Ilmalassa Pasilan jälkeen
      final vIlmala = Vehicle(
        id: '9_ilmala',
        line: '9',
        direction: 1,
        position: const LatLng(60.202, 24.925),
        headsign: 'Ilmala',
        speedKmh: 18,
        heading: 340,
        delaySeconds: 0,
        mode: TransitMode.tram,
        updatedAt: now,
        routeGtfsId: 'HSL:1009',
        operatingDay: '2026-11-07',
        startTime: '10:00',
        nextStopId: 'HSL:1030', // Ilmalan tori
      );

      fakeHfp.emit([vIlmala]);
      await Future<void>.delayed(Duration.zero);

      await controller.select(vIlmala);

      // Varmistetaan että valittu suunta on oikea (Ilmala) eikä Jätkäsaari
      expect(controller.selectedPattern?.headsign, equals('Ilmala'));

      // Seuraava pysäkki EI SAA OLLA Jätkäsaari, vaan Ilmalan tori!
      expect(controller.nextStopTime, isNotNull);
      expect(controller.nextStopTime!.stop.name, equals('Ilmalan tori'));
      expect(controller.nextStopTime!.stop.name, isNot(equals('Jätkäsaari')));
    });

    test('4) Linja 69 ja 69N ovat yhtä hyviä: haettaessa "69" näytetään molemmat linjat ja tilataan HFP molemmille', () async {
      fakeApi.mockedLineSearch = [
        const LineInfo(gtfsId: 'HSL:1069', shortName: '69', longName: 'Kamppi - Malmi', mode: TransitMode.bus),
        const LineInfo(gtfsId: 'HSL:1069N', shortName: '69N', longName: 'Rautatientori - Malmi', mode: TransitMode.bus),
      ];

      final v69 = Vehicle(
        id: 'bus_69',
        line: '69',
        direction: 1,
        position: const LatLng(60.22, 24.96),
        headsign: 'Malmi',
        speedKmh: 35,
        heading: 90,
        delaySeconds: 15,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1069',
      );

      final v69N = Vehicle(
        id: 'bus_69N',
        line: '69N',
        direction: 1,
        position: const LatLng(60.23, 24.97),
        headsign: 'Malmi via Oulunkylä',
        speedKmh: 42,
        heading: 90,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1069N',
      );

      final vOther = Vehicle(
        id: 'bus_550',
        line: '550',
        direction: 1,
        position: const LatLng(60.22, 24.90),
        headsign: 'Itäkeskus',
        speedKmh: 40,
        heading: 90,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:2550',
      );

      fakeHfp.emit([v69, v69N, vOther]);
      await Future<void>.delayed(Duration.zero);

      await controller.search('69');

      // Varmistetaan että HFP tilasi molemmat reitit (1069 ja 1069N)
      expect(fakeHfp.lastRouteIds, containsAll(['1069', '1069N']));
      expect(fakeHfp.lastRouteOnly, isTrue);

      // Molemmat ajoneuvot 69 ja 69N näkyvät hakutuloksissa, mutta ei muu linja
      final displayed = controller.vehicles;
      final lines = displayed.map((v) => v.line).toSet();
      expect(lines, containsAll(['69', '69N']));
      expect(lines, isNot(contains('550')));
    });

    test('5) Linja 69 ja 69N ovat yhtä hyviä: haettaessa "69N" haetaan Digitransitista myös runkoluku "69" ja näytetään molemmat linjat', () async {
      fakeApi.searchedNames.clear();
      fakeApi.mockedLineSearch = [
        const LineInfo(gtfsId: 'HSL:1069', shortName: '69', longName: 'Kamppi - Malmi', mode: TransitMode.bus),
        const LineInfo(gtfsId: 'HSL:1069N', shortName: '69N', longName: 'Rautatientori - Malmi', mode: TransitMode.bus),
      ];

      final v69 = Vehicle(
        id: 'bus_69',
        line: '69',
        direction: 1,
        position: const LatLng(60.22, 24.96),
        headsign: 'Malmi',
        speedKmh: 35,
        heading: 90,
        delaySeconds: 15,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1069',
      );

      final v69N = Vehicle(
        id: 'bus_69N',
        line: '69N',
        direction: 1,
        position: const LatLng(60.23, 24.97),
        headsign: 'Malmi via Oulunkylä',
        speedKmh: 42,
        heading: 90,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1069N',
      );

      fakeHfp.emit([v69, v69N]);
      await Future<void>.delayed(Duration.zero);

      await controller.search('69N');

      // Digitransit-haku tehtiin sekä syötteellä "69N" että runkonumerolla "69"
      expect(fakeApi.searchedNames, containsAll(['69N', '69']));

      // HFP tilaa molemmat
      expect(fakeHfp.lastRouteIds, containsAll(['1069', '1069N']));
      expect(fakeHfp.lastRouteOnly, isTrue);

      // Molemmat ajoneuvot 69 ja 69N löytyvät
      final displayed = controller.vehicles;
      final lines = displayed.map((v) => v.line).toSet();
      expect(lines, containsAll(['69', '69N']));
    });

    test('6) Pelkän numeron haku (esim. 9) hakee myös kirjainvariantit (9N), mutta ei vääriä linjoja kuten 90 tai 19', () async {
      fakeApi.searchedNames.clear();
      fakeApi.mockedLineSearch = [
        const LineInfo(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala - Länsisatama', mode: TransitMode.tram),
        const LineInfo(gtfsId: 'HSL:1009N', shortName: '9N', longName: 'Ilmala - Länsisatama yö', mode: TransitMode.bus),
        const LineInfo(gtfsId: 'HSL:2090', shortName: '90', longName: 'Vuosaari - Kallvikintie', mode: TransitMode.bus),
      ];

      final v9 = Vehicle(
        id: 'tram_9',
        line: '9',
        direction: 1,
        position: const LatLng(60.19, 24.93),
        headsign: 'Ilmala',
        speedKmh: 20,
        heading: 0,
        delaySeconds: 0,
        mode: TransitMode.tram,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009',
      );

      final v9N = Vehicle(
        id: 'bus_9N',
        line: '9N',
        direction: 1,
        position: const LatLng(60.18, 24.94),
        headsign: 'Ilmala',
        speedKmh: 30,
        heading: 0,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009N',
      );

      final v90 = Vehicle(
        id: 'bus_90',
        line: '90',
        direction: 1,
        position: const LatLng(60.20, 25.14),
        headsign: 'Vuosaari',
        speedKmh: 40,
        heading: 90,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:2090',
      );

      final v19 = Vehicle(
        id: 'ferry_19',
        line: '19',
        direction: 1,
        position: const LatLng(60.15, 24.98),
        headsign: 'Suomenlinna',
        speedKmh: 10,
        heading: 180,
        delaySeconds: 0,
        mode: TransitMode.ferry,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1019',
      );

      fakeHfp.emit([v9, v9N, v90, v19]);
      await Future<void>.delayed(Duration.zero);

      // Käyttäjä hakee pelkällä numerolla "9"
      await controller.search('9');

      // Varmistetaan että Digitransitista haettiin sekä "9" että yövariantti "9N"
      expect(fakeApi.searchedNames, containsAll(['9', '9N']));

      // HFP tilaa linjat 1009 ja 1009N
      expect(fakeHfp.lastRouteIds, containsAll(['1009', '1009N']));

      // Tuloksissa näkyvät 9 ja 9N, mutta EI 90 eikä 19
      final displayed = controller.vehicles;
      final lines = displayed.map((v) => v.line).toSet();
      expect(lines, containsAll(['9', '9N']));
      expect(lines, isNot(contains('90')));
      expect(lines, isNot(contains('19')));
    });

    test('7) Kirjainvariantin haku (esim. 9n pienellä) hakee myös perusnumeron (9), muttei vääriä linjoja kuten 90', () async {
      fakeApi.searchedNames.clear();
      fakeApi.mockedLineSearch = [
        const LineInfo(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala - Länsisatama', mode: TransitMode.tram),
        const LineInfo(gtfsId: 'HSL:1009N', shortName: '9N', longName: 'Ilmala - Länsisatama yö', mode: TransitMode.bus),
      ];

      final v9 = Vehicle(
        id: 'tram_9',
        line: '9',
        direction: 1,
        position: const LatLng(60.19, 24.93),
        headsign: 'Ilmala',
        speedKmh: 20,
        heading: 0,
        delaySeconds: 0,
        mode: TransitMode.tram,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009',
      );

      final v9N = Vehicle(
        id: 'bus_9N',
        line: '9N',
        direction: 1,
        position: const LatLng(60.18, 24.94),
        headsign: 'Ilmala',
        speedKmh: 30,
        heading: 0,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009N',
      );

      fakeHfp.emit([v9, v9N]);
      await Future<void>.delayed(Duration.zero);

      // Käyttäjä hakee syötteellä "9n"
      await controller.search('9n');

      expect(fakeApi.searchedNames, containsAll(['9N', '9']));
      expect(fakeHfp.lastRouteIds, containsAll(['1009', '1009N']));

      final displayed = controller.vehicles;
      final lines = displayed.map((v) => v.line).toSet();
      expect(lines, containsAll(['9', '9N']));
    });

    test('8) isLineMatching apufunktio testaa symmetrian ja etuliite/pääte-säännöt', () {
      // 9 ja 9N
      expect(isLineMatching('9', '9'), isTrue);
      expect(isLineMatching('9N', '9'), isTrue);
      expect(isLineMatching('9', '9N'), isTrue);
      expect(isLineMatching('9N', '9n'), isTrue);
      expect(isLineMatching('9B', '9'), isTrue);
      expect(isLineMatching('90', '9'), isFalse);
      expect(isLineMatching('19', '9'), isFalse);

      // 69 ja 69N
      expect(isLineMatching('69', '69'), isTrue);
      expect(isLineMatching('69N', '69'), isTrue);
      expect(isLineMatching('69', '69N'), isTrue);
      expect(isLineMatching('691', '69'), isFalse);

      // Metro M1 ja ratikka 1
      expect(isLineMatching('M1', 'M1'), isTrue);
      expect(isLineMatching('1', 'M1'), isFalse);
      expect(isLineMatching('M1', '1'), isFalse);
      expect(isLineMatching('M1', 'M'), isTrue);
      expect(isLineMatching('M2', 'M'), isTrue);

      // Juna P
      expect(isLineMatching('P', 'P'), isTrue);
      expect(isLineMatching('P', 'p'), isTrue);

      // Usean linjan samanaikainen haku (esim. "9, 69" tai "550 560")
      expect(isLineMatching('9', '9, 69'), isTrue);
      expect(isLineMatching('9N', '9, 69'), isTrue);
      expect(isLineMatching('69', '9, 69'), isTrue);
      expect(isLineMatching('69N', '9, 69'), isTrue);
      expect(isLineMatching('550', '9, 69'), isFalse);
      expect(isLineMatching('560', '550 560'), isTrue);
    });

    test('9) Usean linjan haku (esim. "9, 69"), recentSearches ja hakuvälimuisti toimivat', () async {
      fakeApi.searchedNames.clear();
      fakeApi.mockedLineSearch = [
        const LineInfo(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala - Länsisatama', mode: TransitMode.tram),
        const LineInfo(gtfsId: 'HSL:1069', shortName: '69', longName: 'Kamppi - Malmi', mode: TransitMode.bus),
      ];

      final v9 = Vehicle(
        id: 'tram_9',
        line: '9',
        direction: 1,
        position: const LatLng(60.19, 24.93),
        headsign: 'Ilmala',
        speedKmh: 20,
        heading: 45,
        delaySeconds: 0,
        mode: TransitMode.tram,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1009',
      );
      final v69N = Vehicle(
        id: 'bus_69N',
        line: '69N',
        direction: 1,
        position: const LatLng(60.22, 24.96),
        headsign: 'Malmi',
        speedKmh: 35,
        heading: 90,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:1069N',
      );
      final v550 = Vehicle(
        id: 'bus_550',
        line: '550',
        direction: 1,
        position: const LatLng(60.22, 24.90),
        headsign: 'Itäkeskus',
        speedKmh: 40,
        heading: 90,
        delaySeconds: 0,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:2550',
      );

      fakeHfp.emit([v9, v69N, v550]);
      await Future<void>.delayed(Duration.zero);

      await controller.search('9, 69');

      expect(controller.recentSearches.first, equals('9, 69'));
      expect(fakeHfp.lastRouteIds, containsAll(['1009', '1009N', '1069', '1069N']));

      final displayed = controller.vehicles.map((v) => v.line).toSet();
      expect(displayed, containsAll(['9', '69N']));
      expect(displayed, isNot(contains('550')));

      // Toistettu haku käyttää välimuistia eikä tee uusia API-kutsuja
      final countBefore = fakeApi.searchedNames.length;
      await controller.search('9, 69');
      expect(fakeApi.searchedNames.length, equals(countBefore));
    });

    test('10) Käpylän aseman lähijuna K (HSL:3001K): lähilinjanapin painallus tilaa 3001K, odottaa HFP-viestiä eikä väitä virheellisesti ettei vuoroja ole', () async {
      final kapyla = const LatLng(60.2150, 24.9460);
      controller.setArea(kapyla, 5000, force: true);

      fakeApi.mockedRoutesNear = [
        const LineInfo(gtfsId: 'HSL:3001K', shortName: 'K', longName: 'Helsinki - Kerava', mode: TransitMode.rail),
        const LineInfo(gtfsId: 'HSL:3001I', shortName: 'I', longName: 'Helsinki - Tikkurila - Lentoasema', mode: TransitMode.rail),
        const LineInfo(gtfsId: 'HSL:1069', shortName: '69', longName: 'Kamppi - Malmi', mode: TransitMode.bus),
      ];
      await controller.start();

      expect(controller.nearbyShortNames, containsAll(['K', 'I', '69']));

      // Kun käyttäjä painaa K-painiketta ja HFP-viesti on vasta matkalla:
      await controller.search('K');

      // 1) HFP tilasi oikean lähijunatunnuksen 3001K (eikä pelkkää "K")
      expect(fakeHfp.lastRouteIds, contains('3001K'));
      // 2) isAwaitingHfpVehicles on tosi, jotta käyttöliittymä näyttää "Haetaan..." eikä väitä ettei vuoroja ole
      expect(controller.isAwaitingHfpVehicles, isTrue);

      // 3) Kun K-junan HFP-viesti saapuu (sekä JORE-muoto 3001K että VP.desi "K" tunnistetaan)
      final kTrain = Vehicle.fromHfp(
        '/hfp/v2/journey/ongoing/vp/rail/0090/09001/3001K/1/Kerava/12:15/1200101/2/60;24/21/50/00',
        {
          'VP': {
            'desi': '3001K',
            'lat': 60.2145,
            'long': 24.9455,
            'spd': 15.0,
            'hdg': 10,
            'dl': 0,
            'oday': '2026-11-07',
          }
        },
      )!;
      expect(kTrain.line, equals('K'));
      expect(isLineMatching('3001K', 'K'), isTrue);

      fakeHfp.emit([kTrain]);
      await Future<void>.delayed(Duration.zero);

      // 4) Odotustila poistuu välittömästi ja K-juna näkyy kartalla
      expect(controller.isAwaitingHfpVehicles, isFalse);
      expect(controller.vehicles.length, equals(1));
      expect(controller.vehicles.first.line, equals('K'));
    });

    test('11) bussit-flutter-tyylinen Digitransit HTTPS GraphQL -paikannus näyttää vuorot ja pysäkkiajat vaikka MQTT-virta olisi tyhjä', () async {
      final now = DateTime.now();
      final oulunkyla = const Stop(
        gtfsId: 'HSL:1280501',
        code: '0501',
        name: 'Oulunkylän asema',
        position: LatLng(60.2285, 24.9680),
      );
      fakeApi.mockedVehiclesForRoutes = [
        Vehicle(
          id: 'gtfs:HSL:3001K_20261108_1',
          line: 'K',
          routeGtfsId: 'HSL:3001K',
          direction: 0,
          mode: TransitMode.rail,
          position: const LatLng(60.2150, 24.9460),
          heading: 35,
          speedKmh: 60,
          headsign: 'Kerava',
          nextStopId: 'HSL:1280501',
          tripGtfsId: 'HSL:3001K_20261108_1',
          updatedAt: now,
        ),
      ];
      fakeApi.mockedTripTimesById['HSL:3001K_20261108_1'] = [
        TripStopTime(oulunkyla, now.add(const Duration(minutes: 2)), now.add(const Duration(minutes: 2))),
      ];

      // Haetaan K-juna ilman yhtäkään HFP MQTT -viestiä
      await controller.search('K');

      expect(controller.isAwaitingHfpVehicles, isFalse);
      expect(controller.vehicles.length, equals(1));
      expect(controller.vehicles.first.line, equals('K'));
      expect(controller.vehicles.first.headsign, equals('Kerava'));

      // Valittaessa GraphQL-vuoro sen tulevat pysäkit haetaan tripStopTimesById-kyselyllä
      await controller.select(controller.vehicles.first);
      expect(controller.nextStopTime?.stop.name, equals('Oulunkylän asema'));
    });

    test('12) GraphQL-vuoron sijainti päivittyy ja liikkuu sulavasti edellisen (prev) ja seuraavan (next) pysäkin välillä ajan kuluessa', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final serviceDay = nowSec - 3600;
      // Pysäkki 1 (Pasila): lähtenyt 30 s sitten (3570)
      // Pysäkki 2 (Käpylä): saapuu 90 s päästä (3690)
      // Pysäkki 3 (Oulunkylä): saapuu 210 s päästä (3810)
      final client = DigitransitClient(
        keyProvider: () => 'test-key',
        client: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = body['query'] as String;
          if (q.contains('stopsByRadius')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'stopsByRadius': {
                    'edges': [
                      {
                        'node': {
                          'distance': 120,
                          'stop': {
                            'gtfsId': 'HSL:1250502',
                            'name': 'Käpylä',
                            'code': '0502',
                            'lat': 60.2150,
                            'lon': 24.9460,
                            'stoptimesWithoutPatterns': [
                              {
                                'headsign': 'Kerava',
                                'serviceDay': serviceDay,
                                'scheduledDeparture': 3690,
                                'realtimeDeparture': 3690,
                                'departureDelay': 0,
                                'realtime': true,
                                'trip': {
                                  'gtfsId': 'HSL:3001K_trip1',
                                  'directionId': '0',
                                  'tripHeadsign': 'Kerava',
                                  'route': {
                                    'gtfsId': 'HSL:3001K',
                                    'shortName': 'K',
                                    'longName': 'Helsinki - Kerava',
                                    'mode': 'RAIL',
                                  },
                                },
                              },
                            ],
                            'routes': [],
                          },
                        },
                      },
                    ],
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // Täyden matkan kysely t0: trip(id: ...)
          return http.Response(
            jsonEncode({
              'data': {
                't0': {
                  'gtfsId': 'HSL:3001K_trip1',
                  'directionId': '0',
                  'tripHeadsign': 'Kerava',
                  'route': {
                    'gtfsId': 'HSL:3001K',
                    'shortName': 'K',
                    'longName': 'Helsinki - Kerava',
                    'mode': 'RAIL',
                  },
                  'stoptimes': [
                    {
                      'serviceDay': serviceDay,
                      'scheduledArrival': 3540,
                      'realtimeArrival': 3540,
                      'scheduledDeparture': 3570,
                      'realtimeDeparture': 3570,
                      'departureDelay': 0,
                      'realtime': true,
                      'headsign': 'Kerava',
                      'stop': {
                        'gtfsId': 'HSL:1170501',
                        'name': 'Pasila',
                        'code': '0501',
                        'lat': 60.1985,
                        'lon': 24.9335,
                      },
                    },
                    {
                      'serviceDay': serviceDay,
                      'scheduledArrival': 3690,
                      'realtimeArrival': 3690,
                      'scheduledDeparture': 3710,
                      'realtimeDeparture': 3710,
                      'departureDelay': 0,
                      'realtime': true,
                      'headsign': 'Kerava',
                      'stop': {
                        'gtfsId': 'HSL:1250502',
                        'name': 'Käpylä',
                        'code': '0502',
                        'lat': 60.2150,
                        'lon': 24.9460,
                      },
                    },
                    {
                      'serviceDay': serviceDay,
                      'scheduledArrival': 3810,
                      'realtimeArrival': 3810,
                      'scheduledDeparture': 3830,
                      'realtimeDeparture': 3830,
                      'departureDelay': 0,
                      'realtime': true,
                      'headsign': 'Kerava',
                      'stop': {
                        'gtfsId': 'HSL:1280501',
                        'name': 'Oulunkylä',
                        'code': '0503',
                        'lat': 60.2285,
                        'lon': 24.9680,
                      },
                    },
                  ],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.routesNear(const LatLng(60.2150, 24.9460));
      final t1 = DateTime.fromMillisecondsSinceEpoch(nowSec * 1000);
      final t2 = t1.add(const Duration(seconds: 30));
      final t3 = t1.add(const Duration(seconds: 60));

      final vAtT1 = client.reinterpolateGraphqlVehicles(now: t1).first;
      final vAtT2 = client.reinterpolateGraphqlVehicles(now: t2).first;
      final vAtT3 = client.reinterpolateGraphqlVehicles(now: t3).first;

      // Juna liikkuu jatkuvasti pohjoiseen (Pasilasta 60.1985 -> Käpylään 60.2150),
      // eikä seiso paikallaan pysäkin koordinaatissa!
      expect(vAtT1.position.latitude, greaterThan(60.1985));
      expect(vAtT1.position.latitude, lessThan(60.2150));
      expect(vAtT2.position.latitude, greaterThan(vAtT1.position.latitude));
      expect(vAtT3.position.latitude, greaterThan(vAtT2.position.latitude));
      expect(vAtT3.position.latitude, lessThan(60.2150));
      expect(vAtT1.speedKmh, greaterThan(20));
    });

    test('13) Lähipysäkkien painonapeissa näytetään vain linjat, joilla on sillä hetkellä vuoroja, ja "Kaikkia" hakee kaikkien näiden linjojen live-vuorot', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final serviceDay = nowSec - 3600;
      final client = DigitransitClient(
        keyProvider: () => 'test-key',
        client: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = body['query'] as String;
          if (q.contains('stopsByRadius')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'stopsByRadius': {
                    'edges': [
                      {
                        'node': {
                          'distance': 100,
                          'stop': {
                            'gtfsId': 'HSL:1001',
                            'name': 'Rautatientori',
                            'code': '1001',
                            'lat': 60.1710,
                            'lon': 24.9410,
                            'stoptimesWithoutPatterns': [
                              // Linja 600: ajossa nyt (saapuu 2 min päästä)
                              {
                                'headsign': 'Lentoasema',
                                'serviceDay': serviceDay,
                                'scheduledDeparture': 3720,
                                'realtimeDeparture': 3720,
                                'departureDelay': 0,
                                'realtime': true,
                                'trip': {
                                  'gtfsId': 'HSL:4600_active',
                                  'directionId': '0',
                                  'tripHeadsign': 'Lentoasema',
                                  'route': {
                                    'gtfsId': 'HSL:4600',
                                    'shortName': '600',
                                    'longName': 'Rautatientori - Lentoasema',
                                    'mode': 'BUS',
                                  },
                                },
                              },
                              // Linja 999: lähtee vasta 40 min päästä päätepysäkiltään -> EI vielä ajossa!
                              {
                                'headsign': 'Kauklahti',
                                'serviceDay': serviceDay,
                                'scheduledDeparture': 6000,
                                'realtimeDeparture': 6000,
                                'departureDelay': 0,
                                'realtime': false,
                                'trip': {
                                  'gtfsId': 'HSL:4999_future',
                                  'directionId': '0',
                                  'tripHeadsign': 'Kauklahti',
                                  'route': {
                                    'gtfsId': 'HSL:4999',
                                    'shortName': '999',
                                    'longName': 'Helsinki - Kauklahti',
                                    'mode': 'BUS',
                                  },
                                },
                              },
                            ],
                            // Staattinen reitti 55, jolla ei ole yhtään lähtöä:
                            'routes': [
                              {
                                'gtfsId': 'HSL:1055',
                                'shortName': '55',
                                'longName': 'Rautatientori - Koskela',
                                'mode': 'BUS',
                              },
                            ],
                          },
                        },
                      },
                    ],
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'data': {}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final routes = await client.routesNear(const LatLng(60.1710, 24.9410));
      final shortNames = routes.map((r) => r.shortName).toList();
      // Vain linja 600 (jolla on vuoro ajossa nyt) on mukana; ei 999 (40 min päästä) eikä staattinen 55!
      expect(shortNames, equals(['600']));

      // Testataan "Kaikkia"-toimintoa LiveMapControllerissa:
      fakeApi.mockedRoutesNear = [
        const LineInfo(gtfsId: 'HSL:4600', shortName: '600', longName: 'Rautatientori - Lentoasema', mode: TransitMode.bus),
        const LineInfo(gtfsId: 'HSL:3001K', shortName: 'K', longName: 'Helsinki - Kerava', mode: TransitMode.rail),
      ];
      final v600 = Vehicle(
        id: 'bus_600',
        line: '600',
        direction: 0,
        position: const LatLng(60.290, 24.960), // Vantaalla (> 5 km päässä, mutta kuuluu 1-kohdan linjaan 600!)
        headsign: 'Lentoasema',
        speedKmh: 50,
        heading: 10,
        mode: TransitMode.bus,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:4600',
      );
      final vK = Vehicle(
        id: 'train_K',
        line: 'K',
        direction: 0,
        position: const LatLng(60.215, 24.946),
        headsign: 'Kerava',
        speedKmh: 60,
        heading: 20,
        mode: TransitMode.rail,
        updatedAt: DateTime.now(),
        routeGtfsId: 'HSL:3001K',
      );
      fakeHfp.emit([v600, vK]);
      await Future<void>.delayed(Duration.zero);

      // Ensin käyttäjä valitsee vain linjan 600:
      await controller.search('600');
      expect(controller.vehicles.map((v) => v.line).toList(), equals(['600']));

      // Sitten käyttäjä painaa "Kaikkia"-painonappia:
      await controller.searchAllNearbyLines();
      expect(controller.isAllNearbyLinesActive, isTrue);
      expect(controller.lineFilter, isEmpty);
      expect(controller.vehicles.map((v) => v.line).toSet(), containsAll(['600', 'K']));
    });

    test('14) Kun Digitransitin Trip.stoptimes palauttaa serviceDay: 0, linjan 600 vuorot ja 600-painonappi eivät katoa kartalta', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final serviceDay = nowSec - 3600;
      final client = DigitransitClient(
        keyProvider: () => 'test-key',
        client: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final q = body['query'] as String;
          if (q.contains('stopsByRadius')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'stopsByRadius': {
                    'edges': [
                      {
                        'node': {
                          'distance': 100,
                          'stop': {
                            'gtfsId': 'HSL:1250101',
                            'name': 'Käpylän asema',
                            'code': '2090',
                            'lat': 60.2150,
                            'lon': 24.9460,
                            'stoptimesWithoutPatterns': [
                              {
                                'headsign': 'Lentoasema',
                                'serviceDay': serviceDay,
                                'scheduledDeparture': 3660,
                                'realtimeDeparture': 3660,
                                'departureDelay': 0,
                                'realtime': true,
                                'trip': {
                                  'gtfsId': 'HSL:4600_night_trip',
                                  'directionId': '0',
                                  'tripHeadsign': 'Lentoasema',
                                  'route': {
                                    'gtfsId': 'HSL:4600',
                                    'shortName': '600',
                                    'longName': 'Rautatientori - Lentoasema',
                                    'mode': 'BUS',
                                  },
                                },
                              },
                            ],
                            'routes': [],
                          },
                        },
                      },
                    ],
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // Digitransitin oikea palvelin palauttaa Trip.stoptimes-kyselyssä serviceDay: 0!
          return http.Response(
            jsonEncode({
              'data': {
                't0': {
                  'gtfsId': 'HSL:4600_night_trip',
                  'directionId': '0',
                  'tripHeadsign': 'Lentoasema',
                  'route': {
                    'gtfsId': 'HSL:4600',
                    'shortName': '600',
                    'longName': 'Rautatientori - Lentoasema',
                    'mode': 'BUS',
                  },
                  'stoptimes': [
                    {
                      'serviceDay': 0,
                      'scheduledArrival': 3500,
                      'realtimeArrival': 3500,
                      'scheduledDeparture': 3500,
                      'realtimeDeparture': 3500,
                      'departureDelay': 0,
                      'realtime': true,
                      'headsign': 'Lentoasema',
                      'stop': {
                        'gtfsId': 'HSL:1001',
                        'name': 'Rautatientori',
                        'code': '1001',
                        'lat': 60.1710,
                        'lon': 24.9410,
                      },
                    },
                    {
                      'serviceDay': 0,
                      'scheduledArrival': 3660,
                      'realtimeArrival': 3660,
                      'scheduledDeparture': 3660,
                      'realtimeDeparture': 3660,
                      'departureDelay': 0,
                      'realtime': true,
                      'headsign': 'Lentoasema',
                      'stop': {
                        'gtfsId': 'HSL:1250101',
                        'name': 'Käpylän asema',
                        'code': '2090',
                        'lat': 60.2150,
                        'lon': 24.9460,
                      },
                    },
                  ],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final routes = await client.routesNear(const LatLng(60.2150, 24.9460));
      expect(routes.map((r) => r.shortName), contains('600'));
      expect(client.lastNearbyVehicles, isNotEmpty);

      // Seuraava 2 sekunnin interpolointitikki EI saa poistaa 600-vuoroa ("vuosi 1970" -bugin takia):
      final afterTick = client.reinterpolateGraphqlVehicles();
      expect(afterTick, isNotEmpty);
      expect(afterTick.first.line, equals('600'));
    });

    test('15) Vuoron seuraavista pysäkeistä käyttäjän valitsema pysäkki tallentuu ja näytetään valittuna vuoron linjalta', () async {
      final now = DateTime.now();
      final stop1 = const Stop(
        gtfsId: 'HSL:1250101',
        name: 'Käpylän asema',
        code: '2090',
        position: LatLng(60.2150, 24.9460),
      );
      final stop2 = const Stop(
        gtfsId: 'HSL:1280501',
        name: 'Oulunkylän asema',
        code: '0501',
        position: LatLng(60.2285, 24.9680),
      );
      final testVehicle = Vehicle(
        id: 'gtfs:HSL:3001K_1',
        tripGtfsId: 'HSL:3001K_1',
        line: 'K',
        routeGtfsId: 'HSL:3001K',
        direction: 0,
        mode: TransitMode.rail,
        position: const LatLng(60.2000, 24.9350),
        headsign: 'Kerava',
        updatedAt: now,
      );

      fakeApi.mockedTripTimesById['HSL:3001K_1'] = [
        TripStopTime(stop1, now.add(const Duration(minutes: 2)), now.add(const Duration(minutes: 2))),
        TripStopTime(stop2, now.add(const Duration(minutes: 5)), now.add(const Duration(minutes: 5))),
      ];
      fakeApi.mockedVehiclesForRoutes = [testVehicle];

      await controller.select(testVehicle);
      expect(controller.selectedId, equals(testVehicle.id));
      expect(controller.tripTimes.length, equals(2));
      expect(controller.selectedStop, isNull);

      // Käyttäjä valitsee pysäkkilistalta pysäkin "Oulunkylän asema"
      final st2 = controller.tripTimes[1];
      controller.selectStop(st2.stop, st2);
      expect(controller.selectedStop, isNotNull);
      expect(controller.selectedStop!.name, equals('Oulunkylän asema'));
      expect(controller.selectedTripStopTime, equals(st2));

      // Valinnan napauttaminen uudelleen kytkee sen pois päältä (toggle)
      controller.selectStop(st2.stop, st2);
      expect(controller.selectedStop, isNull);
      expect(controller.selectedTripStopTime, isNull);

      // Valitaan uudestaan ja nollataan vuoron valinta
      controller.selectStop(stop1, controller.tripTimes[0]);
      expect(controller.selectedStop?.name, equals('Käpylän asema'));
      controller.clearSelection();
      expect(controller.selectedStop, isNull);
    });

    test('16) Kun live-vuoron alakortti suljetaan ruksista (closeVehicleCard), sulkeutuu vain lista mutta linjakartta ja reitti säilyvät näkyvissä', () async {
      final now = DateTime.now();
      final stop1 = const Stop(
        gtfsId: 'HSL:46001',
        name: 'Rautatientori',
        code: '1001',
        position: LatLng(60.1710, 24.9410),
      );
      final testBus = Vehicle(
        id: 'gtfs:HSL:4600_1',
        tripGtfsId: 'HSL:4600_1',
        line: '600',
        routeGtfsId: 'HSL:4600',
        direction: 0,
        mode: TransitMode.bus,
        position: const LatLng(60.1710, 24.9410),
        headsign: 'Lentoasema',
        updatedAt: now,
      );

      fakeApi.mockedTripTimesById['HSL:4600_1'] = [
        TripStopTime(stop1, now.add(const Duration(minutes: 10)), now.add(const Duration(minutes: 10))),
      ];
      fakeApi.mockedRoutesWithPatterns['HSL:4600'] = LineInfo(
        gtfsId: 'HSL:4600',
        shortName: '600',
        longName: 'Rautatientori - Lentoasema',
        mode: TransitMode.bus,
        patterns: [
          LinePattern(
            code: 'HSL:4600:0:01',
            headsign: 'Lentoasema',
            directionId: 0,
            geometry: const [LatLng(60.171, 24.941), LatLng(60.317, 24.968)],
            stops: [stop1],
          ),
        ],
      );

      // Valitaan vuoro
      await controller.select(testBus);
      expect(controller.selectedId, equals(testBus.id));
      expect(controller.selectedPattern, isNotNull);
      expect(controller.isVehicleCardVisible, isTrue);

      // Käyttäjä sulkee alakortin/listan ruksista (x)
      controller.closeVehicleCard();

      // Listakortti on suljettu, mutta linja ja reittikuvio pysyvät edelleen kartalla!
      expect(controller.isVehicleCardVisible, isFalse);
      expect(controller.selectedPattern, isNotNull);
      expect(controller.selectedLine, isNotNull);
      expect(controller.selectedPattern!.headsign, equals('Lentoasema'));

      // Käyttäjä voi avata listan uudelleen
      controller.showVehicleCard();
      expect(controller.isVehicleCardVisible, isTrue);

      // Tyhjän kartan napauttaminen (clearSelection) sulkee sekä linjan että kortin
      controller.clearSelection();
      expect(controller.selectedPattern, isNull);
      expect(controller.selectedId, isNull);
      expect(controller.isVehicleCardVisible, isFalse);
    });

    test('17) Kun "Kaikkia" on aktiivisena, kyselyn keskeyttäminen x-ruksista (cancelSearch) nollaa isAllNearbyLinesActive-tilan ja palauttaa oletustilan', () async {
      await controller.searchAllNearbyLines();
      expect(controller.isAllNearbyLinesActive, isTrue);

      // Käyttäjä napauttaa keskeytä kysely x-ruksia
      controller.cancelSearch();
      expect(controller.isAllNearbyLinesActive, isFalse);
      expect(controller.isSearchingRoutes, isFalse);
      expect(controller.isAwaitingHfpVehicles, isFalse);
      expect(controller.lineFilter, isEmpty);
    });
  });
}
