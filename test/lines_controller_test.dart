import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/models/line.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_mode.dart';
import 'package:hsltrafic/state/app_state.dart';
import 'package:hsltrafic/state/lines_controller.dart';

class _FakeDigitransitClient extends DigitransitClient {
  List<LineInfo> mockedLines = [];
  Map<String, LineInfo> mockedRoutesWithPatterns = {};
  List<Stop> mockedStops = [];
  Map<String, List<Departure>> mockedTimetables = {};

  @override
  Future<List<LineInfo>> searchLines(String name) async => mockedLines;

  @override
  Future<LineInfo?> routeWithPatterns(String gtfsId) async =>
      mockedRoutesWithPatterns[gtfsId];

  @override
  Future<List<Stop>> searchStops(String name) async => mockedStops;

  @override
  Future<List<Departure>> stopTimetable(String stopId, {DateTime? date, int count = 250}) async =>
      mockedTimetables[stopId] ?? const [];
}

class _FakeLocationService extends LocationService {
  @override
  Future<LatLng?> current() async => const LatLng(60.1708, 24.9414);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinesController tests', () {
    late _FakeDigitransitClient fakeApi;
    late LocationController locCtrl;
    late LinesController controller;

    final stop1 = const Stop(
      gtfsId: 'HSL:1001',
      name: 'Rautatientori',
      code: '1001',
      platformCode: '1',
      zoneId: 'A',
      position: LatLng(60.171, 24.941),
    );

    final stop2 = const Stop(
      gtfsId: 'HSL:1002',
      name: 'Hakaniemi',
      code: '1002',
      platformCode: '2',
      zoneId: 'A',
      position: LatLng(60.179, 24.952),
    );

    final stop3 = const Stop(
      gtfsId: 'HSL:1003',
      name: 'Ilmala',
      code: '1003',
      platformCode: '1',
      zoneId: 'A',
      position: LatLng(60.205, 24.921),
    );

    final testLine9 = LineInfo(
      gtfsId: 'HSL:1009',
      shortName: '9',
      longName: 'Länsiterminaali - Ilmala',
      mode: TransitMode.tram,
      patterns: [
        LinePattern(
          code: 'HSL:1009:0:01',
          headsign: 'Ilmala',
          directionId: 0,
          geometry: const [LatLng(60.171, 24.941), LatLng(60.179, 24.952), LatLng(60.205, 24.921)],
          stops: [stop1, stop2, stop3],
        ),
        LinePattern(
          code: 'HSL:1009:1:01',
          headsign: 'Länsiterminaali',
          directionId: 1,
          geometry: const [LatLng(60.205, 24.921), LatLng(60.179, 24.952), LatLng(60.171, 24.941)],
          stops: [stop3, stop2, stop1],
        ),
      ],
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      fakeApi = _FakeDigitransitClient();
      final services = Services(
        api: fakeApi,
        hfp: HfpService(),
        location: _FakeLocationService(),
        repo: FavoritesRepository(prefs),
      );
      locCtrl = LocationController(services);
      controller = LinesController(services, locCtrl);
    });

    test('1) Linjahaku hakee linjan, lataa päätepysäkit, välipysäkit ja linjareitin kartalle', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;

      expect(controller.searchMode, equals(LinesSearchMode.line));
      await controller.search('9');

      expect(controller.selectedLine, isNotNull);
      expect(controller.selectedLine!.shortName, equals('9'));
      expect(controller.selectedPattern, isNotNull);
      expect(controller.selectedPattern!.headsign, equals('Ilmala'));
      expect(controller.selectedPattern!.stops.length, equals(3));
      // Päätepysäkit ovat ensimmäinen ja viimeinen pysäkki
      expect(controller.selectedPattern!.stops.first.name, equals('Rautatientori'));
      expect(controller.selectedPattern!.stops.last.name, equals('Ilmala'));
    });

    test('2) Linjan suunnan vaihtaminen (selectPattern) päivittää reittikuvion ja päätepysäkit', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;

      await controller.search('9');
      expect(controller.selectedPattern!.headsign, equals('Ilmala'));

      // Vaihdetaan paluusuuntaan (Länsiterminaali)
      controller.selectPattern(testLine9.patterns[1]);
      expect(controller.selectedPattern!.headsign, equals('Länsiterminaali'));
      expect(controller.selectedPattern!.stops.first.name, equals('Ilmala'));
      expect(controller.selectedPattern!.stops.last.name, equals('Rautatientori'));
    });

    test('3) Pysäkin valitseminen kartalta (selectStop) hakee sen vuorokauden vuoroaikataulun', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;
      final now = DateTime.now();
      fakeApi.mockedTimetables['HSL:1002'] = [
        Departure(
          line: '9',
          mode: TransitMode.tram,
          headsign: 'Ilmala',
          scheduled: now.add(const Duration(minutes: 5)),
          realtime: now.add(const Duration(minutes: 6)),
          isRealtime: true,
          routeGtfsId: 'HSL:1009',
        ),
      ];

      await controller.search('9');
      // Käyttäjä napauttaa välipysäkkiä Hakaniemi
      await controller.selectStop(stop2);

      expect(controller.selectedStop, isNotNull);
      expect(controller.selectedStop!.name, equals('Hakaniemi'));
      expect(controller.departures.length, equals(1));
      expect(controller.departures.first.line, equals('9'));
    });

    test('4) Aikataululistan x-ruksi (clearSelectedStop) sulkee listan, mutta jättää pysäkin markeerauksen (selectedStop) näkyviin kartalle', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;

      await controller.search('9');
      await controller.selectStop(stop2);
      expect(controller.selectedStop, isNotNull);
      expect(controller.isTimetableVisible, isTrue);

      // 2) Suljetaan x-ruksista: aikataululista sulkeutuu, mutta markeeraus (selectedStop) jää näkyviin
      controller.clearSelectedStop();
      expect(controller.isTimetableVisible, isFalse);
      expect(controller.selectedStop, isNotNull);
      expect(controller.selectedStop!.gtfsId, equals(stop2.gtfsId));
      // Linja ja reitti säilyvät kartalla
      expect(controller.selectedLine, isNotNull);
      expect(controller.selectedPattern, isNotNull);

      // Voidaan avata uudelleen
      controller.openTimetable();
      expect(controller.isTimetableVisible, isTrue);
    });

    test('5) Pysäkkihaku (searchMode: stop) hakee pysäkin, näyttää sen kartalla ja listaa siitä lähtevät eri linjat', () async {
      final stopWithRoutes = Stop(
        gtfsId: 'HSL:1001',
        name: 'Rautatientori',
        code: '1001',
        platformCode: '1',
        zoneId: 'A',
        position: const LatLng(60.171, 24.941),
        routes: const [
          StopRoute(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala', mode: TransitMode.tram, headsign: 'Ilmala'),
          StopRoute(gtfsId: 'HSL:4600', shortName: '600', longName: 'Lentoasema', mode: TransitMode.bus, headsign: 'Lentoasema'),
        ],
      );

      fakeApi.mockedStops = [stopWithRoutes];
      fakeApi.mockedTimetables['HSL:1001'] = [
        Departure(
          line: '600',
          mode: TransitMode.bus,
          headsign: 'Lentoasema',
          scheduled: DateTime.now().add(const Duration(minutes: 10)),
          realtime: DateTime.now().add(const Duration(minutes: 10)),
          isRealtime: true,
        ),
      ];

      // Vaihdetaan tila Pysäkki-hakuun
      controller.setSearchMode(LinesSearchMode.stop);
      expect(controller.searchMode, equals(LinesSearchMode.stop));

      await controller.search('Rautatientori');

      expect(controller.selectedStop, isNotNull);
      expect(controller.selectedStop!.name, equals('Rautatientori'));
      expect(controller.selectedStop!.routes.length, equals(2));
      expect(controller.departures.length, equals(1));
    });

    test('6) Pysäkkilistan linjan valinta (selectLineFromStop) näyttää kyseisen linjan reitin kartalla korostaen valittua pysäkkiä', () async {
      final stopWithRoutes = Stop(
        gtfsId: 'HSL:1002',
        name: 'Hakaniemi',
        code: '1002',
        position: const LatLng(60.179, 24.952),
        routes: const [
          StopRoute(gtfsId: 'HSL:1009', shortName: '9', longName: 'Ilmala', mode: TransitMode.tram, headsign: 'Ilmala'),
        ],
      );

      fakeApi.mockedStops = [stopWithRoutes];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;

      controller.setSearchMode(LinesSearchMode.stop);
      await controller.search('Hakaniemi');
      expect(controller.selectedStop!.name, equals('Hakaniemi'));

      // Käyttäjä valitsee pysäkiltä linjan 9
      await controller.selectLineFromStop(stopWithRoutes.routes.first);

      expect(controller.selectedLine, isNotNull);
      expect(controller.selectedLine!.shortName, equals('9'));
      expect(controller.selectedPattern, isNotNull);
      // Valittu pysäkki säilyy korostettuna
      expect(controller.selectedStop, isNotNull);
      expect(controller.selectedStop!.name, equals('Hakaniemi'));
      // Pattern sisältää tämän pysäkin
      expect(controller.selectedPattern!.stops.any((s) => s.gtfsId == 'HSL:1002'), isTrue);
    });

    test('7) Hakukentän x-ruksi (clearSearch) nollaa haun ja tyhjentää valinnat', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;

      await controller.search('9');
      expect(controller.selectedLine, isNotNull);

      controller.clearSearch();
      expect(controller.query, isEmpty);
      expect(controller.selectedLine, isNull);
      expect(controller.selectedPattern, isNull);
      expect(controller.selectedStop, isNull);
    });

    test('8) Aikataulukauden vaihto (setDayType: arkisin, lauantaisin, sunnuntaisin) hakee kyseisen päivän aikataulun', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;
      await controller.search('9');
      await controller.selectStop(stop1);

      controller.setDayType(TimetableDayType.weekday);
      expect(controller.dayType, equals(TimetableDayType.weekday));

      controller.setDayType(TimetableDayType.saturday);
      expect(controller.dayType, equals(TimetableDayType.saturday));

      controller.setDayType(TimetableDayType.sunday);
      expect(controller.dayType, equals(TimetableDayType.sunday));
    });

    test('9) Pysäkkikoodihaku (esim. "  h080  ") siivoaa välilyönnit edestä ja takaa ja löytää koodia vastaavat pysäkit', () async {
      final stopH0801 = const Stop(
        gtfsId: 'HSL:1040437',
        name: 'Erottaja',
        code: 'H0801',
        platformCode: '1',
        zoneId: 'A',
        position: LatLng(60.166, 24.942),
      );
      final stopH0805 = const Stop(
        gtfsId: 'HSL:1040440',
        name: 'Aleksant. teatteri',
        code: 'H0805',
        platformCode: '1',
        zoneId: 'A',
        position: LatLng(60.163, 24.935),
      );

      String? lastSearchedStopArg;
      fakeApi.mockedStops = [stopH0805, stopH0801];
      // Tallennetaan API-kutsun argumentti tarkistusta varten
      fakeApi = _SpyDigitransitClient(onSearchStops: (q) => lastSearchedStopArg = q)
        ..mockedStops = [stopH0805, stopH0801];
      controller = LinesController(
        Services(
          api: fakeApi,
          hfp: HfpService(),
          location: _FakeLocationService(),
          repo: FavoritesRepository(await SharedPreferences.getInstance()),
        ),
        locCtrl,
      );

      controller.setSearchMode(LinesSearchMode.stop);

      // Haetaan välilyönneillä "  h080  "
      await controller.search('  h080  ');

      expect(controller.query, equals('h080'));
      expect(lastSearchedStopArg, equals('h080'));
      expect(controller.matchingStops.length, equals(2));
      expect(controller.selectedStop, isNotNull);
      expect(controller.selectedStop!.code, equals('H0805'));
    });

    test('10) Linjahaku siivoaa ylimääräiset välilyönnit edestä ja takaa ("  9  ")', () async {
      fakeApi.mockedLines = [testLine9];
      fakeApi.mockedRoutesWithPatterns['HSL:1009'] = testLine9;

      await controller.search('  9  ');
      expect(controller.query, equals('9'));
      expect(controller.selectedLine, isNotNull);
      expect(controller.selectedLine!.shortName, equals('9'));
    });
  });
}

class _SpyDigitransitClient extends _FakeDigitransitClient {
  final void Function(String) onSearchStops;
  _SpyDigitransitClient({required this.onSearchStops});

  @override
  Future<List<Stop>> searchStops(String name) async {
    onSearchStops(name);
    return mockedStops;
  }
}
