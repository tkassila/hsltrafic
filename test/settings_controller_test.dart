import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hsltrafic/data/digitransit_client.dart';
import 'package:hsltrafic/data/favorites_repository.dart';
import 'package:hsltrafic/data/hfp_service.dart';
import 'package:hsltrafic/data/location_service.dart';
import 'package:hsltrafic/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsController default settings', () {
    test('Default tile source is OpenStreetMap (TileSource.osm) when user has not set another', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: repo,
      );

      final settings = SettingsController(services);
      expect(repo.tileSource, equals('osm'));
      expect(settings.tile, equals(TileSource.osm));
      expect(settings.tile.label, equals('OpenStreetMap'));
    });

    test('Default nearby radius is 1500m (1.5km) when user has not set another', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: repo,
      );

      final settings = SettingsController(services);
      expect(repo.nearbyRadius, equals(1500));
      expect(settings.nearbyRadius, equals(1500));
    });

    test('Saved custom settings override defaults', () async {
      SharedPreferences.setMockInitialValues({
        'tile_source': 'digitransit',
        'nearby_radius': 800,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: repo,
      );

      final settings = SettingsController(services);
      expect(repo.tileSource, equals('digitransit'));
      expect(settings.tile, equals(TileSource.digitransit));
      expect(repo.nearbyRadius, equals(800));
      expect(settings.nearbyRadius, equals(800));
    });

    test('Updating tile source and nearby radius persists them and notifies listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = FavoritesRepository(prefs);
      final services = Services(
        api: DigitransitClient(),
        hfp: HfpService(),
        location: LocationService(),
        repo: repo,
      );

      final settings = SettingsController(services);
      int notificationCount = 0;
      settings.addListener(() => notificationCount++);

      settings.setTile(TileSource.carto);
      expect(settings.tile, equals(TileSource.carto));
      expect(repo.tileSource, equals('carto'));
      expect(notificationCount, equals(1));

      settings.setNearbyRadius(2000);
      expect(settings.nearbyRadius, equals(2000));
      expect(repo.nearbyRadius, equals(2000));
      expect(notificationCount, equals(2));
    });
  });
}

