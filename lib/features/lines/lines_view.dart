import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../models/line.dart';
import '../../models/place_stop.dart';
import '../../models/transit_mode.dart';
import '../../shared/base_map.dart';
import '../../shared/mode_style.dart';
import '../../shared/street_view.dart';
import '../../shared/widgets.dart';
import '../../state/app_state.dart';
import '../../state/lines_controller.dart';
import '../../theme/hsl_colors.dart';

class LinesView extends StatefulWidget {
  const LinesView({super.key});

  @override
  State<LinesView> createState() => _LinesViewState();
}

class _LinesViewState extends State<LinesView> {
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showSearchCard = true;
  double _currentZoom = 14.5;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSearch(LinesController lines) async {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    final trimmed = _searchCtrl.text.trim();
    if (_searchCtrl.text != trimmed) {
      _searchCtrl.value = _searchCtrl.value.copyWith(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    await lines.search(trimmed);
    if (!mounted) return;
    if (lines.selectedPattern != null) {
      _fitPattern(lines.selectedPattern!);
    } else if (lines.selectedStop != null) {
      _mapController.move(lines.selectedStop!.position, math.max(_currentZoom, 15.0));
    }
  }

  void _fitPattern(LinePattern pattern) {
    if (pattern.geometry.isEmpty && pattern.stops.isEmpty) return;
    final points = pattern.geometry.isNotEmpty
        ? pattern.geometry
        : pattern.stops.map((s) => s.position).toList();
    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
    } else {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 100, 40, 180),
          maxZoom: 15.5,
        ),
      );
    }
  }

  /// 3) Avaa Google Street View pysäkin koordinaateista
  Future<void> _openStreetView(BuildContext context, Stop stop) async {
    await openGoogleStreetView(context, position: stop.position, stopName: stop.name);
  }

  @override
  Widget build(BuildContext context) {
    final lines = context.watch<LinesController>();
    final settings = context.watch<SettingsController>();
    final loc = context.watch<LocationController>();

    final selectedPattern = lines.selectedPattern;
    final selectedLine = lines.selectedLine;
    final selectedStop = lines.selectedStop;

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      body: Stack(
        children: [
          // 1) HSL Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: lines.center ?? loc.positionOrDefault,
              initialZoom: 14.5,
              minZoom: 10,
              maxZoom: 19,
              onPositionChanged: (pos, _) {
                final zoom = pos.zoom;
                if ((zoom - _currentZoom).abs() >= 0.35) {
                  setState(() => _currentZoom = zoom);
                }
              },
              onTap: (_, _) {
                if (_searchFocusNode.hasFocus || isKeyboardVisible) {
                  _searchFocusNode.unfocus();
                  FocusScope.of(context).unfocus();
                  return;
                }
              },
            ),
            children: [
              buildTileLayer(settings.tile),

              // 2) Linjareitti kartalla (Polyline)
              if (selectedPattern != null && selectedPattern.geometry.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: selectedPattern.geometry,
                      strokeWidth: 7.0,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    Polyline(
                      points: selectedPattern.geometry,
                      strokeWidth: 4.5,
                      color: lineColor(
                        selectedLine?.mode ?? TransitMode.bus,
                        selectedLine?.shortName ?? '',
                      ),
                    ),
                  ],
                ),

              // 2) Pysäkit kartalla (Päätepysäkit & välipysäkit)
              if (selectedPattern != null && selectedPattern.stops.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (int i = 0; i < selectedPattern.stops.length; i++)
                      _buildPatternStopMarker(
                        stop: selectedPattern.stops[i],
                        isTerminal: i == 0 || i == selectedPattern.stops.length - 1,
                        isFirst: i == 0,
                        isSelected: selectedPattern.stops[i].gtfsId == selectedStop?.gtfsId,
                        mode: selectedLine?.mode ?? TransitMode.bus,
                        lineName: selectedLine?.shortName ?? '',
                        onTap: () {
                          lines.selectStop(selectedPattern.stops[i]);
                          _mapController.move(selectedPattern.stops[i].position, math.max(_currentZoom, 15.0));
                        },
                        onLongPress: () => _openStreetView(context, selectedPattern.stops[i]),
                      ),
                    // 1) & 2) Valitun pysäkin label-merkki (kuten lähipysäkkikartalla), säilyy vaikka lista suljetaan x-ruksista
                    if (selectedStop != null)
                      _buildSelectedStopLabelMarker(
                        stop: selectedStop,
                        pattern: selectedPattern,
                        lines: lines,
                      ),
                  ],
                ),

              // 6) Jos pysäkkihaku löysi pysäkkejä eikä linjareittiä ole vielä valittu
              if (selectedPattern == null && (selectedStop != null || lines.matchingStops.isNotEmpty))
                MarkerLayer(
                  markers: [
                    for (final s in (lines.matchingStops.isNotEmpty ? lines.matchingStops : [?selectedStop]))
                      Marker(
                        point: s.position,
                        width: s == selectedStop ? 44 : 32,
                        height: s == selectedStop ? 44 : 32,
                        alignment: Alignment.center,
                        child: Tooltip(
                          message: '${s.name}\n(Paina pitkään: Google Street View)',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              lines.selectStop(s);
                              _mapController.move(s.position, math.max(_currentZoom, 15.0));
                            },
                            onLongPress: () => _openStreetView(context, s),
                            child: Center(
                              child: Container(
                                width: s == selectedStop ? 26 : 22,
                                height: s == selectedStop ? 26 : 22,
                                decoration: BoxDecoration(
                                  color: s == selectedStop ? s.mode.color : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: s == selectedStop ? Colors.white : s.mode.color,
                                    width: s == selectedStop ? 2.5 : 2.0,
                                  ),
                                  boxShadow: [
                                    if (s == selectedStop)
                                      BoxShadow(
                                        color: s.mode.color.withValues(alpha: 0.65),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    const BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                                  ],
                                ),
                                child: Icon(
                                  s.mode.icon,
                                  color: s == selectedStop ? Colors.white : s.mode.color,
                                  size: s == selectedStop ? 14 : 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 1) & 2) Valitun pysäkin label-merkki (kuten lähipysäkkikartalla), säilyy vaikka lista suljetaan x-ruksista
                    if (selectedStop != null)
                      _buildSelectedStopLabelMarker(
                        stop: selectedStop,
                        pattern: null,
                        lines: lines,
                      ),
                  ],
                ),

              // Oma sijainti
              if (loc.position != null)
                MarkerLayer(markers: [userMarker(loc.position!)]),

              buildAttribution(settings.tile),
            ],
          ),

          // 3) Yläosan hakupalkki ja hakutilavalitsin (Linja / Pysäkki)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showSearchCard)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 5) Hakutavan valitsin: Linja vs Pysäkki
                            Row(
                              children: [
                                SegmentedButton<LinesSearchMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: LinesSearchMode.line,
                                      label: Text('Linja', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      icon: Icon(Icons.directions_bus_rounded, size: 16),
                                    ),
                                    ButtonSegment(
                                      value: LinesSearchMode.stop,
                                      label: Text('Pysäkki', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      icon: Icon(Icons.pin_drop_rounded, size: 16),
                                    ),
                                  ],
                                  selected: {lines.searchMode},
                                  onSelectionChanged: (set) {
                                    final m = set.first;
                                    lines.setSearchMode(m);
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const Spacer(),
                                if (lines.isLoading)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: HslColors.primaryBlue),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Hakukenttä, x-ruksi nollaukseen ja Hae-painonappi
                            Row(
                              children: [
                                Icon(
                                  lines.searchMode == LinesSearchMode.line
                                      ? Icons.alt_route_rounded
                                      : Icons.place_rounded,
                                  color: HslColors.primaryBlue,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchCtrl,
                                    focusNode: _searchFocusNode,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      hintText: lines.searchMode == LinesSearchMode.line
                                          ? 'Hae linjaa (esim. 9, 550, 600)...'
                                          : 'Hae pysäkkiä tai koodia (esim. h080, H0801, Kamppi)...',
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    onChanged: (v) => setState(() {}),
                                    onSubmitted: (_) => _onSearch(lines),
                                  ),
                                ),
                                // 1) Tekstikentässä x ruksi nollausta varten
                                if (_searchCtrl.text.isNotEmpty || lines.query.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Tyhjennä hakukenttä',
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      lines.clearSearch();
                                      setState(() {});
                                    },
                                  ),
                                if (_searchFocusNode.hasFocus || isKeyboardVisible)
                                  IconButton(
                                    icon: const Icon(Icons.keyboard_hide_rounded, color: HslColors.primaryBlue, size: 20),
                                    tooltip: 'Sulje näppäimistö',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      _searchFocusNode.unfocus();
                                      FocusScope.of(context).unfocus();
                                    },
                                  ),
                                ElevatedButton(
                                  onPressed: () => _onSearch(lines),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: HslColors.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    minimumSize: const Size(0, 34),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Hae', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Virheilmoitus
                  if (lines.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Card(
                      color: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: HslColors.warningAmber),
                            const SizedBox(width: 8),
                            Expanded(child: Text(lines.errorMessage!, style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Useita linjoja löytyi -> valintapainikkeet
                  if (lines.searchMode == LinesSearchMode.line && lines.matchingLines.length > 1) ...[
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final l in lines.matchingLines)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(l.mode.icon, size: 14, color: l == selectedLine ? Colors.white : l.mode.color),
                                backgroundColor: l == selectedLine ? lineColor(l.mode, l.shortName) : null,
                                label: Text(
                                  l.shortName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: l == selectedLine ? Colors.white : null,
                                  ),
                                ),
                                onPressed: () async {
                                  final full = await lines.s.api.routeWithPatterns(l.gtfsId);
                                  lines.selectedLine = full ?? l;
                                  if (lines.selectedLine != null && lines.selectedLine!.patterns.isNotEmpty) {
                                    lines.selectedPattern = lines.selectedLine!.patterns.first;
                                    _fitPattern(lines.selectedPattern!);
                                  }
                                  setState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Useita pysäkkejä löytyi -> valintapainikkeet
                  if (lines.searchMode == LinesSearchMode.stop && lines.matchingStops.length > 1) ...[
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in lines.matchingStops)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(s.mode.icon, size: 14, color: s == selectedStop ? Colors.white : s.mode.color),
                                backgroundColor: s == selectedStop ? HslColors.primaryBlue : null,
                                label: Text(
                                  '${s.name}${s.code != null ? ' (${s.code})' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: s == selectedStop ? Colors.white : null,
                                  ),
                                ),
                                onPressed: () {
                                  lines.selectStop(s);
                                  _mapController.move(s.position, math.max(_currentZoom, 15.0));
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // Linjan suuntavalitsin (LinePattern)
                  if (selectedLine != null && selectedLine.patterns.length > 1) ...[
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in selectedLine.patterns)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                selected: p == selectedPattern,
                                selectedColor: lineColor(selectedLine.mode, selectedLine.shortName),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 14,
                                      color: p == selectedPattern ? Colors.white : null,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      p.headsign.isNotEmpty ? p.headsign : 'Suunta ${p.directionId + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: p == selectedPattern ? Colors.white : null,
                                      ),
                                    ),
                                  ],
                                ),
                                onSelected: (sel) {
                                  if (sel) {
                                    lines.selectPattern(p);
                                    _fitPattern(p);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Kartan apupainikkeet (Piilota hakukenttä, Oma sijainti, Sovita reitti)
          Positioned(
            right: 16,
            bottom: selectedStop != null ? 360 : 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'lines_toggle_header',
                  tooltip: _showSearchCard ? 'Piilota haku' : 'Näytä haku',
                  backgroundColor: Theme.of(context).cardColor,
                  child: Icon(
                    _showSearchCard ? Icons.expand_less : Icons.search_rounded,
                    color: HslColors.primaryBlue,
                  ),
                  onPressed: () => setState(() => _showSearchCard = !_showSearchCard),
                ),
                if (selectedPattern != null) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'lines_fit_route',
                    tooltip: 'Sovita koko linjareitti kartalle',
                    backgroundColor: Theme.of(context).cardColor,
                    child: const Icon(Icons.zoom_out_map_rounded, color: HslColors.primaryBlue),
                    onPressed: () => _fitPattern(selectedPattern),
                  ),
                ],
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'lines_locate',
                  backgroundColor: Theme.of(context).cardColor,
                  child: const Icon(Icons.my_location, color: HslColors.primaryBlue),
                  onPressed: () async {
                    await loc.locate();
                    if (!mounted) return;
                    final pos = loc.positionOrDefault;
                    _mapController.move(pos, 15.0);
                  },
                ),
              ],
            ),
          ),

          // Kelluva "Sulje näppäimistö" -painike
          if (isKeyboardVisible)
            Positioned(
              bottom: keyboardHeight + 10,
              right: 16,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).cardColor,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    _searchFocusNode.unfocus();
                    FocusScope.of(context).unfocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: HslColors.primaryBlue.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.keyboard_hide_rounded, size: 18, color: HslColors.primaryBlue),
                        SizedBox(width: 6),
                        Text(
                          'Sulje näppäimistö',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: HslColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 3) & 4) Kartan alapuolelle sijoittuva aikataulukortti valitulle pysäkille
          if (selectedStop != null && lines.isTimetableVisible)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _StopTimetableCard(
                stop: selectedStop,
                lines: lines,
                onClose: lines.clearSelectedStop,
                onStreetView: () => _openStreetView(context, selectedStop),
              ),
            ),

          // 2) Kun aikataululista on suljettu x-ruksista, pysäkki pysyy kartalla markeerattuna
          // ja näytetään pieni kelluva painike aikataulun avaamiseksi helposti uudelleen
          if (selectedStop != null && !lines.isTimetableVisible)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Center(
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.black87,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: lines.openTimetable,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(selectedStop.mode.icon, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedStop.name} aikataulu',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.expand_less_rounded, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Marker _buildPatternStopMarker({
    required Stop stop,
    required bool isTerminal,
    required bool isFirst,
    required bool isSelected,
    required TransitMode mode,
    required String lineName,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final color = isSelected ? stop.mode.color : lineColor(mode, lineName);
    final size = isSelected ? 22.0 : (isTerminal ? 20.0 : 13.0);

    return Marker(
      point: stop.position,
      width: isSelected ? 44.0 : size + 8,
      height: isSelected ? 44.0 : size + 8,
      alignment: Alignment.center,
      child: Tooltip(
        message: '${isTerminal ? (isFirst ? "Lähtöpysäkki: " : "Päätepysäkki: ") : ""}${stop.name}\n(Paina pitkään: Google Street View)',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isSelected
                    ? stop.mode.color
                    : (isTerminal ? color : Colors.white),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isSelected ? 2.5 : (isTerminal ? 2.5 : 2.0),
                ),
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: stop.mode.color.withValues(alpha: 0.7),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: isSelected ? 6 : 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: isTerminal && !isSelected
                  ? Icon(
                      isFirst ? Icons.trip_origin_rounded : Icons.flag_rounded,
                      size: 11,
                      color: Colors.white,
                    )
                  : (isSelected
                      ? Icon(stop.mode.icon, size: 13, color: Colors.white)
                      : null),
            ),
          ),
        ),
      ),
    );
  }

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
    final dLon = (next.longitude - prev.longitude) * 0.5;

    if (dLon.abs() > dLat.abs()) {
      return _LabelSide.top;
    }
    return _LabelSide.right;
  }

  Marker _buildSelectedStopLabelMarker({
    required Stop stop,
    required LinePattern? pattern,
    required LinesController lines,
  }) {
    final labelSide = _determineLabelSide(stop, pattern);
    return Marker(
      point: stop.position,
      width: labelSide == _LabelSide.right ? 280 : 240,
      height: labelSide == _LabelSide.right ? 64 : 90,
      alignment: labelSide == _LabelSide.right
          ? Alignment.centerLeft
          : Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!lines.isTimetableVisible) {
            lines.openTimetable();
          }
        },
        onLongPress: () => _openStreetView(context, stop),
        child: labelSide == _LabelSide.right
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 24),
                  const CustomPaint(
                    size: Size(6, 12),
                    painter: _PointerArrowPainter(
                      color: Colors.black87,
                      direction: _ArrowDirection.left,
                    ),
                  ),
                  _buildCalloutContent(stop, lines),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildCalloutContent(stop, lines),
                  const CustomPaint(
                    size: Size(12, 6),
                    painter: _PointerArrowPainter(
                      color: Colors.black87,
                      direction: _ArrowDirection.down,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildCalloutContent(Stop stop, LinesController lines) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stop.mode.icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    if (stop.code != null && stop.code!.isNotEmpty)
                      Text(
                        stop.code!,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    if (stop.platformCode != null && stop.platformCode!.isNotEmpty)
                      Text(
                        '• Laituri ${stop.platformCode}',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    if (stop.zoneId != null && stop.zoneId!.isNotEmpty)
                      Text(
                        '• ${stop.zoneId}',
                        style: const TextStyle(
                          color: Color(0xFF64B5F6),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.streetview_rounded, color: Colors.amber, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Google Street View',
            onPressed: () => _openStreetView(context, stop),
          ),
        ],
      ),
    );
  }
}

/// 3) & 4) & 6) Pysäkin vuoroaikataulu, arki- ja viikonloppuajat sekä lähtevät linjat
class _StopTimetableCard extends StatelessWidget {
  final Stop stop;
  final LinesController lines;
  final VoidCallback onClose;
  final VoidCallback? onStreetView;

  const _StopTimetableCard({
    required this.stop,
    required this.lines,
    required this.onClose,
    this.onStreetView,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pysäkin otsikkorivi ja 4) x-ruksi sulkemiseen
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: stop.mode.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(stop.mode.icon, color: stop.mode.color, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            if (stop.code != null && stop.code!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  'Pysäkki ${stop.code}',
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
                                ),
                              ),
                            if (stop.platformCode != null && stop.platformCode!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  'Laituri ${stop.platformCode}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodySmall?.color),
                                ),
                              ),
                            if (stop.zoneId != null && stop.zoneId!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: HslColors.primaryBlue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Vyöhyke ${stop.zoneId}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: HslColors.primaryBlue),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 3) Street View -painike
                  if (onStreetView != null)
                    IconButton(
                      icon: const Icon(Icons.streetview_rounded, color: Colors.amber, size: 22),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Google Street View',
                      onPressed: onStreetView,
                    ),
                  // 4) Aikataululistan x ruksi
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Sulje aikataululista',
                    onPressed: onClose,
                  ),
                ],
              ),

              const Divider(height: 12),

              // 6) & 7) Pysäkkihakutilassa: lista siitä pysäkistä lähtevistä eri linjoista
              if (stop.routes.isNotEmpty) ...[
                const Text(
                  'Pysäkiltä lähtevät linjat (valitse nähdäksesi reitin kartalla):',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final r in stop.routes)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: lines.selectedStopRoute == r
                                ? lineColor(r.mode, r.shortName)
                                : null,
                            avatar: Icon(
                              r.mode.icon,
                              size: 13,
                              color: lines.selectedStopRoute == r ? Colors.white : r.mode.color,
                            ),
                            label: Text(
                              '${r.shortName} ${r.headsign.isNotEmpty ? '➔ ${r.headsign}' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: lines.selectedStopRoute == r ? Colors.white : null,
                              ),
                            ),
                            // 7) Jos listan linja valittu, niin näytetään sen linjan reitti kartalla korostaen pysäkkiä
                            onPressed: () => lines.selectLineFromStop(r),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // 3) Aikatauluvalitsin: Tänään, Arkisin (Ma–Pe), Lauantaisin, Sunnuntaisin
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildDayChip(
                      label: 'Tänään',
                      type: TimetableDayType.today,
                      selected: lines.dayType == TimetableDayType.today,
                      onTap: () => lines.setDayType(TimetableDayType.today),
                    ),
                    _buildDayChip(
                      label: 'Arkisin (Ma–Pe)',
                      type: TimetableDayType.weekday,
                      selected: lines.dayType == TimetableDayType.weekday,
                      onTap: () => lines.setDayType(TimetableDayType.weekday),
                    ),
                    _buildDayChip(
                      label: 'Lauantaisin',
                      type: TimetableDayType.saturday,
                      selected: lines.dayType == TimetableDayType.saturday,
                      onTap: () => lines.setDayType(TimetableDayType.saturday),
                    ),
                    _buildDayChip(
                      label: 'Sunnuntaisin',
                      type: TimetableDayType.sunday,
                      selected: lines.dayType == TimetableDayType.sunday,
                      onTap: () => lines.setDayType(TimetableDayType.sunday),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Vuoroaikataulun lista
              Expanded(
                child: lines.isLoadingTimetable
                    ? const Center(child: CircularProgressIndicator(color: HslColors.primaryBlue))
                    : (lines.departures.isEmpty
                        ? const Center(
                            child: Text(
                              'Ei vuoroaikatauluja valitulle ajanjaksolle.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          )
                        : _buildTimetableList(context, lines.departures)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayChip({
    required String label,
    required TimetableDayType type,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        visualDensity: VisualDensity.compact,
        selected: selected,
        selectedColor: HslColors.primaryBlue,
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : null,
          ),
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildTimetableList(BuildContext context, List<Departure> departures) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: departures.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final d = departures[idx];
        final timeStr = hm(d.realtime);
        final schedStr = hm(d.scheduled);
        final delayMin = (d.delaySeconds / 60).round();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              LineBadge(mode: d.mode, line: d.line, small: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.headsign,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (d.isRealtime) ...[
                        const Icon(Icons.sensors, size: 12, color: HslColors.successGreen),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: d.isRealtime ? HslColors.primaryBlue : null,
                        ),
                      ),
                    ],
                  ),
                  if (d.isRealtime && delayMin != 0)
                    Text(
                      delayMin > 0 ? '+$delayMin min' : '$delayMin min',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: delayMin > 2 ? HslColors.safetyRed : HslColors.warningAmber,
                      ),
                    )
                  else if (schedStr != timeStr)
                    Text(
                      'Aikataulu $schedStr',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _LabelSide { right, top }

enum _ArrowDirection { down, left, right }

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
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.direction != direction;
}
