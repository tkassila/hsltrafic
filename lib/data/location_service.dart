import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum LocationState { unknown, ready, denied, deniedForever, serviceOff }

/// GPS-sijainti vain kun sovellus on auki.
class LocationService {
  LatLng? lastPosition;
  LatLng? get position => lastPosition;

  Future<LocationState> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationState.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied) return LocationState.denied;
    if (p == LocationPermission.deniedForever) return LocationState.deniedForever;
    return LocationState.ready;
  }

  Future<LatLng?> current() async {
    // Haetaan sijainti suoraan Geolocator.getCurrentPosition()-kutsulla (kuten bussit-flutterissa)
    try {
      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      lastPosition = latLng;
      return latLng;
    } catch (_) {}

    // Varalla laitteen viimeisin tunnettu sijainti
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final latLng = LatLng(last.latitude, last.longitude);
        lastPosition = latLng;
        return latLng;
      }
    } catch (_) {}
    return null;
  }

  Stream<LatLng> stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).map((p) => LatLng(p.latitude, p.longitude));

  Future<void> openSettings() => Geolocator.openAppSettings();
}
