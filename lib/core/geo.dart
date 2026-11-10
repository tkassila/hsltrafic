import 'dart:math';
import 'package:latlong2/latlong.dart';

const Distance _distance = Distance();

/// Etäisyys metreinä kahden pisteen välillä.
double distanceMeters(LatLng a, LatLng b) => _distance(a, b);

/// Suunta (0..360°) pisteestä a pisteeseen b.
double bearingDegrees(LatLng a, LatLng b) => (_distance.bearing(a, b) + 360) % 360;

/// Purkaa Google-polyline-koodauksen (tarkkuus 5), jota Digitransit käyttää.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// Lähimmän pisteen etäisyys polyviivasta (metreinä) – approksimaatio pisteiden välein.
double distanceToPolyline(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return double.infinity;
  double best = double.infinity;
  for (final q in line) {
    final d = distanceMeters(p, q);
    if (d < best) best = d;
  }
  return best;
}

class PolylinePosition {
  final LatLng point;
  final double heading;
  final double arcLengthMeters;
  final int segmentIndex;
  final double distanceFromPointMeters;

  const PolylinePosition({
    required this.point,
    required this.heading,
    required this.arcLengthMeters,
    required this.segmentIndex,
    required this.distanceFromPointMeters,
  });
}

/// Projektoi pisteen [p] lähimmälle tiegeometrian ([polyline]) janalle (valinnaisesti alkaen
/// indeksistä [minSegmentIndex]). Palauttaa pisteen tarkan sijainnin tien keskilinjalla,
/// tien suuntakulman (`heading`) sekä kuljetun matkan (`arcLengthMeters`) polyviivan alusta.
PolylinePosition? projectOntoPolyline(
  LatLng p,
  List<LatLng> polyline, {
  int minSegmentIndex = 0,
}) {
  if (polyline.length < 2) return null;
  final cosLat = cos(p.latitude * pi / 180.0);

  double cumulative = 0.0;
  double bestDist = double.infinity;
  LatLng bestPoint = polyline.first;
  double bestArc = 0.0;
  double bestHeading = 0.0;
  int bestIdx = 0;

  final startIdx = minSegmentIndex.clamp(0, polyline.length - 2);
  for (int i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final segLen = distanceMeters(a, b);
    if (i >= startIdx) {
      final dx = (b.longitude - a.longitude) * cosLat;
      final dy = b.latitude - a.latitude;
      final lenSq = dx * dx + dy * dy;
      double t = 0.0;
      if (lenSq > 1e-14) {
        final px = (p.longitude - a.longitude) * cosLat;
        final py = p.latitude - a.latitude;
        t = ((px * dx + py * dy) / lenSq).clamp(0.0, 1.0);
      }
      final proj = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      final d = distanceMeters(p, proj);
      if (d < bestDist) {
        bestDist = d;
        bestPoint = proj;
        bestArc = cumulative + segLen * t;
        bestIdx = i;
        bestHeading = segLen > 1.0 ? bearingDegrees(a, b) : bestHeading;
      }
    }
    cumulative += segLen;
  }

  return PolylinePosition(
    point: bestPoint,
    heading: bestHeading,
    arcLengthMeters: bestArc,
    segmentIndex: bestIdx,
    distanceFromPointMeters: bestDist,
  );
}

/// Kiinnittää ("snappaa") ajoneuvon sijainnin [p] tien reittiviivalle [polyline], jos ajoneuvo
/// on enintään [maxDistanceMeters] (oletus 65 m) päässä tiestä. Estää GPS-heijastusten tai
/// mutkien oikaisun piirtämästä ajoneuvoa tien viereisten talojen/korttelien päälle.
PolylinePosition? snapToPolyline(
  LatLng p,
  List<LatLng> polyline, {
  double maxDistanceMeters = 65.0,
}) {
  final proj = projectOntoPolyline(p, polyline);
  if (proj == null || proj.distanceFromPointMeters > maxDistanceMeters) {
    return null;
  }
  return proj;
}

/// Interpoloi ajoneuvon sijainnin kahden pysäkin ([fromStop] -> [toStop]) välillä
/// pitkin todellista tie-/ratageometriaa ([polyline]) suhteella [frac] (`0.0 .. 1.0`).
/// Jos pysäkit ovat kaukana reittigeometriasta, käyttää suoraa janaa varalla.
({LatLng point, double heading, double spanMeters}) interpolateAlongPolyline(
  List<LatLng> polyline,
  LatLng fromStop,
  LatLng toStop,
  double frac,
) {
  final clampedFrac = frac.clamp(0.0, 1.0);
  if (polyline.length >= 2) {
    final startProj = projectOntoPolyline(fromStop, polyline);
    if (startProj != null && startProj.distanceFromPointMeters <= 150) {
      final endProj = projectOntoPolyline(
        toStop,
        polyline,
        minSegmentIndex: max(0, startProj.segmentIndex - 1),
      );
      if (endProj != null &&
          endProj.distanceFromPointMeters <= 150 &&
          endProj.arcLengthMeters >= startProj.arcLengthMeters) {
        final spanMeters = endProj.arcLengthMeters - startProj.arcLengthMeters;
        final targetArc = startProj.arcLengthMeters + spanMeters * clampedFrac;

        double acc = 0.0;
        for (int i = 0; i < polyline.length - 1; i++) {
          final a = polyline[i];
          final b = polyline[i + 1];
          final segLen = distanceMeters(a, b);
          if (acc + segLen >= targetArc || i == polyline.length - 2) {
            final localT =
                segLen > 0.1 ? ((targetArc - acc) / segLen).clamp(0.0, 1.0) : 0.0;
            final pt = LatLng(
              a.latitude + (b.latitude - a.latitude) * localT,
              a.longitude + (b.longitude - a.longitude) * localT,
            );
            final hdg = segLen > 1.0
                ? bearingDegrees(a, b)
                : (distanceMeters(fromStop, toStop) > 5
                    ? bearingDegrees(fromStop, toStop)
                    : 0.0);
            return (
              point: pt,
              heading: hdg,
              spanMeters: spanMeters > 5 ? spanMeters : distanceMeters(fromStop, toStop),
            );
          }
          acc += segLen;
        }
      }
    }
  }

  // Varalla suora interpolointi, jos tiegeometriaa ei ole saatavilla
  final pt = LatLng(
    fromStop.latitude + (toStop.latitude - fromStop.latitude) * clampedFrac,
    fromStop.longitude + (toStop.longitude - fromStop.longitude) * clampedFrac,
  );
  final d = distanceMeters(fromStop, toStop);
  final hdg = d > 5 ? bearingDegrees(fromStop, toStop) : 0.0;
  return (point: pt, heading: hdg, spanMeters: d);
}

/// HSL:n HFP-geohash-ruudut annetun keskipisteen ja säteen ympärille.
///
/// HFP-topic: `.../60;24/19/73/...` = kokonaisasteet `60;24`, sitten jokaisella
/// tasolla yksi desimaali leveys- ja pituusasteesta. Palauttaa ruutujen etuliitteet
/// (esim. `60;24/19/73`), joita vasten tilataan `<etuliite>/#`.
List<String> hfpCells(LatLng center, double radiusMeters, {int maxCells = 60}) {
  final dLat = radiusMeters / 111320.0;
  final dLon = radiusMeters / (111320.0 * cos(center.latitude * pi / 180.0));

  for (int decimals = 2; decimals >= 0; decimals--) {
    final scale = pow(10, decimals).toInt();
    final latMin = ((center.latitude - dLat) * scale).floor();
    final latMax = ((center.latitude + dLat) * scale).floor();
    final lonMin = ((center.longitude - dLon) * scale).floor();
    final lonMax = ((center.longitude + dLon) * scale).floor();
    final count = (latMax - latMin + 1) * (lonMax - lonMin + 1);
    if (count <= maxCells || decimals == 0) {
      final cells = <String>[];
      for (int la = latMin; la <= latMax; la++) {
        for (int lo = lonMin; lo <= lonMax; lo++) {
          cells.add(_cellString(la, lo, decimals));
        }
      }
      return cells;
    }
  }
  return const [];
}

String _cellString(int latIndex, int lonIndex, int decimals) {
  final scale = pow(10, decimals).toInt();
  final latInt = latIndex ~/ scale;
  final lonInt = lonIndex ~/ scale;
  final latFrac = (latIndex % scale).toString().padLeft(decimals, '0');
  final lonFrac = (lonIndex % scale).toString().padLeft(decimals, '0');
  final buf = StringBuffer('$latInt;$lonInt');
  for (int i = 0; i < decimals; i++) {
    buf.write('/${latFrac[i]}${lonFrac[i]}');
  }
  return buf.toString();
}

/// Rajaa pisteen sallittuun aluelaatikkoon (HSL- ja Uudenmaan kehysalue), jottei esim. emulaattorin Kalifornia-oletus mene kyselyihin.
bool isInGreaterHelsinki(LatLng p) =>
    p.latitude > 59.5 && p.latitude < 61.2 && p.longitude > 23.5 && p.longitude < 26.5;

/// Tarkistaa onko piste Suomen valtakunnan rajojen sisällä (estää emulaattorin Kalifornia/Mountain View -koordinaatit).
bool isInFinland(LatLng p) =>
    p.latitude >= 59.4 && p.latitude <= 70.2 && p.longitude >= 19.0 && p.longitude <= 31.6;
