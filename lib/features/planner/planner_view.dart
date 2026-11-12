import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../models/journey.dart';
import '../../models/place_stop.dart';
import '../../models/transit_mode.dart';
import '../../shared/base_map.dart';
import '../../shared/mode_style.dart';
import '../../shared/place_search.dart';
import '../../shared/region_selector.dart';
import '../../shared/street_view.dart';
import '../../shared/widgets.dart';
import '../../state/alarm_controller.dart';
import '../../state/app_state.dart';
import '../../state/planner_controller.dart';
import '../../theme/hsl_colors.dart';
import '../alarms/alarm_management_dialog.dart';
import '../alarms/set_trip_alarm_dialog.dart';

class PlannerView extends StatefulWidget {
  const PlannerView({super.key});

  @override
  State<PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends State<PlannerView> {
  final MapController _mapController = MapController();
  int? _selectedLegIndex; // null = koko reitti näkyvissä
  bool _isMapExpanded = false;
  bool _showMap = true;
  bool _showQueryFields = true;

  void _zoomToLeg(Leg leg) {
    final points = leg.geometry.isNotEmpty ? leg.geometry : [leg.fromPos, leg.toPos];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15.5);
    } else {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40),
          maxZoom: 17.0,
        ),
      );
    }
  }

  void _zoomToItinerary(Itinerary itin) {
    if (itin.allPoints.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(itin.allPoints);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(35),
        maxZoom: 16.0,
      ),
    );
  }

  Future<void> _setAlarmForItinerary(Itinerary itin) async {
    HapticFeedback.heavyImpact();
    final walkStartTime = itin.start;

    // Ensimmäinen joukkoliikenneosuus tai ensimmäinen osuus
    final firstTransit = itin.legs.where((l) => l.isTransit).firstOrNull;
    final line = firstTransit?.line;
    final mode = firstTransit?.mode ?? itin.legs.first.mode;
    final dest = firstTransit != null && firstTransit.headsign.isNotEmpty
        ? firstTransit.headsign
        : (itin.legs.isNotEmpty ? itin.legs.last.toName : '');
    final stop = firstTransit?.fromName ?? (itin.legs.isNotEmpty ? itin.legs.first.fromName : '');

    await SetTripAlarmDialog.show(
      context,
      title: line != null ? '${mode.label} $line' : 'Reitti $dest',
      line: line,
      mode: mode,
      destination: dest,
      stopName: stop.isNotEmpty ? stop : null,
      departureTime: firstTransit?.start ?? itin.start,
      walkStartTime: walkStartTime,
      source: 'planner',
    );
  }

  List<Polyline> _buildLegPolylines(Itinerary itin) {
    final polylines = <Polyline>[];
    for (int i = 0; i < itin.legs.length; i++) {
      final leg = itin.legs[i];
      final isLegSelected = _selectedLegIndex == i;
      final points = leg.geometry.isNotEmpty ? leg.geometry : [leg.fromPos, leg.toPos];
      if (points.isEmpty) continue;
      final baseCol = leg.isTransit ? lineColor(leg.mode, leg.line) : HslColors.walkGray;

      final activeCol = _selectedLegIndex == null
          ? baseCol
          : (isLegSelected ? baseCol : baseCol.withValues(alpha: 0.25));

      // Valitun osan valkoinen reunus/korostus
      if (isLegSelected) {
        polylines.add(
          Polyline(
            points: points,
            strokeWidth: 9.0,
            color: Colors.white,
          ),
        );
      }

      polylines.add(
        Polyline(
          points: points,
          strokeWidth: isLegSelected ? 6.0 : (leg.isTransit ? 4.5 : 3.0),
          color: activeCol,
          pattern: leg.isTransit ? const StrokePattern.solid() : const StrokePattern.dotted(),
        ),
      );
    }
    return polylines;
  }

  List<Marker> _buildLegMarkers(Itinerary itin) {
    final markers = <Marker>[];
    if (itin.legs.isEmpty) return markers;

    if (_selectedLegIndex == null) {
      // Koko reitin alku- ja loppupisteet
      markers.add(
        Marker(
          point: itin.legs.first.fromPos,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Tooltip(
            message: '${itin.legs.first.fromName}\n(Paina pitkään: Google Street View)',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => openGoogleStreetView(
                context,
                position: itin.legs.first.fromPos,
                stopName: itin.legs.first.fromName,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: HslColors.successGreen,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                ),
                child: const Icon(Icons.trip_origin_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      );
      markers.add(
        Marker(
          point: itin.legs.last.toPos,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Tooltip(
            message: '${itin.legs.last.toName}\n(Paina pitkään: Google Street View)',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => openGoogleStreetView(
                context,
                position: itin.legs.last.toPos,
                stopName: itin.legs.last.toName,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: HslColors.safetyRed,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                ),
                child: const Icon(Icons.place_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      );
    } else if (_selectedLegIndex! < itin.legs.length) {
      // Valitun osuuden nousu- ja poistumispysäkit
      final leg = itin.legs[_selectedLegIndex!];
      final col = leg.isTransit ? lineColor(leg.mode, leg.line) : HslColors.walkGray;

      markers.add(
        Marker(
          point: leg.fromPos,
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Tooltip(
            message: '${leg.fromName}\n(Paina pitkään: Google Street View)',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => openGoogleStreetView(
                context,
                position: leg.fromPos,
                stopName: leg.fromName,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: col,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5)],
                ),
                child: Icon(leg.mode.icon, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      );

      markers.add(
        Marker(
          point: leg.toPos,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Tooltip(
            message: '${leg.toName}\n(Paina pitkään: Google Street View)',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => openGoogleStreetView(
                context,
                position: leg.toPos,
                stopName: leg.toName,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: col, width: 3.5),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                ),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Widget> _buildLegTiles(Itinerary itin, ThemeData theme) {
    final tiles = <Widget>[];
    for (int legIdx = 0; legIdx < itin.legs.length; legIdx++) {
      final leg = itin.legs[legIdx];
      final isLegActive = _selectedLegIndex == legIdx;
      final legCol = leg.isTransit ? lineColor(leg.mode, leg.line) : HslColors.walkGray;

      tiles.add(
        InkWell(
          key: ValueKey('leg_$legIdx'),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _selectedLegIndex = legIdx);
            _zoomToLeg(leg);
          },
          onLongPress: legIdx == 0 ? () => _setAlarmForItinerary(itin) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isLegActive
                  ? HslColors.primaryBlue.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLegActive ? HslColors.primaryBlue : Colors.transparent,
                width: isLegActive ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: legCol,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isLegActive
                        ? [BoxShadow(color: legCol.withValues(alpha: 0.4), blurRadius: 5)]
                        : null,
                  ),
                  child: Icon(leg.mode.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (leg.isTransit && leg.line != null) ...[
                            Text(
                              leg.line!,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              leg.isTransit
                                  ? (leg.headsign.isNotEmpty ? '→ ${leg.headsign}' : 'Osuus ${legIdx + 1}')
                                  : 'Kävele ${distanceText(leg.distance)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${hm(leg.start)} ${leg.fromName}  →  ${hm(leg.end)} ${leg.toName}',
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${leg.duration.inMinutes} min',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    if (isLegActive) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.visibility_rounded, size: 13, color: HslColors.primaryBlue),
                          SizedBox(width: 2),
                          Text('Kartalla', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: HslColors.primaryBlue)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerController>();
    final settings = context.watch<SettingsController>();
    final theme = Theme.of(context);
    final selectedItinerary = planner.selected;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                AppStrings.get('tab_planner'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const TransitRegionSelectorPill(compact: true),
          ],
        ),
        actions: [
          if (planner.results.isNotEmpty && _selectedLegIndex != null)
            TextButton.icon(
              icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
              label: const Text('Koko reitti', style: TextStyle(color: Colors.white, fontSize: 13)),
              onPressed: () {
                setState(() => _selectedLegIndex = null);
                if (selectedItinerary != null) _zoomToItinerary(selectedItinerary);
              },
            ),
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
            icon: planner.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Päivitä',
            onPressed: planner.loading
                ? null
                : () async {
                    setState(() => _selectedLegIndex = null);
                    await planner.search();
                    if (planner.selected != null) {
                      _zoomToItinerary(planner.selected!);
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Origin & Destination input card
          if (_showQueryFields)
            Card(
              margin: const EdgeInsets.all(10),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // From input
                  _PlaceInputTile(
                    label: AppStrings.get('from'),
                    place: planner.effectiveFrom,
                    icon: Icons.trip_origin_rounded,
                    iconColor: HslColors.successGreen,
                    onTap: () async {
                      final isRailOnly = planner.modes.length == 1 && planner.modes.contains(TransitMode.rail);
                      final p = await pickPlace(context, title: 'Lähtöpaikka', isRailOnly: isRailOnly);
                      if (p != null) {
                        planner.setFrom(p);
                        setState(() => _selectedLegIndex = null);
                      }
                    },
                  ),

                  // Waypoints (via)
                  for (int i = 0; i < planner.via.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const SizedBox(width: 24),
                          Expanded(
                            child: _PlaceInputTile(
                              label: 'Välipiste ${i + 1}',
                              place: planner.via[i],
                              icon: Icons.fmd_good_outlined,
                              iconColor: HslColors.warningAmber,
                              onTap: () async {
                                final isRailOnly = planner.modes.length == 1 && planner.modes.contains(TransitMode.rail);
                                final p = await pickPlace(context, title: 'Välipiste', allowCurrent: false, isRailOnly: isRailOnly);
                                if (p != null) {
                                  planner.removeVia(i);
                                  planner.addVia(p);
                                }
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: HslColors.safetyRed, size: 18),
                            onPressed: () => planner.removeVia(i),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 6),

                  // Destination input
                  Row(
                    children: [
                      Expanded(
                        child: _PlaceInputTile(
                          label: AppStrings.get('to'),
                          place: planner.to,
                          hint: 'Minne olet menossa?',
                          icon: Icons.place_rounded,
                          iconColor: HslColors.safetyRed,
                          onTap: () async {
                            final isRailOnly = planner.modes.length == 1 && planner.modes.contains(TransitMode.rail);
                            final p = await pickPlace(context, title: 'Määränpää', isRailOnly: isRailOnly);
                            if (p != null) {
                              planner.setTo(p);
                              setState(() => _selectedLegIndex = null);
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.swap_vert_rounded, color: HslColors.primaryBlue),
                        onPressed: () {
                          planner.swap();
                          setState(() => _selectedLegIndex = null);
                        },
                        tooltip: 'Vaihda suunta',
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Kulkumuotojen suodatus (VR-kaukojunat, bussit, ratikat, metro, lautat)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final mode in [
                          TransitMode.rail,
                          TransitMode.bus,
                          TransitMode.tram,
                          TransitMode.metro,
                          TransitMode.ferry,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    mode.icon,
                                    size: 14,
                                    color: planner.modes.contains(mode) ? Colors.white : mode.color,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    mode == TransitMode.rail ? 'Juna (VR & lähijunat)' : mode.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: planner.modes.contains(mode) ? Colors.white : null,
                                    ),
                                  ),
                                ],
                              ),
                              selected: planner.modes.contains(mode),
                              selectedColor: mode.color,
                              checkmarkColor: Colors.white,
                              onSelected: (_) => planner.toggleMode(mode),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Action row (Add waypoint & Search button)
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                        label: Text(AppStrings.get('add_via'), style: const TextStyle(fontSize: 12)),
                        onPressed: () async {
                          final isRailOnly = planner.modes.length == 1 && planner.modes.contains(TransitMode.rail);
                          final p = await pickPlace(context, title: 'Lisää välipiste', allowCurrent: false, isRailOnly: isRailOnly);
                          if (p != null) planner.addVia(p);
                        },
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        icon: planner.loading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.search_rounded, size: 18),
                        label: Text(AppStrings.get('search_routes')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HslColors.primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: planner.loading
                            ? null
                            : () async {
                                setState(() => _selectedLegIndex = null);
                                await planner.search();
                                if (planner.selected != null) {
                                  _zoomToItinerary(planner.selected!);
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Map view when results are available and map is visible
          if (_showMap && selectedItinerary != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: _isMapExpanded
                  ? (_showQueryFields ? 360.0 : 450.0)
                  : (_showQueryFields ? 230.0 : 320.0),
              curve: Curves.easeInOut,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: selectedItinerary.allPoints.isNotEmpty
                          ? selectedItinerary.allPoints.first
                          : (settings.region.center ?? const LatLng(60.1699, 24.9384)),
                      initialZoom: 13.0,
                    ),
                    children: [
                      buildTileLayer(settings.tile),
                      PolylineLayer(polylines: _buildLegPolylines(selectedItinerary)),
                      MarkerLayer(markers: _buildLegMarkers(selectedItinerary)),
                      buildAttribution(settings.tile),
                    ],
                  ),

                  // Floating indicator when a specific leg is selected
                  if (_selectedLegIndex != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 60,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Osa ${_selectedLegIndex! + 1}: ${selectedItinerary.legs[_selectedLegIndex!].fromName} → ${selectedItinerary.legs[_selectedLegIndex!].toName}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() => _selectedLegIndex = null);
                                _zoomToItinerary(selectedItinerary);
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text('Koko reitti', style: TextStyle(color: HslColors.primaryBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Expand / collapse map button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        icon: Icon(_isMapExpanded ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded, size: 18, color: HslColors.primaryBlue),
                        tooltip: _isMapExpanded ? 'Pienennä kartta' : 'Suurenna kartta',
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

          // Error banner
          if (planner.error != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HslColors.safetyRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: HslColors.safetyRed, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(planner.error!, style: const TextStyle(color: HslColors.safetyRed, fontSize: 13))),
                ],
              ),
            ),

          // Results header
          if (planner.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${AppStrings.get('route_options')} (${planner.results.length})',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.hintColor),
                  ),
                  Text(
                    'Napauta osuutta nähdäksesi sen kartalla',
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ],
              ),
            ),

          // Itineraries list and expandable leg details
          Expanded(
            child: planner.loading
                ? const Center(child: CircularProgressIndicator())
                : planner.results.isEmpty && planner.searched && planner.error == null
                    ? const Center(child: Text('Ei löytynyt reittejä.'))
                    : planner.results.isEmpty && !_showQueryFields
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.search_rounded,
                                    size: 48,
                                    color: HslColors.walkGray,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Kyselykentät on piilotettu.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.search_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Näytä kyselykentät'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: HslColors.primaryBlue,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () => setState(
                                      () => _showQueryFields = true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        itemCount: planner.results.length,
                        itemBuilder: (context, index) {
                          final itin = planner.results[index];
                          final isSelected = index == planner.selectedIndex;

                          return Card(
                            elevation: isSelected ? 4 : 1,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: isSelected
                                  ? const BorderSide(color: HslColors.primaryBlue, width: 2)
                                  : BorderSide.none,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row of route card
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      planner.select(index);
                                      setState(() => _selectedLegIndex = null);
                                      _zoomToItinerary(itin);
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${hm(itin.start)} – ${hm(itin.end)}',
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                            ),
                                            Text(
                                              durationText(itin.duration),
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: HslColors.primaryBlue),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // Quick badges summary
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            for (final (i, leg) in itin.legs.indexed) ...[
                                              if (i == 0)
                                                Tooltip(
                                                  message: 'Paina pitkään: aseta huomiohälytys',
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: InkWell(
                                                      borderRadius: BorderRadius.circular(8),
                                                      onLongPress: () => _setAlarmForItinerary(itin),
                                                      child: Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                                        child: leg.isTransit
                                                            ? LineBadge(mode: leg.mode, line: leg.line ?? '', small: true)
                                                            : Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  const Icon(Icons.directions_walk_rounded, size: 16, color: HslColors.walkGray),
                                                                  Text('${leg.duration.inMinutes}m', style: const TextStyle(fontSize: 11, color: HslColors.walkGray)),
                                                                ],
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              else if (leg.isTransit)
                                                LineBadge(mode: leg.mode, line: leg.line ?? '', small: true)
                                              else
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.directions_walk_rounded, size: 16, color: HslColors.walkGray),
                                                    Text('${leg.duration.inMinutes}m', style: const TextStyle(fontSize: 11, color: HslColors.walkGray)),
                                                  ],
                                                ),
                                              if (i < itin.legs.length - 1)
                                                const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.grey),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Kävelyä ${itin.walkDistance} m • ${itin.transfers} vaihtoa',
                                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // If this itinerary is selected, show clickable detailed Legs
                                  if (isSelected) ...[
                                    const Divider(height: 16),
                                    Text(
                                      'Reitin vaiheet (valitse osuus):',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.hintColor),
                                    ),
                                    const SizedBox(height: 6),
                                    ..._buildLegTiles(itin, theme),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _PlaceInputTile extends StatelessWidget {
  final String label;
  final GeoPlace? place;
  final String? hint;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _PlaceInputTile({
    required this.label,
    required this.place,
    this.hint,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPlace = place != null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPlace ? place!.label : (hint ?? label),
                    style: TextStyle(
                      fontWeight: hasPlace ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                      color: hasPlace ? null : theme.hintColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
