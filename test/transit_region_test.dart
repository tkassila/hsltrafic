import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/models/place_stop.dart';
import 'package:hsltrafic/models/transit_region.dart';
import 'package:hsltrafic/shared/region_selector.dart';
import 'package:hsltrafic/state/app_state.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransitRegion model tests', () {
    test('byId resolves valid region and defaults to auto on unknown', () {
      expect(TransitRegion.byId('hsl'), equals(TransitRegion.hsl));
      expect(TransitRegion.byId('waltti'), equals(TransitRegion.waltti));
      expect(TransitRegion.byId('finland'), equals(TransitRegion.finland));
      expect(TransitRegion.byId('tampere'), equals(TransitRegion.tampere));
      expect(TransitRegion.byId('turku'), equals(TransitRegion.turku));
      expect(TransitRegion.byId('unknown_xyz'), equals(TransitRegion.auto));
      expect(TransitRegion.byId(null), equals(TransitRegion.auto));
    });

    test('resolveGraphqlUrl returns correct endpoint for explicit regions', () {
      expect(TransitRegion.hsl.resolveGraphqlUrl(null),
          equals('https://api.digitransit.fi/routing/v2/hsl/gtfs/v1'));
      expect(TransitRegion.waltti.resolveGraphqlUrl(null),
          equals('https://api.digitransit.fi/routing/v2/waltti/gtfs/v1'));
      expect(TransitRegion.finland.resolveGraphqlUrl(null),
          equals('https://api.digitransit.fi/routing/v2/finland/gtfs/v1'));
    });

    test('resolveGraphqlUrl dynamically detects city from GPS coordinates in auto mode', () {
      const helsinkiPos = LatLng(60.170, 24.940);
      const tamperePos = LatLng(61.498, 23.760);
      const turkuPos = LatLng(60.451, 22.266);
      const ouluPos = LatLng(65.012, 25.468);
      const jyvaskylaPos = LatLng(62.242, 25.747);
      const laplandPos = LatLng(68.906, 27.028);

      // Helsinki -> HSL
      expect(TransitRegion.auto.resolveGraphqlUrl(helsinkiPos), equals(TransitRegion.hsl.graphqlUrl));
      expect(TransitRegion.auto.effectiveDisplayName(helsinkiPos), equals('Automaattinen: HSL'));

      // Tampere -> Waltti
      expect(TransitRegion.auto.resolveGraphqlUrl(tamperePos), equals(TransitRegion.waltti.graphqlUrl));
      expect(TransitRegion.auto.effectiveDisplayName(tamperePos), equals('Automaattinen: Tampere'));

      // Turku -> Waltti
      expect(TransitRegion.auto.resolveGraphqlUrl(turkuPos), equals(TransitRegion.waltti.graphqlUrl));
      expect(TransitRegion.auto.effectiveDisplayName(turkuPos), equals('Automaattinen: Turku'));

      // Oulu -> Waltti
      expect(TransitRegion.auto.resolveGraphqlUrl(ouluPos), equals(TransitRegion.waltti.graphqlUrl));
      expect(TransitRegion.auto.effectiveDisplayName(ouluPos), equals('Automaattinen: Oulu'));

      // Jyväskylä -> Waltti
      expect(TransitRegion.auto.resolveGraphqlUrl(jyvaskylaPos), equals(TransitRegion.waltti.graphqlUrl));
      expect(TransitRegion.auto.effectiveDisplayName(jyvaskylaPos), equals('Automaattinen: Jyväskylä'));

      // Outside urban regions -> Finland
      expect(TransitRegion.auto.resolveGraphqlUrl(laplandPos), equals(TransitRegion.finland.graphqlUrl));
      expect(TransitRegion.auto.effectiveDisplayName(laplandPos), equals('Automaattinen: Koko Suomi'));
    });
  });

  group('SettingsController & DigitransitClient dynamic region integration', () {
    test('Default region is auto and updates DigitransitClient.graphqlUrl dynamically', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final loc = LocationService();
      final api = DigitransitClient();
      final services = Services(
        api: api,
        hfp: HfpService(),
        location: loc,
        repo: repo,
      );

      final settings = SettingsController(services);
      expect(settings.region, equals(TransitRegion.auto));
      expect(repo.transitRegion, equals('auto'));

      // Initially no GPS -> default HSL
      expect(api.graphqlUrl, equals(TransitRegion.hsl.graphqlUrl));

      // Setting location to Tampere
      loc.lastPosition = const LatLng(61.498, 23.760);
      expect(api.graphqlUrl, equals(TransitRegion.waltti.graphqlUrl));

      // Explicitly switching to Finland (VR & Kaukoliikenne)
      settings.setRegion(TransitRegion.finland);
      expect(settings.region, equals(TransitRegion.finland));
      expect(repo.transitRegion, equals('finland'));
      expect(api.graphqlUrl, equals(TransitRegion.finland.graphqlUrl));

      // Explicitly switching to Waltti
      settings.setRegion(TransitRegion.waltti);
      expect(settings.region, equals(TransitRegion.waltti));
      expect(repo.transitRegion, equals('waltti'));
      expect(api.graphqlUrl, equals(TransitRegion.waltti.graphqlUrl));
    });

    test('resolvePlanGraphqlUrl chooses correct router for local vs intercity VR routes', () {
      const hkiStation = LatLng(60.1719, 24.9414);
      const tampereStation = LatLng(61.4981, 23.7731);
      const tampereHervanta = LatLng(61.4498, 23.8596);
      const turkuStation = LatLng(60.4569, 22.2676);

      // 1) Helsinki -> Tampere is > 160 km intercity route -> Must use Finland (VR) router
      expect(
        TransitRegion.auto.resolvePlanGraphqlUrl(from: hkiStation, to: tampereStation),
        equals(TransitRegion.finland.graphqlUrl),
      );
      expect(
        TransitRegion.hsl.resolvePlanGraphqlUrl(from: hkiStation, to: tampereStation),
        equals(TransitRegion.finland.graphqlUrl),
      );

      // 2) Tampere -> Hervanta is local Tampere route -> Uses Waltti router
      expect(
        TransitRegion.tampere.resolvePlanGraphqlUrl(from: tampereStation, to: tampereHervanta),
        equals(TransitRegion.waltti.graphqlUrl),
      );
      expect(
        TransitRegion.auto.resolvePlanGraphqlUrl(from: tampereStation, to: tampereHervanta),
        equals(TransitRegion.waltti.graphqlUrl),
      );

      // 3) Tampere -> Turku is intercity route -> Uses Finland router
      expect(
        TransitRegion.tampere.resolvePlanGraphqlUrl(from: tampereStation, to: turkuStation),
        equals(TransitRegion.finland.graphqlUrl),
      );

      // 4) Explicit Finland region always uses Finland router
      expect(
        TransitRegion.finland.resolvePlanGraphqlUrl(from: tampereStation, to: tampereHervanta),
        equals(TransitRegion.finland.graphqlUrl),
      );
    });

    test('activeFocusPoint adapts to region and user GPS location', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final loc = LocationService();
      final api = DigitransitClient();
      final services = Services(
        api: api,
        hfp: HfpService(),
        location: loc,
        repo: repo,
      );
      final settings = SettingsController(services);

      // Auto without GPS -> null (or default)
      expect(settings.activeFocusPoint, isNull);

      // Auto with GPS -> returns user GPS
      const myGps = LatLng(60.200, 24.900);
      loc.lastPosition = myGps;
      expect(settings.activeFocusPoint, equals(myGps));

      // Selecting Tampere -> focus changes to Tampere center
      settings.setRegion(TransitRegion.tampere);
      expect(settings.activeFocusPoint, equals(TransitRegion.tampere.center));

      // Selecting Turku -> focus changes to Turku center
      settings.setRegion(TransitRegion.turku);
      expect(settings.activeFocusPoint, equals(TransitRegion.turku.center));
    });
  });

  group('TransitRegionSelector UI widget tests', () {
    testWidgets('TransitRegionSelectorPill displays active region and opens bottom sheet to select new', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final loc = LocationService();
      final api = DigitransitClient();
      final services = Services(
        api: api,
        hfp: HfpService(),
        location: loc,
        repo: repo,
      );

      final settings = SettingsController(services);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: TransitRegionSelectorPill(),
              ),
            ),
          ),
        ),
      );

      // Check that pill is rendered with Auto
      expect(find.text('Automaattinen (GPS)'), findsOneWidget);

      // Tap pill to open bottom sheet
      await tester.tap(find.byType(TransitRegionSelectorPill));
      await tester.pumpAndSettle();

      // Check bottom sheet contents
      expect(find.text('Valitse liikennealue & reititin'), findsOneWidget);
      expect(find.text('Waltti-kaupungit'), findsOneWidget);
      expect(find.text('Tampere (Nysse)'), findsOneWidget);

      // Select Tampere
      await tester.tap(find.text('Tampere (Nysse)'));
      await tester.pumpAndSettle();

      // Verify that bottom sheet closed and pill now reflects Tampere
      expect(settings.region, equals(TransitRegion.tampere));
      expect(find.text('Tampere (Nysse)'), findsOneWidget);
    });
  });

  group('Smart address & city/station geocoding and ranking', () {
    test('GeoPlace serializes and deserializes layer property correctly', () {
      const cityPlace = GeoPlace(
        label: 'Tampere',
        secondary: 'Kaupunki / Kunta',
        position: LatLng(61.498, 23.760),
        layer: 'localadmin',
      );
      final json = cityPlace.toJson();
      expect(json['layer'], equals('localadmin'));
      expect(json['label'], equals('Tampere'));

      final parsed = GeoPlace.fromJson(json);
      expect(parsed.label, equals('Tampere'));
      expect(parsed.layer, equals('localadmin'));
      expect(parsed.secondary, equals('Kaupunki / Kunta'));
    });
  });
}
