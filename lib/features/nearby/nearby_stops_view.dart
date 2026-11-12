import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../core/localization.dart';
import '../../data/location_service.dart';
import '../../models/line.dart';
import '../../models/place_stop.dart';
import '../../models/transit_mode.dart';
import '../../shared/base_map.dart';
import '../../shared/mode_style.dart';
import '../../shared/occupancy_dialog.dart';
import '../../shared/place_search.dart';
import '../../shared/region_selector.dart';
import '../../shared/street_view.dart';
import '../../shared/widgets.dart';
import '../../state/alarm_controller.dart';
import '../../state/app_state.dart';
import '../../state/nearby_controller.dart';
import '../../theme/hsl_colors.dart';
import '../alarms/alarm_management_dialog.dart';
import '../alarms/set_trip_alarm_dialog.dart';

class NearbyStopsView extends StatefulWidget {
  const NearbyStopsView({super.key});

  @override
  State<NearbyStopsView> createState() => _NearbyStopsViewState();
}

class _NearbyStopsViewState extends State<NearbyStopsView> {
  static const double _normalMapHeight = 180.0;

  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _stopKeys = {};
  final Set<String> _expandedStopIds = {};

  bool _showMap = true;
  bool _showQueryFields = true;
  bool _isMapExpanded = false;
  int _lastSearchSeq = -1;
  String? _lastFittedLinePattern;

  // 4) Klikatun linjan reitin solmun (pysäkkirenkaan) popup-tiedot
  Stop? _inspectedPatternStop;

  /// Muotoilee linjan ja sen suunnan määränpään siten, että vuorojen numeron perään tulee
  /// se nimi mihin vuoro on sille suunnalle menossa, ei vuoron yleisnimeä (esim. "9 Länsisatama").
  static String formatLineAndDestination(String line, String destination) {
    final cleanLine = line.trim();
    final cleanDest = resolveDestinationHeadsign(headsign: destination).trim();
    if (cleanLine.isEmpty) return cleanDest;
    if (cleanDest.isEmpty) return cleanLine;
    if (cleanDest.toLowerCase().startsWith(cleanLine.toLowerCase())) {
      final remainder = cleanDest.substring(cleanLine.length).trim();
      if (remainder.isNotEmpty) {
        return '$cleanLine $remainder';
      }
      return cleanDest;
    }
    return '$cleanLine $cleanDest';
  }

  Future<void> _setAlarmForDeparture(Stop stop, Departure dep) async {
    HapticFeedback.heavyImpact();
    final walkMinutes = stop.distance != null ? (stop.distance! / 70).ceil() : 0;
    final walkStartTime = dep.realtime.subtract(Duration(minutes: walkMinutes));
    final stopLabel = '${stop.name}${stop.code != null ? " (${stop.code})" : ""}';

    await SetTripAlarmDialog.show(
      context,
      title: '${dep.mode.label} ${dep.line}',
      line: dep.line,
      mode: dep.mode,
      destination: dep.headsign,
      stopName: stopLabel,
      departureTime: dep.realtime,
      walkStartTime: walkStartTime,
      source: 'nearby',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nearby = context.read<NearbyController>();
      final loc = context.read<LocationController>();
      nearby.search();
      if (loc.state == LocationState.unknown) {
        loc.locate();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Sovittaa karttanäkymän kattamaan kaikki löydetyt pysäkit ja hakukeskipisteen
  void _fitStops(List<NearbyStop> items, LatLng originPos) {
    if (!mounted) return;
    if (items.isEmpty) {
      _mapController.move(originPos, 16.0);
      return;
    }
    final points = <LatLng>[
      originPos,
      for (final item in items) item.stop.position,
    ];
    if (points.length == 1) {
      _mapController.move(points.first, 16.0);
    } else {
      final bounds = LatLngBounds.fromPoints(points);
      if (bounds.southWest == bounds.northEast) {
        _mapController.move(points.first, 16.0);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40),
            maxZoom: 17.5,
          ),
        );
      }
    }
  }

  /// Sovittaa kartan näyttämään tietyn linjan katureitin ja valitun pysäkin
  void _fitLinePattern(LinePattern pattern, LatLng stopPos) {
    if (!mounted) return;
    final points = pattern.geometry.isNotEmpty
        ? pattern.geometry
        : [stopPos, ...pattern.stops.map((s) => s.position)];
    if (points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(35),
        maxZoom: 16.5,
      ),
    );
  }

  /// Zoomaa suoraan valitulle pysäkille
  void _zoomToStop(LatLng pos) {
    if (!mounted) return;
    _mapController.move(pos, math.max(_mapController.camera.zoom, 16.5));
  }

  /// 2) Vierittää listaa automaattisesti siten, että valittu pysäkki näkyy listassa
  void _scrollToStop(String stopId) {
    _expandedStopIds
      ..clear()
      ..add(stopId);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      final key = _stopKeys[stopId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      }
    });
  }

  /// 4) Rakentaa katureitin pysäkkien renkaat; klikattu rengas näyttää nimen ja koodin
  List<Marker> _buildPatternStopMarkers(
    LinePattern pattern,
    NearbyController nearby,
  ) {
    final markers = <Marker>[];
    final nodeColor = lineColor(
      nearby.selectedLineMode ?? nearby.selectedStop?.mode ?? TransitMode.bus,
      nearby.selectedLine ?? '',
    );

    for (final pst in pattern.stops) {
      if (pst.gtfsId == nearby.selectedStopId) continue;
      final isNodeClicked = _inspectedPatternStop?.gtfsId == pst.gtfsId;

      // 1) Pysäkin rengas reitillä: pysyy aina 100% reitillä (Alignment.center),
      // ja on vähän pienempi (11px vs 15px) silloin kun sen label on näkyvissä.
      markers.add(
        Marker(
          point: pst.position,
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Reitin ollessa kartalla pysäkin klikkaus näyttää vain kyseisen pysäkin tarkastelutiedot (ei vaihda pysäkkiä/kyselyä)
            onTap: () {
              setState(() {
                if (isNodeClicked) {
                  _inspectedPatternStop = null;
                } else {
                  _inspectedPatternStop = pst;
                }
              });
            },
            onLongPress: () {
              openGoogleStreetView(context, position: pst.position, stopName: pst.name);
            },
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: isNodeClicked ? 11 : 15,
                height: isNodeClicked ? 11 : 15,
                decoration: BoxDecoration(
                  color: isNodeClicked ? nodeColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isNodeClicked ? Colors.white : nodeColor,
                    width: isNodeClicked ? 2.0 : 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isNodeClicked
                          ? nodeColor.withValues(alpha: 0.5)
                          : Colors.black26,
                      blurRadius: isNodeClicked ? 4 : 2,
                      spreadRadius: isNodeClicked ? 1 : 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // 2) Kun tietty pysäkki on valittu, siirretään pysäkin labeliä linjan ja pysäkkirenkaan sivulle
      if (isNodeClicked) {
        final labelSide = _determineLabelSide(pst, nearby.selectedLinePattern);
        markers.add(
          Marker(
            point: pst.position,
            width: labelSide == _LabelSide.right ? 280 : 220,
            height: labelSide == _LabelSide.right ? 58 : 84,
            alignment: labelSide == _LabelSide.right
                ? Alignment.centerLeft
                : Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _inspectedPatternStop = null),
              onLongPress: () => openGoogleStreetView(context, position: pst.position, stopName: pst.name),
              child: labelSide == _LabelSide.right
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Riittävä etäisyys linjaviivan ja pysäkkirenkaan ulkopuolelle
                        const SizedBox(width: 24),
                        const CustomPaint(
                          size: Size(6, 12),
                          painter: _PointerArrowPainter(
                            color: Colors.black87,
                            direction: _ArrowDirection.left,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(pst.mode.icon, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 150),
                                    child: Text(
                                      pst.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (pst.code != null && pst.code!.isNotEmpty)
                                Text(
                                  'Pysäkki ${pst.code}${pst.platformCode != null ? ' (Laituri ${pst.platformCode})' : ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(pst.mode.icon, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 150),
                                    child: Text(
                                      pst.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (pst.code != null && pst.code!.isNotEmpty)
                                Text(
                                  'Pysäkki ${pst.code}${pst.platformCode != null ? ' (Laituri ${pst.platformCode})' : ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const CustomPaint(
                          size: Size(12, 6),
                          painter: _PointerArrowPainter(
                            color: Colors.black87,
                            direction: _ArrowDirection.down,
                          ),
                        ),
                        // Riittävä etäisyys linjaviivan ja pysäkkirenkaan ulkopuolelle
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  Marker _buildSelectedStopLabelMarker(
    Stop stop,
    LinePattern? pattern,
    NearbyController nearby,
  ) {
    final labelSide = _determineLabelSide(stop, pattern);
    return Marker(
      point: stop.position,
      width: labelSide == _LabelSide.right ? 280 : 220,
      height: labelSide == _LabelSide.right ? 58 : 84,
      alignment: labelSide == _LabelSide.right
          ? Alignment.centerLeft
          : Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => openGoogleStreetView(context, position: stop.position, stopName: stop.name),
        child: labelSide == _LabelSide.right
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Riittävä etäisyys linjaviivan ja pysäkkirenkaan ulkopuolelle
                  const SizedBox(width: 24),
                  const CustomPaint(
                    size: Size(6, 12),
                    painter: _PointerArrowPainter(
                      color: Colors.black87,
                      direction: _ArrowDirection.left,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          stop.mode.icon,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(
                            stop.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (stop.code != null && stop.code!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            stop.code!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                        if (nearby.isStopLoading(stop.gtfsId)) ...[
                          const SizedBox(width: 6),
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          stop.mode.icon,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(
                            stop.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (stop.code != null && stop.code!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            stop.code!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                        if (nearby.isStopLoading(stop.gtfsId)) ...[
                          const SizedBox(width: 6),
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const CustomPaint(
                    size: Size(12, 6),
                    painter: _PointerArrowPainter(
                      color: Colors.black87,
                      direction: _ArrowDirection.down,
                    ),
                  ),
                  // Riittävä etäisyys linjaviivan ja pysäkkirenkaan ulkopuolelle
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nearby = context.watch<NearbyController>();
    final settings = context.watch<SettingsController>();
    final origin = nearby.effectiveOrigin;
    final theme = Theme.of(context);

    // a) Päivitä karttanäkymä automaattisesti lähipysäkeille kun haku valmistuu
    if (nearby.searchSeq != _lastSearchSeq && !nearby.loading) {
      _lastSearchSeq = nearby.searchSeq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitStops(nearby.results, origin.position);
      });
    }

    // c) Kun linjan reitti katuverkossa on ladattu, sovitetaan kartta reitille kerran
    if (nearby.selectedLinePattern != null &&
        nearby.selectedLinePattern!.code != _lastFittedLinePattern) {
      _lastFittedLinePattern = nearby.selectedLinePattern!.code;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (nearby.selectedLinePattern != null && nearby.selectedStop != null) {
          _fitLinePattern(
            nearby.selectedLinePattern!,
            nearby.selectedStop!.position,
          );
        }
      });
    } else if (nearby.selectedLinePattern == null) {
      _lastFittedLinePattern = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                AppStrings.get('tab_nearby'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const TransitRegionSelectorPill(compact: true),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showQueryFields
                  ? Icons.search_off_rounded
                  : Icons.search_rounded,
            ),
            tooltip: _showQueryFields
                ? 'Piilota kyselykentät'
                : 'Näytä kyselykentät',
            onPressed: () =>
                setState(() => _showQueryFields = !_showQueryFields),
          ),
          IconButton(
            icon: Icon(_showMap ? Icons.view_list_rounded : Icons.map_rounded),
            tooltip: _showMap ? 'Piilota kartta' : 'Näytä kartta',
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
          Consumer<AlarmController>(
            builder: (context, alarmCtrl, _) => IconButton(
              icon: Badge(
                isLabelVisible: alarmCtrl.activeAlarms.isNotEmpty,
                label: Text('${alarmCtrl.activeAlarms.length}'),
                child: const Icon(Icons.alarm_rounded),
              ),
              tooltip: 'Hälytysten hallinta',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const AlarmManagementDialog(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Päivitä',
            onPressed: nearby.search,
          ),
        ],
      ),
      body: Column(
        children: [
          // Address & Radius control card (klikkaus tänne palauttaa kartan koon normaaliksi)
          if (_showQueryFields)
            Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (_isMapExpanded) {
                setState(() => _isMapExpanded = false);
              }
            },
            child: Card(
              margin: const EdgeInsets.fromLTRB(
                6,
                3,
                6,
                4,
              ), // const EdgeInsets.fromLTRB(12, 6, 12, 4),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5, //10,
                  vertical: 4, //8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Address Selector
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await pickPlace(
                          context,
                          title: 'Hae osoite tai paikka',
                        );
                        if (picked != null) {
                          nearby.setOrigin(picked);
                          _mapController.move(
                            picked.position,
                            _mapController.camera.zoom,
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              origin.isCurrentLocation
                                  ? Icons.my_location
                                  : Icons.place_rounded,
                              color: HslColors.primaryBlue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    origin.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (origin.secondary != null)
                                    Text(
                                      origin.secondary!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: theme.hintColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.edit_location_alt_rounded,
                              size: 16,
                              color: HslColors.primaryBlue,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Radius Slider Row (kompaktimpi korkeus)
                    Row(
                      children: [
                        Text(
                          '${AppStrings.get('search_radius')}:',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: HslColors.primaryBlue.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${nearby.radius} m',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: HslColors.primaryBlue,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: nearby.radius.toDouble().clamp(50, 3000),
                              min: 50,
                              max: 3000,
                              divisions: 59,
                              label: '${nearby.radius} m',
                              onChanged: (v) => nearby.setRadius(v.round()),
                              onChangeEnd: (v) =>
                                  nearby.setRadius(v.round(), immediate: true),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Map View (fokusoitaessa/klikattaessa korkeus 2x, muualle klikattaessa normaali)
          // Kyselykenttien piilotus suurentaa karttaa ja jättää samalla pysäkkilistalle enemmän tilaa
          if (_showMap)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              height: _isMapExpanded
                  ? (_showQueryFields ? _normalMapHeight * 2 : 420.0)
                  : (_showQueryFields ? _normalMapHeight : 240.0),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: origin.position,
                      initialZoom: 16.0,
                      onPositionChanged: (_, hasGesture) {
                        if (hasGesture && !_isMapExpanded) {
                          setState(() => _isMapExpanded = true);
                        }
                      },
                      onTap: (_, _) {
                        if (!_isMapExpanded) {
                          setState(() => _isMapExpanded = true);
                        }
                        if (_inspectedPatternStop != null) {
                          setState(() => _inspectedPatternStop = null);
                        }
                      },
                    ),
                    children: [
                      buildTileLayer(settings.tile),

                      // c) Näytetään kyseisen linjan reitti kaduilla (jos linja valittu)
                      if (nearby.selectedLinePattern != null &&
                          nearby.selectedLinePattern!.geometry.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            // Valkoinen taustahehku/reunus katureitille
                            Polyline(
                              points: nearby.selectedLinePattern!.geometry,
                              strokeWidth: 9.0,
                              color: Colors.white,
                            ),
                            // Linjan katureitti linjan omalla värillä
                            Polyline(
                              points: nearby.selectedLinePattern!.geometry,
                              strokeWidth: 6.0,
                              color: lineColor(
                                nearby.selectedLineMode ??
                                    nearby.selectedStop?.mode ??
                                    TransitMode.bus,
                                nearby.selectedLine ?? '',
                              ),
                            ),
                          ],
                        ),

                      // Radius circle around origin
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: origin.position,
                            radius: nearby.radius.toDouble(),
                            useRadiusInMeter: true,
                            color: HslColors.primaryBlue.withValues(
                              alpha: 0.10,
                            ),
                            borderColor: HslColors.primaryBlue.withValues(
                              alpha: 0.7,
                            ),
                            borderStrokeWidth: 1.5,
                          ),
                        ],
                      ),

                      // Hakukeskipisteen (oman sijainnin / osoitteen) markkeri
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: origin.position,
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: HslColors.primaryBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // 4) Linjan muiden pysäkkien renkaat/solmut katureitillä; klikattaessa näytetään nimi/koodi!
                      if (nearby.selectedLinePattern != null)
                        MarkerLayer(
                          markers: _buildPatternStopMarkers(
                            nearby.selectedLinePattern!,
                            nearby,
                          ),
                        ),

                      // b) Pysäkkien markkerit: valittu pysäkki korostettuna merkillä
                      // Kun tietty linja on valittu, piilotetaan muut ei-valitut lähipysäkit
                      MarkerLayer(
                        markers: [
                          // Ei-valitut pysäkit (näytetään vain jos linjaa ei ole valittu)
                          if (nearby.selectedLine == null)
                            for (final item in nearby.results)
                              if (item.stop.gtfsId != nearby.selectedStopId)
                                Marker(
                                  point: item.stop.position,
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    // 2) Kun valitaan pysäkki kartalta: hae tuoreet vuorot + näytä listasta se pysäkki
                                    onTap: () {
                                      nearby.selectStop(
                                        item.stop,
                                        fetchDepartures: true,
                                      );
                                      _zoomToStop(item.stop.position);
                                      _scrollToStop(item.stop.gtfsId);
                                    },
                                    onLongPress: () {
                                      openGoogleStreetView(context, position: item.stop.position, stopName: item.stop.name);
                                    },
                                    child: Center(
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: item.departures.isEmpty
                                              ? Color.lerp(
                                                  item.stop.mode.color,
                                                  Colors.white,
                                                  0.45,
                                                )!
                                              : item.stop.mode.color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          item.stop.mode.icon,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                          // Valittu pysäkki x/y: rengas/merkki pysyy aina 100% reitillä/koordinaatissa (Alignment.center)
                          if (nearby.selectedStop != null) ...[
                            Marker(
                              point: nearby.selectedStop!.position,
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (nearby.selectedLine == null) {
                                    nearby.selectStop(
                                      nearby.selectedStop,
                                      fetchDepartures: true,
                                    );
                                    _zoomToStop(nearby.selectedStop!.position);
                                    _scrollToStop(nearby.selectedStop!.gtfsId);
                                  }
                                },
                                onLongPress: () {
                                  openGoogleStreetView(context, position: nearby.selectedStop!.position, stopName: nearby.selectedStop!.name);
                                },
                                child: Center(
                                  child: Container(
                                    width: nearby.selectedLinePattern != null
                                        ? 18
                                        : 34,
                                    height: nearby.selectedLinePattern != null
                                        ? 18
                                        : 34,
                                    decoration: BoxDecoration(
                                      color: nearby.selectedStop!.mode.color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width:
                                            nearby.selectedLinePattern != null
                                            ? 2.5
                                            : 3.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: nearby.selectedStop!.mode.color
                                              .withValues(alpha: 0.6),
                                          blurRadius:
                                              nearby.selectedLinePattern != null
                                              ? 6
                                              : 10,
                                          spreadRadius:
                                              nearby.selectedLinePattern != null
                                              ? 1
                                              : 2,
                                        ),
                                        const BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      nearby.selectedLinePattern != null
                                          ? nearby.selectedStop!.mode.icon
                                          : Icons.place_rounded,
                                      color: Colors.white,
                                      size: nearby.selectedLinePattern != null
                                          ? 10
                                          : 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Pysäkin label siirrettynä linjaviivan ja pysäkkirenkaiden sivulle sopivan etäisyyden päähän
                            _buildSelectedStopLabelMarker(
                              nearby.selectedStop!,
                              nearby.selectedLinePattern,
                              nearby,
                            ),
                          ],
                        ],
                      ),

                      buildAttribution(settings.tile),
                    ],
                  ),

                  // Floating Info Banner (kun linjan reitti tai pysäkki on valittu)
                  if (nearby.selectedLine != null || nearby.loadingLineRoute)
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 56,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          children: [
                            if (nearby.selectedLine != null &&
                                nearby.selectedLineMode != null)
                              LineBadge(
                                mode: nearby.selectedLineMode!,
                                line: nearby.selectedLine!,
                                small: true,
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    nearby.loadingLineRoute
                                        ? 'Haetaan linjan ${nearby.selectedLine} reittiä...'
                                        : 'Linja ${nearby.selectedLine} → ${nearby.selectedHeadsign ?? ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (nearby.selectedStop != null)
                                    Text(
                                      'Pysäkki: ${nearby.selectedStop!.name}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (nearby.loadingLineRoute)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else
                              InkWell(
                                onTap: () {
                                  nearby.clearLineRoute();
                                  _fitStops(nearby.results, origin.position);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else if (nearby.selectedStop != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 56,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Valittu pysäkki: ${nearby.selectedStop!.name}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() => _expandedStopIds.clear());
                                nearby.clearSelection();
                                _fitStops(nearby.results, origin.position);
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  'Näytä kaikki',
                                  style: TextStyle(
                                    color: HslColors.primaryBlue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Expand/collapse map size button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        icon: Icon(
                          _isMapExpanded
                              ? Icons.close_fullscreen_rounded
                              : Icons.open_in_full_rounded,
                          size: 18,
                          color: HslColors.primaryBlue,
                        ),
                        tooltip: _isMapExpanded
                            ? 'Pienennä kartta'
                            : 'Suurenna kartta',
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() => _isMapExpanded = !_isMapExpanded);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Results Header & Count (klikkaus palauttaa kartan korkeuden normaaliksi)
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (_isMapExpanded) {
                setState(() => _isMapExpanded = false);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Löydetyt pysäkit (${nearby.results.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.hintColor,
                    ),
                  ),
                  if (nearby.loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      'Napauta pysäkkiä tai linjaa',
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                    ),
                ],
              ),
            ),
          ),

          // Stops List (fokuksen siirtyminen listaan palauttaa kartan korkeuden normaaliksi)
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (_isMapExpanded) {
                  setState(() => _isMapExpanded = false);
                }
              },
              child: nearby.loading && nearby.results.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : nearby.results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_off_rounded,
                              size: 48,
                              color: HslColors.walkGray,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppStrings.get('no_stops_found'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppStrings.get('increase_radius_hint'),
                              style: TextStyle(
                                color: theme.hintColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      itemCount: nearby.results.length,
                      itemBuilder: (context, index) {
                        final item = nearby.results[index];
                        final stop = item.stop;
                        final departures = item.departures;
                        final hasNoDepartures = departures.isEmpty;
                        final isDark = theme.brightness == Brightness.dark;
                        final isStopSelected =
                            stop.gtfsId == nearby.selectedStopId;
                        final isStopExpanded =
                            _expandedStopIds.contains(stop.gtfsId) ||
                            isStopSelected;

                        // Vaalennetaan taustavärejä kun pysäkillä ei ole vuoroja kyseisenä ajankohtana
                        final noDepCardColor = Color.lerp(
                          theme.cardColor,
                          Colors.white,
                          isDark ? 0.16 : 0.55,
                        )!;
                        final noDepInnerBg = Color.lerp(
                          theme.cardColor,
                          Colors.white,
                          isDark ? 0.22 : 0.68,
                        )!;
                        final noDepRowBg = Color.lerp(
                          theme.cardColor,
                          Colors.white,
                          isDark ? 0.28 : 0.78,
                        )!;
                        final effectiveModeColor = hasNoDepartures
                            ? Color.lerp(
                                stop.mode.color,
                                Colors.white,
                                isDark ? 0.35 : 0.40,
                              )!
                            : stop.mode.color;

                        return Card(
                          key: _stopKeys.putIfAbsent(
                            stop.gtfsId,
                            () => GlobalKey(),
                          ),
                          elevation: isStopSelected
                              ? 5
                              : (hasNoDepartures ? 1 : 2),
                          margin: const EdgeInsets.only(bottom: 12),
                          // 1) & 2) Korosta valittua pysäkkiä tietyllä reunaviivalla ja värillä
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: isStopSelected
                                ? BorderSide(
                                    color: effectiveModeColor,
                                    width: 2.5,
                                  )
                                : BorderSide(
                                    color: hasNoDepartures
                                        ? Colors.white.withValues(
                                            alpha: isDark ? 0.22 : 0.6,
                                          )
                                        : Colors.grey.withValues(alpha: 0.2),
                                    width: 1.0,
                                  ),
                          ),
                          color: hasNoDepartures
                              ? noDepCardColor
                              : (isStopSelected
                                    ? stop.mode.color.withValues(alpha: 0.04)
                                    : null),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  setState(() {
                                    if (isStopExpanded) {
                                      _expandedStopIds.remove(stop.gtfsId);
                                      if (isStopSelected) {
                                        nearby.selectStop(
                                          null,
                                          fetchDepartures: false,
                                        );
                                      }
                                    } else {
                                      _expandedStopIds
                                        ..clear()
                                        ..add(stop.gtfsId);
                                      nearby.selectStop(
                                        stop,
                                        fetchDepartures: false,
                                      );
                                      _zoomToStop(stop.position);
                                    }
                                  });
                                },
                                onLongPress: () {
                                  openGoogleStreetView(context, position: stop.position, stopName: stop.name);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: hasNoDepartures
                                              ? Color.lerp(
                                                  stop.mode.color,
                                                  Colors.white,
                                                  isDark ? 0.45 : 0.65,
                                                )!.withValues(
                                                  alpha: isDark ? 0.30 : 0.55,
                                                )
                                              : stop.mode.color.withValues(
                                                  alpha: isStopSelected
                                                      ? 0.35
                                                      : 0.15,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: isStopSelected
                                              ? Border.all(
                                                  color: effectiveModeColor,
                                                  width: 2.2,
                                                )
                                              : null,
                                        ),
                                        child: Icon(
                                          stop.mode.icon,
                                          color: effectiveModeColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    stop.name,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                      color: isStopSelected
                                                          ? stop.mode.color
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                                if (stop.distance != null)
                                                  Text(
                                                    distanceText(
                                                      stop.distance!,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme.hintColor,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    [
                                                      stop.subtitle.isNotEmpty
                                                          ? stop.subtitle
                                                          : stop.gtfsId,
                                                      if (departures.isEmpty &&
                                                          stop
                                                              .routes
                                                              .isNotEmpty)
                                                        'Linjat: ${stop.routes.take(5).map((r) => r.shortName).join(', ')}',
                                                    ].join(' • '),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: theme.hintColor,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isStopSelected) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '• Valittu pysäkki',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: stop.mode.color,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        isStopExpanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        color: isStopSelected
                                            ? stop.mode.color
                                            : theme.hintColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isStopExpanded) ...[
                                const Divider(height: 1),
                                if (departures.isEmpty && stop.routes.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Ei vuoroja tällä hetkellä.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                )
                              else if (departures.isEmpty) ...[
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: noDepInnerBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isStopSelected
                                          ? effectiveModeColor.withValues(
                                              alpha: 0.45,
                                            )
                                          : theme.dividerColor.withValues(
                                              alpha: 0.3,
                                            ),
                                      width: isStopSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: 6,
                                          top: 2,
                                        ),
                                        child: Text(
                                          'Ei vuoroja tällä hetkellä • Pysäkin linjat (valitse nähdäksesi reitti):',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isStopSelected
                                                ? effectiveModeColor
                                                : theme.hintColor,
                                          ),
                                        ),
                                      ),
                                      for (final (rIdx, route)
                                          in stop.routes.indexed)
                                        Builder(
                                          builder: (context) {
                                            final isLineSelected =
                                                isStopSelected &&
                                                (nearby.selectedDepartureIndex !=
                                                        null
                                                    ? nearby.selectedDepartureIndex ==
                                                          rIdx
                                                    : nearby.selectedLine ==
                                                          route.shortName);
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isLineSelected
                                                    ? HslColors.primaryBlue
                                                          .withValues(
                                                            alpha: 0.16,
                                                          )
                                                    : noDepRowBg,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isLineSelected
                                                      ? HslColors.primaryBlue
                                                      : (isStopSelected
                                                            ? effectiveModeColor
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  )
                                                            : Colors
                                                                  .transparent),
                                                  width: isLineSelected
                                                      ? 2.0
                                                      : 1.0,
                                                ),
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                onTap: () {
                                                  if (isLineSelected) {
                                                    setState(
                                                      () =>
                                                          _inspectedPatternStop =
                                                              null,
                                                    );
                                                    nearby.clearLineRoute();
                                                    _fitStops(
                                                      nearby.results,
                                                      origin.position,
                                                    );
                                                  } else {
                                                    nearby.selectLineRoute(
                                                      stop: stop,
                                                      line: route.shortName,
                                                      mode: route.mode,
                                                      headsign: route.headsign,
                                                      routeGtfsId: route.gtfsId,
                                                      departureIndex: rIdx,
                                                    );
                                                  }
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      LineBadge(
                                                        mode: route.mode,
                                                        line: route.shortName,
                                                        small: true,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          formatLineAndDestination(
                                                            route.shortName,
                                                            route.headsign.isNotEmpty
                                                                ? route.headsign
                                                                : route.longName,
                                                          ),
                                                          style: TextStyle(
                                                            fontWeight:
                                                                isLineSelected
                                                                ? FontWeight
                                                                      .bold
                                                                : FontWeight
                                                                      .w500,
                                                            fontSize: 13,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Ei vuoroja nyt',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              theme.hintColor,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Icon(
                                                        Icons.route_rounded,
                                                        size: 16,
                                                        color: isLineSelected
                                                            ? HslColors
                                                                  .primaryBlue
                                                            : theme.hintColor
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                // 1) Korosta valitun pysäkin linjoja tietyllä reunaviivalla
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isStopSelected
                                        ? stop.mode.color.withValues(
                                            alpha: 0.05,
                                          )
                                        : theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isStopSelected
                                          ? stop.mode.color.withValues(
                                              alpha: 0.45,
                                            )
                                          : theme.dividerColor.withValues(
                                              alpha: 0.3,
                                            ),
                                      width: isStopSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: 6,
                                          top: 2,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Pysäkin linjat (valitse nähdäksesi reitti & 2h vuorot):',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isStopSelected
                                                    ? stop.mode.color
                                                    : theme.hintColor,
                                              ),
                                            ),
                                            if (nearby.isStopLoading(stop.gtfsId))
                                              const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: HslColors.primaryBlue,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      for (final (depIdx, dep)
                                          in departures.indexed) ...[
                                        Builder(
                                          builder: (context) {
                                            final isLineSelected =
                                                isStopSelected &&
                                                (nearby.selectedDepartureIndex !=
                                                        null
                                                    ? nearby.selectedDepartureIndex ==
                                                          depIdx
                                                    : (nearby.selectedLine ==
                                                              dep.line &&
                                                          nearby.selectedHeadsign ==
                                                              dep.headsign));

                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isLineSelected
                                                    ? HslColors.primaryBlue
                                                          .withValues(
                                                            alpha: 0.12,
                                                          )
                                                    : (isStopSelected
                                                          ? theme.cardColor
                                                          : theme
                                                                .colorScheme
                                                                .surface),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                // 1) Linjan reunaviiva
                                                border: Border.all(
                                                  color: isLineSelected
                                                      ? HslColors.primaryBlue
                                                      : (isStopSelected
                                                            ? stop.mode.color
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  )
                                                            : Colors
                                                                  .transparent),
                                                  width: isLineSelected
                                                      ? 2.0
                                                      : 1.0,
                                                ),
                                                boxShadow: isStopSelected
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.04,
                                                              ),
                                                          blurRadius: 3,
                                                          offset: const Offset(
                                                            0,
                                                            1,
                                                          ),
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Linjan perustiedot ja napautus
                                                  InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    onTap: () {
                                                      if (isLineSelected) {
                                                        setState(
                                                          () =>
                                                              _inspectedPatternStop =
                                                                  null,
                                                        );
                                                        nearby.clearLineRoute();
                                                        _fitStops(
                                                          nearby.results,
                                                          origin.position,
                                                        );
                                                      } else {
                                                        nearby.selectLineRoute(
                                                          stop: stop,
                                                          line: dep.line,
                                                          mode: dep.mode,
                                                          headsign:
                                                              dep.headsign,
                                                          routeGtfsId:
                                                              dep.routeGtfsId,
                                                          departureIndex:
                                                              depIdx,
                                                        );
                                                      }
                                                    },
                                                    onLongPress: () {
                                                      showDepartureOccupancySheet(
                                                        context,
                                                        departure: dep,
                                                        stop: stop,
                                                        client: nearby.s.api,
                                                        onSetAlarm: () => _setAlarmForDeparture(stop, dep),
                                                      );
                                                    },
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 8,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          Tooltip(
                                                            message: 'Paina pitkään: aseta huomiohälytys',
                                                            child: GestureDetector(
                                                              behavior: HitTestBehavior.opaque,
                                                              onLongPress: () {
                                                                _setAlarmForDeparture(stop, dep);
                                                              },
                                                              child: LineBadge(
                                                                mode: dep.mode,
                                                                line: dep.line,
                                                                small: true,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  formatLineAndDestination(
                                                                    dep.line,
                                                                    dep.headsign,
                                                                  ),
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        isLineSelected
                                                                        ? FontWeight
                                                                              .bold
                                                                        : FontWeight
                                                                              .w500,
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                                if (isLineSelected)
                                                                  const Text(
                                                                    'Reitti näkyy kartalla • Vuorot alla',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: HslColors
                                                                          .primaryBlue,
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .end,
                                                            children: [
                                                              Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  if (dep.hasOccupancy) ...[
                                                                    Tooltip(
                                                                      message: dep.occupancyDescription,
                                                                      child: Icon(
                                                                        dep.occupancyIcon,
                                                                        size: 13,
                                                                        color: dep.occupancyColor,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 3),
                                                                  ],
                                                                  Text(
                                                                    '${dep.minutesUntil()} min',
                                                                    style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize: 14,
                                                                      color:
                                                                          dep.isRealtime
                                                                          ? HslColors
                                                                                .successGreen
                                                                          : null,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              Text(
                                                                hm(
                                                                  dep.realtime,
                                                                ),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: theme
                                                                      .hintColor,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Icon(
                                                            Icons.route_rounded,
                                                            size: 16,
                                                            color:
                                                                isLineSelected
                                                                ? HslColors
                                                                      .primaryBlue
                                                                : theme
                                                                      .hintColor
                                                                      .withValues(
                                                                        alpha:
                                                                            0.5,
                                                                      ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),

                                                  // 3) Linjan alla 1 tunnin seuraavat vuorot kun linja on valittu
                                                  if (isLineSelected) ...[
                                                    const Divider(height: 1),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: theme
                                                            .colorScheme
                                                            .surfaceContainerHighest
                                                            .withValues(
                                                              alpha: 0.3,
                                                            ),
                                                        borderRadius:
                                                            const BorderRadius.only(
                                                              bottomLeft:
                                                                  Radius.circular(
                                                                    10,
                                                                  ),
                                                              bottomRight:
                                                                  Radius.circular(
                                                                    10,
                                                                  ),
                                                            ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .schedule_rounded,
                                                                size: 14,
                                                                color: HslColors
                                                                    .primaryBlue,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Text(
                                                                'Seuraavat vuorot seuraavan 2 tunnin aikana:',
                                                                style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 11,
                                                                  color: HslColors
                                                                      .primaryBlue,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          if (nearby
                                                              .loadingHourDepartures) ...[
                                                            const Padding(
                                                              padding:
                                                                  EdgeInsets.symmetric(
                                                                    vertical: 6,
                                                                  ),
                                                              child: Row(
                                                                children: [
                                                                  SizedBox(
                                                                    width: 14,
                                                                    height: 14,
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Text(
                                                                    'Haetaan vuoroja...',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ] else if (nearby
                                                              .lineHourDepartures
                                                              .isNotEmpty) ...[
                                                            Wrap(
                                                              spacing: 6,
                                                              runSpacing: 6,
                                                              children: [
                                                                for (final hd
                                                                    in nearby
                                                                        .lineHourDepartures)
                                                                  Builder(
                                                                    builder: (context) {
                                                                      final isDark =
                                                                          theme
                                                                              .brightness ==
                                                                          Brightness
                                                                              .dark;
                                                                      final boxBg =
                                                                          isDark
                                                                          ? theme.colorScheme.surfaceContainerHigh
                                                                          : HslColors.surfaceLight;
                                                                      final boxBorder =
                                                                          hd.isRealtime
                                                                          ? HslColors.successGreen
                                                                          : (isDark
                                                                                ? Colors.white24
                                                                                : Colors.grey.shade300);
                                                                      final timeColor =
                                                                          isDark
                                                                          ? Colors.white
                                                                          : Colors.black87;
                                                                      final minColor =
                                                                          hd.isRealtime
                                                                          ? HslColors.successGreen
                                                                          : (isDark
                                                                                ? Colors.white70
                                                                                : Colors.grey.shade700);

                                                                      return Tooltip(
                                                                        message: 'Paina pitkään: näytä kuormitustieto & hälytys',
                                                                        child: InkWell(
                                                                          borderRadius: BorderRadius.circular(8),
                                                                          onLongPress: () {
                                                                            showDepartureOccupancySheet(
                                                                              context,
                                                                              departure: hd,
                                                                              stop: stop,
                                                                              client: nearby.s.api,
                                                                              onSetAlarm: () => _setAlarmForDeparture(stop, hd),
                                                                            );
                                                                          },
                                                                          child: Container(
                                                                            padding: const EdgeInsets.symmetric(
                                                                              horizontal:
                                                                                  8,
                                                                              vertical:
                                                                                  4,
                                                                            ),
                                                                            decoration: BoxDecoration(
                                                                              color:
                                                                                  boxBg,
                                                                              borderRadius:
                                                                                  BorderRadius.circular(
                                                                                    8,
                                                                                  ),
                                                                              border: Border.all(
                                                                                color:
                                                                                    boxBorder,
                                                                                width:
                                                                                    hd.isRealtime
                                                                                    ? 1.5
                                                                                    : 1.0,
                                                                              ),
                                                                              boxShadow: const [
                                                                                BoxShadow(
                                                                                  color: Colors.black12,
                                                                                  blurRadius: 2,
                                                                                  offset: Offset(
                                                                                    0,
                                                                                    1,
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            child: Row(
                                                                              mainAxisSize:
                                                                                  MainAxisSize.min,
                                                                              children: [
                                                                                if (hd.isRealtime)
                                                                                  Container(
                                                                                    width: 6,
                                                                                    height: 6,
                                                                                    margin: const EdgeInsets.only(right: 5),
                                                                                    decoration: const BoxDecoration(color: HslColors.successGreen, shape: BoxShape.circle),
                                                                                  ),
                                                                                Text(
                                                                                  '${formatLineAndDestination(hd.line, hd.headsign.isNotEmpty ? hd.headsign : (nearby.selectedHeadsign ?? ''))}  ',
                                                                                  style: TextStyle(
                                                                                    fontWeight: FontWeight.bold,
                                                                                    fontSize: 11,
                                                                                    color: timeColor,
                                                                                  ),
                                                                                ),
                                                                                Text(
                                                                                  hm(
                                                                                    hd.realtime,
                                                                                  ),
                                                                                  style: TextStyle(
                                                                                    fontWeight: FontWeight.bold,
                                                                                    fontSize: 12,
                                                                                    color: timeColor,
                                                                                  ),
                                                                                ),
                                                                                const SizedBox(
                                                                                  width: 3,
                                                                                ),
                                                                                Text(
                                                                                  '(${hd.minutesUntil()} min)',
                                                                                  style: TextStyle(
                                                                                    fontSize: 10,
                                                                                    fontWeight: FontWeight.w600,
                                                                                    color: minColor,
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  ),
                                                              ],
                                                            ),
                                                          ] else ...[
                                                            const Text(
                                                              'Ei muita vuoroja seuraavan 2 tunnin aikana.',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ArrowDirection { down, left, right, up }

enum _LabelSide { right, top }

/// Päättelee sijoitetaanko pysäkin label linjaviivan ja pysäkkirenkaiden sivulle (oikealle)
/// vai yläpuolelle siten, ettei label osu linjaviivan tai muiden pysäkkirenkaiden päälle.
_LabelSide _determineLabelSide(Stop stop, LinePattern? pattern) {
  if (pattern == null || pattern.stops.length < 2) {
    return _LabelSide.top;
  }
  final idx = pattern.stops.indexWhere((s) => s.gtfsId == stop.gtfsId);
  LatLng prev = stop.position;
  LatLng next = stop.position;
  if (idx != -1) {
    if (idx > 0) prev = pattern.stops[idx - 1].position;
    if (idx < pattern.stops.length - 1) next = pattern.stops[idx + 1].position;
  } else {
    int closestIdx = 0;
    double minD = double.infinity;
    for (int i = 0; i < pattern.stops.length; i++) {
      final d = distanceMeters(stop.position, pattern.stops[i].position);
      if (d < minD) {
        minD = d;
        closestIdx = i;
      }
    }
    if (closestIdx > 0) prev = pattern.stops[closestIdx - 1].position;
    if (closestIdx < pattern.stops.length - 1) next = pattern.stops[closestIdx + 1].position;
  }
  final dLat = next.latitude - prev.latitude;
  // Longitudin suhteellinen skaalaus ~60° leveysasteella (cos(60°) = 0.5)
  final dLon = (next.longitude - prev.longitude) * 0.5;

  // Jos linjaviiva kulkee ensisijaisesti itä-länsi-suunnassa, linjan ja renkaiden sivu on yläpuolella (pohjoinen).
  // Muussa tapauksessa (pystysuora tai viisto linja) sivu on linjan oikealla puolella (itä).
  if (dLon.abs() > dLat.abs()) {
    return _LabelSide.top;
  } else {
    return _LabelSide.right;
  }
}

/// Kolmionuoli markkerilaattojen viereen/alle
class _PointerArrowPainter extends CustomPainter {
  final Color color;
  final _ArrowDirection direction;
  const _PointerArrowPainter({
    required this.color,
    this.direction = _ArrowDirection.down,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    switch (direction) {
      case _ArrowDirection.down:
        path.moveTo(0, 0);
        path.lineTo(size.width / 2, size.height);
        path.lineTo(size.width, 0);
        break;
      case _ArrowDirection.left:
        path.moveTo(size.width, 0);
        path.lineTo(0, size.height / 2);
        path.lineTo(size.width, size.height);
        break;
      case _ArrowDirection.right:
        path.moveTo(0, 0);
        path.lineTo(size.width, size.height / 2);
        path.lineTo(0, size.height);
        break;
      case _ArrowDirection.up:
        path.moveTo(0, size.height);
        path.lineTo(size.width / 2, 0);
        path.lineTo(size.width, size.height);
        break;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.direction != direction;
}
