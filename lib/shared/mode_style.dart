import 'package:flutter/material.dart';
import '../models/transit_mode.dart';
import '../models/vehicle.dart';
import '../theme/hsl_colors.dart';

/// UI-tyyli (väri, ikoni) kulkumuodoille – erillään puhtaasta mallikerroksesta.
extension TransitModeStyle on TransitMode {
  IconData get icon {
    switch (this) {
      case TransitMode.bus:
        return Icons.directions_bus_rounded;
      case TransitMode.tram:
        return Icons.tram_rounded;
      case TransitMode.metro:
        return Icons.subway_rounded;
      case TransitMode.rail:
        return Icons.train_rounded;
      case TransitMode.ferry:
        return Icons.directions_boat_rounded;
      case TransitMode.walk:
        return Icons.directions_walk_rounded;
      case TransitMode.bike:
        return Icons.pedal_bike_rounded;
      case TransitMode.other:
        return Icons.directions_transit_rounded;
    }
  }

  Color get color {
    switch (this) {
      case TransitMode.bus:
        return HslColors.busBlue;
      case TransitMode.tram:
        return HslColors.tramGreen;
      case TransitMode.metro:
        return HslColors.metroOrange;
      case TransitMode.rail:
        return HslColors.trainPurple;
      case TransitMode.ferry:
        return HslColors.ferryCyan;
      case TransitMode.walk:
        return HslColors.walkGray;
      case TransitMode.bike:
        return HslColors.bikeYellow;
      case TransitMode.other:
        return HslColors.primaryBlue;
    }
  }
}

/// Runkolinjat näytetään oranssina, muut bussit sinisenä.
const Set<String> _trunkLines = {'200', '500', '510', '550', '560', '570'};

Color lineColor(TransitMode mode, String? shortName) {
  if (mode == TransitMode.bus && shortName != null && _trunkLines.contains(shortName)) {
    return HslColors.trunkBusOrange;
  }
  return mode.color;
}

/// Viiveväri: vihreä (ajoissa), keltainen (pieni myöhästyminen), punainen (yli 3 min).
/// Lähtöä odottavalle päätepysäkillä sininen/vihreä.
Color delayColor(int delaySec) {
  if (delaySec > 180) return HslColors.safetyRed;
  if (delaySec > 60) return HslColors.warningAmber;
  if (delaySec < -180) return HslColors.primaryBlue;
  return HslColors.successGreen;
}

String delayText(int delaySec) {
  final m = (delaySec / 60).round();
  if (m == 0) return 'Aikataulussa';
  if (m > 0) return '+$m min myöhässä';
  // Päätepysäkillä tai lähtöpisteessä odottava vuoro: ei "etuajassa 21 min", vaan lähtöön on 21 min!
  if (m < -3) return 'Lähtöön ${-m} min';
  return '${-m} min etuajassa';
}

/// Palauttaa ajoneuvon tilavärin huomioiden päätepysäkillä lähtöä odottavan tilanteen.
Color vehicleStatusColor(Vehicle vehicle) {
  if (vehicle.isWaitingForDeparture) {
    return HslColors.primaryBlue;
  }
  return delayColor(vehicle.delaySeconds);
}

/// Palauttaa ajoneuvon tilatekstin huomioiden päätepysäkillä lähtöä odottavan tilanteen.
String vehicleStatusText(Vehicle vehicle) {
  if (vehicle.isWaitingForDeparture) {
    final m = vehicle.minutesUntilDeparture;
    if (m <= 0) return 'Aikataulussa';
    if (m == 1) return 'Lähtöön 1 min';
    return 'Lähtöön $m min';
  }
  return delayText(vehicle.delaySeconds);
}
