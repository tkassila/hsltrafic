import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../core/localization.dart';
import '../../models/line.dart';
import '../../models/place_stop.dart';
import '../../models/transit_mode.dart';
import '../../models/vehicle.dart';
import '../../shared/base_map.dart';
import '../../shared/mode_style.dart';
import '../../shared/region_selector.dart';
import '../../shared/street_view.dart';
import '../../shared/widgets.dart';
import '../../state/app_state.dart';
import '../../state/live_map_controller.dart';
import '../../theme/hsl_colors.dart';

class LiveMapView extends StatefulWidget {
  const LiveMapView({super.key});

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final TextEditingController _filterCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final AnimationController _flashCtrl;
  bool _pendingFitToSearch = false;
  bool _isSearching = false;
  bool _showSearchHeader = true;
  double _currentZoom = 14.5;
  bool _wasActive = false;
  bool _hasCenteredOnGps = false;
  LiveMapController? _liveRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _liveRef = context.read<LiveMapController>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = context.read<LocationController>();
      final live = context.read<LiveMapController>();
      final pos = loc.positionOrDefault;
      live.center = pos;
      live.radius = 5000;
      _mapController.move(pos, 14.0);
      if (live.isActive) {
        live.setArea(pos, 5000, force: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _liveRef?.setAppPaused(true);
    } else if (state == AppLifecycleState.resumed) {
      _liveRef?.setAppPaused(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocusNode.dispose();
    _liveRef?.cancelPendingTimers();
    _flashCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _flashMap() {
    _flashCtrl.forward(from: 0.0);
  }

  void _fitToVehicles(List<Vehicle> matching) {
    if (!mounted || matching.isEmpty) return;
    if (matching.length == 1) {
      _mapController.move(matching.first.position, math.max(_mapController.camera.zoom, 14.5));
    } else {
      final bounds = LatLngBounds.fromPoints(matching.map((v) => v.position).toList());
      if (bounds.southWest == bounds.northEast) {
        _mapController.move(matching.first.position, math.max(_mapController.camera.zoom, 14.5));
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(48),
            maxZoom: 15.5,
          ),
        );
      }
    }
  }

  /// Keskeyttää "Kaikkia"-haun tai linjakyselyn ja palauttaa oletustilan
  Future<void> _cancelCurrentSearch() async {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    final live = context.read<LiveMapController>();
    final loc = context.read<LocationController>();

    _filterCtrl.clear();
    _pendingFitToSearch = false;
    if (mounted) setState(() => _isSearching = false);

    live.cancelSearch();
    final pos = loc.positionOrDefault;
    live.center = pos;
    live.setArea(pos, 5000, force: true);
    await live.search('');
  }

  Future<void> _runSearch() async {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    final live = context.read<LiveMapController>();
    final loc = context.read<LocationController>();

    // 1) Visuaalinen välähdys kartalle haun osoittamiseksi
    _flashMap();

    final query = _filterCtrl.text.trim();
    final hasQuery = query.isNotEmpty;
    _pendingFitToSearch = hasQuery;

    if (mounted) setState(() => _isSearching = true);

    // 2) Keskitetään kartta sen hetken omaan sijaintiin (ei jumiteta linjahakua hitaaseen GPS-lukitukseen,
    // jos sijainti on jo tiedossa)
    if (loc.position == null && !hasQuery) {
      try {
        await loc.locate();
      } catch (_) {}
    } else {
      loc.locate().catchError((_) {});
    }
    if (!mounted) return;

    final pos = loc.positionOrDefault;
    live.center = pos;
    _mapController.move(pos, math.max(_mapController.camera.zoom, 14.5));

    // 3) Suoritetaan haku välittömästi
    try {
      if (!hasQuery) {
        live.setArea(pos, 5000, force: true);
        await live.search('');
      } else {
        await live.search(query);
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }

    if (!mounted) return;
    final matching = live.vehicles;
    if (hasQuery && matching.isNotEmpty) {
      _pendingFitToSearch = false;
      _fitToVehicles(matching);
    }
  }

  /// "Kaikkia"-painonappi: hakee kaikkien 1-kohdan lähipysäkkilinjojen live-seurannassa olevat vuorot.
  Future<void> _runAllNearbySearch() async {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    final live = context.read<LiveMapController>();
    final loc = context.read<LocationController>();

    _flashMap();
    _filterCtrl.clear();
    _pendingFitToSearch = true;
    if (mounted) setState(() => _isSearching = true);

    loc.locate().catchError((_) {});
    final pos = loc.positionOrDefault;
    live.center = pos;

    try {
      await live.searchAllNearbyLines();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }

    if (!mounted) return;
    final matching = live.vehicles;
    if (matching.isNotEmpty) {
      _pendingFitToSearch = false;
      _fitToVehicles(matching);
    } else {
      _mapController.move(pos, math.max(_mapController.camera.zoom, 14.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveMapController>();
    final settings = context.watch<SettingsController>();
    final loc = context.watch<LocationController>();

    final selected = live.selected;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    // 1) IndexedStack + GPS-synkronointi: kun puhelin saa ensimmäisen oikean GPS-sijainnin,
    // tai kun käyttäjä siirtyy Live-kartta-välilehdelle, siirretään kamera ja aluetilaus oikeaan sijaintiin.
    if (loc.position != null && !_hasCenteredOnGps) {
      _hasCenteredOnGps = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final gpsPos = loc.position!;
        live.center = gpsPos;
        _mapController.move(gpsPos, math.max(_mapController.camera.zoom, 14.5));
        if (live.isActive) {
          live.setArea(gpsPos, 5000, force: true);
        }
      });
    }

    if (live.isActive && !_wasActive) {
      _wasActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (loc.position == null) {
          try {
            await loc.locate();
          } catch (_) {}
        }
        if (!mounted) return;
        final pos = loc.position ?? live.center;
        live.center = pos;
        _mapController.move(pos, math.max(_mapController.camera.zoom, 14.5));
        live.setArea(pos, 5000, force: true);
      });
    } else if (!live.isActive && _wasActive) {
      _wasActive = false;
    }

    // Kun haetun linjan ajoneuvot saapuvat HFP-virrasta, sovitetaan kartta niihin
    if (_pendingFitToSearch && live.vehicles.isNotEmpty) {
      _pendingFitToSearch = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitToVehicles(live.vehicles);
      });
    }

    // Follow vehicle logic
    if (live.follow && selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(selected.position, _mapController.camera.zoom);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // Open Source Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: loc.positionOrDefault,
              initialZoom: 14.5,
              minZoom: 10,
              maxZoom: 19,
              onPositionChanged: (pos, hasGesture) {
                final zoom = pos.zoom;
                if ((zoom - _currentZoom).abs() >= 0.35) {
                  setState(() => _currentZoom = zoom);
                }
                if (hasGesture) {
                  if (_searchFocusNode.hasFocus) {
                    _searchFocusNode.unfocus();
                  }
                  // Calculate radius based on visible bounds or zoom
                  final radiusMeters = (1500000 / math.pow(2, zoom)).clamp(500.0, 6000.0);
                  live.setArea(pos.center, radiusMeters);
                }
              },
              onTap: (_, _) {
                // Jos näppäimistö on näkyvissä, suljetaan se vaikuttamatta kartan tilaan tai valintoihin
                if (_searchFocusNode.hasFocus || MediaQuery.of(context).viewInsets.bottom > 0) {
                  _searchFocusNode.unfocus();
                  FocusScope.of(context).unfocus();
                  return;
                }
                if (live.selectedStop != null) {
                  live.clearSelectedStop();
                } else if (live.selectedId != null || live.selectedPattern != null) {
                  live.clearSelection();
                }
              },
            ),
            children: [
              buildTileLayer(settings.tile),

              // Valitun vuoron reittiviiva kartalle
              if (live.selectedPattern != null && live.selectedPattern!.geometry.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: live.selectedPattern!.geometry,
                      strokeWidth: 7.0,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    Polyline(
                      points: live.selectedPattern!.geometry,
                      strokeWidth: 4.5,
                      color: lineColor(
                        selected?.mode ?? live.selectedLine?.mode ?? TransitMode.bus,
                        selected?.line ?? live.selectedLine?.shortName ?? '',
                      ),
                    ),
                  ],
                ),

              // Valitun vuoron pysäkit kartalle
              if (live.selectedPattern != null && live.selectedPattern!.stops.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final s in live.selectedPattern!.stops)
                      Marker(
                        point: s.position,
                        width: (s.gtfsId == live.selectedStop?.gtfsId)
                            ? 22
                            : ((s.gtfsId == (live.nextStopTime?.stop.gtfsId ?? live.nextStopFallback?.gtfsId))
                                ? 16
                                : 10),
                        height: (s.gtfsId == live.selectedStop?.gtfsId)
                            ? 22
                            : ((s.gtfsId == (live.nextStopTime?.stop.gtfsId ?? live.nextStopFallback?.gtfsId))
                                ? 16
                                : 10),
                        child: Tooltip(
                          message: '${s.name}\n(Paina pitkään: Google Street View)',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final matching = live.tripTimes.where((t) => t.stop.gtfsId == s.gtfsId).firstOrNull;
                              live.selectStop(s, matching);
                              if (live.selectedStop != null) {
                                _mapController.move(
                                  s.position,
                                  math.max(_mapController.camera.zoom, 15.0),
                                );
                              }
                            },
                            onLongPress: () {
                              openGoogleStreetView(context, position: s.position, stopName: s.name);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: (s.gtfsId == live.selectedStop?.gtfsId)
                                    ? HslColors.primaryBlue
                                    : ((s.gtfsId == (live.nextStopTime?.stop.gtfsId ?? live.nextStopFallback?.gtfsId))
                                        ? HslColors.primaryBlue
                                        : Colors.white),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (s.gtfsId == live.selectedStop?.gtfsId)
                                      ? Colors.white
                                      : lineColor(
                                          selected?.mode ?? live.selectedLine?.mode ?? TransitMode.bus,
                                          selected?.line ?? live.selectedLine?.shortName ?? '',
                                        ),
                                  width: (s.gtfsId == live.selectedStop?.gtfsId)
                                      ? 3.0
                                      : ((s.gtfsId == (live.nextStopTime?.stop.gtfsId ?? live.nextStopFallback?.gtfsId))
                                          ? 2.5
                                          : 2.0),
                                ),
                                boxShadow: (s.gtfsId == live.selectedStop?.gtfsId)
                                    ? const [
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 5,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

              // Käyttäjän valitsema pysäkki vuoron linjalta korostettuna merkkinä ja infolaatikkona kartalla
              if (live.selectedStop != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: live.selectedStop!.position,
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Tooltip(
                        message: '${live.selectedStop!.name}\n(Paina pitkään: Google Street View)',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () {
                            openGoogleStreetView(context, position: live.selectedStop!.position, stopName: live.selectedStop!.name);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: HslColors.primaryBlue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              live.selectedStop!.mode.icon,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _buildSelectedStopCallout(
                      live.selectedStop!,
                      live.selectedTripStopTime,
                      live.tripTimes,
                      live.selectedPattern?.stops ?? const [],
                    ),
                  ],
                ),

              // User location dot
              if (loc.position != null)
                MarkerLayer(markers: [userMarker(loc.position!)]),

              // Vehicles Markers (skaalautuva koko zoom-tason mukaan + 3x suuntanuoli).
              // Ankkurointi: flutter_map sijoittaa pisteen (v.position) kohtaan (right, bottom),
              // missä top = 0.5 * h * (alignment.y + 1) ja bottom = h - top.
              // Kun 38x38-ajoneuvokuvake on laatikon alareunassa (keskipiste 19 px alareunasta eli h - 19 ylhäältä),
              // alignment.y = (38 / h) - 1 asettaa pyöreän ajoneuvokuvakkeen keskipisteen täsmälleen tien keskilinjalle!
              MarkerLayer(
                markers: [
                  for (final v in live.vehicles)
                    Marker(
                      point: v.position,
                      width: (_currentZoom < 13.0 && v.id != live.selectedId) ? 72 : 124,
                      height: (_currentZoom < 13.0 && v.id != live.selectedId) ? 58 : 68,
                      alignment: Alignment(
                        0.0,
                        (38.0 / ((_currentZoom < 13.0 && v.id != live.selectedId) ? 58.0 : 68.0)) - 1.0,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          live.select(v);
                          _mapController.move(
                            v.position,
                            math.max(_mapController.camera.zoom, 15.0),
                          );
                        },
                        child: _VehicleMarkerWidget(
                          vehicle: v,
                          isSelected: v.id == live.selectedId,
                          isCompact: _currentZoom < 13.0 && v.id != live.selectedId,
                        ),
                      ),
                    ),
                ],
              ),

              buildAttribution(settings.tile),
            ],
          ),

          // Kartan välähdysanimaatio haun merkiksi
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _flashCtrl,
              builder: (context, _) {
                if (_flashCtrl.value == 0.0 || _flashCtrl.value == 1.0) {
                  return const SizedBox.shrink();
                }
                final opacity = (1.0 - _flashCtrl.value) * 0.35;
                return IgnorePointer(
                  child: Container(
                    color: HslColors.primaryBlue.withValues(alpha: opacity),
                  ),
                );
              },
            ),
          ),

          // Top Header & Mode Filter Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showSearchHeader) ...[
                    // Search & status bar
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.search_rounded, color: HslColors.primaryBlue),
                              tooltip: 'Käynnistä haku',
                              visualDensity: VisualDensity.compact,
                              onPressed: _runSearch,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _filterCtrl,
                                focusNode: _searchFocusNode,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: live.isAllNearbyLinesActive
                                      ? 'Kaikki lähipysäkkien linjat aktiivisena'
                                      : '${AppStrings.get('search_line_placeholder')} (esim. 9, 69)',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onChanged: (v) {
                                  setState(() {});
                                  if (v.trim().isEmpty && live.lineFilter.isNotEmpty) {
                                    live.setLineFilter('');
                                  }
                                },
                                onSubmitted: (_) => _runSearch(),
                              ),
                            ),
                            // Keskeytä / tyhjennä x-ruksi, kun hakukentässä on tekstiä tai kun "Kaikkia" on aktiivisena/haussa
                            if (_filterCtrl.text.isNotEmpty || live.isAllNearbyLinesActive)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                tooltip: live.isAllNearbyLinesActive ? 'Keskeytä Kaikkia-haku' : 'Tyhjennä haku',
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  if (live.isAllNearbyLinesActive) {
                                    _cancelCurrentSearch();
                                  } else {
                                    _filterCtrl.clear();
                                    _pendingFitToSearch = false;
                                    setState(() {});
                                    _runSearch();
                                  }
                                },
                              ),
                            // Sulje näppäimistö -painike hakurivissä vaikuttamatta karttaan
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
                              onPressed: _runSearch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: HslColors.primaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: const Size(0, 34),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _isSearching
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Hae', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (live.connected || live.vehicles.isNotEmpty)
                                    ? HslColors.successGreen.withValues(alpha: 0.15)
                                    : HslColors.warningAmber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (live.connected || live.vehicles.isNotEmpty)
                                          ? HslColors.successGreen
                                          : HslColors.warningAmber,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${live.vehicles.length}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: (live.connected || live.vehicles.isNotEmpty)
                                          ? HslColors.successGreen
                                          : HslColors.warningAmber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Mode Chips & Region Selector
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: TransitRegionSelectorPill(compact: true),
                          ),
                          for (final mode in [
                            TransitMode.bus,
                            TransitMode.tram,
                            TransitMode.metro,
                            TransitMode.rail,
                            TransitMode.ferry,
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(mode.icon, size: 16, color: live.modes.contains(mode) ? Colors.white : mode.color),
                                    const SizedBox(width: 4),
                                    Text(
                                      mode.label,
                                      style: TextStyle(
                                        color: live.modes.contains(mode) ? Colors.white : null,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                selected: live.modes.contains(mode),
                                selectedColor: mode.color,
                                checkmarkColor: Colors.white,
                                onSelected: (_) => live.toggleMode(mode),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Pikavalinnat: "Kaikkia"-painonappi + viimeksi haetut linjat & lähimmät aktiiviset linjat
                    if (live.recentSearches.isNotEmpty || live.nearbyShortNames.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // 2) "Kaikkia"-painonappi, jolla haetaan 1-kohdan kaikkien linjojen live-seurannassa olevat vuorot
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(
                                  live.isAllNearbyLinesActive
                                      ? Icons.close_rounded
                                      : Icons.directions_transit_rounded,
                                  size: 14,
                                  color: (live.isAllNearbyLinesActive || live.lineFilter.trim().isEmpty)
                                      ? Colors.white
                                      : HslColors.primaryBlue,
                                ),
                                backgroundColor: (live.isAllNearbyLinesActive || live.lineFilter.trim().isEmpty)
                                    ? HslColors.primaryBlue
                                    : null,
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Kaikkia',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: (live.isAllNearbyLinesActive || live.lineFilter.trim().isEmpty)
                                            ? Colors.white
                                            : null,
                                      ),
                                    ),
                                    if (live.isAllNearbyLinesActive) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.close, size: 12, color: Colors.white),
                                    ],
                                  ],
                                ),
                                onPressed: () {
                                  if (live.isAllNearbyLinesActive) {
                                    _cancelCurrentSearch();
                                  } else {
                                    _runAllNearbySearch();
                                  }
                                },
                              ),
                            ),
                            for (final recent in live.recentSearches)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    Icons.history,
                                    size: 14,
                                    color: live.lineFilter.toUpperCase() == recent.toUpperCase()
                                        ? Colors.white
                                        : HslColors.primaryBlue,
                                  ),
                                  backgroundColor: live.lineFilter.toUpperCase() == recent.toUpperCase()
                                      ? HslColors.primaryBlue
                                      : null,
                                  label: Text(
                                    recent,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: live.lineFilter.toUpperCase() == recent.toUpperCase()
                                          ? Colors.white
                                          : null,
                                    ),
                                  ),
                                  onPressed: () {
                                    if (live.lineFilter.toUpperCase() == recent.toUpperCase()) {
                                      _filterCtrl.clear();
                                    } else {
                                      _filterCtrl.text = recent;
                                    }
                                    setState(() {});
                                    _runSearch();
                                  },
                                ),
                              ),
                            for (final nearLine in live.nearbyShortNames
                                .where((n) => !live.recentSearches.contains(n.toUpperCase())))
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: live.lineFilter.toUpperCase() == nearLine.toUpperCase()
                                      ? HslColors.primaryBlue
                                      : null,
                                  label: Text(
                                    nearLine,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: live.lineFilter.toUpperCase() == nearLine.toUpperCase()
                                          ? Colors.white
                                          : null,
                                    ),
                                  ),
                                  onPressed: () {
                                    if (live.lineFilter.toUpperCase() == nearLine.toUpperCase()) {
                                      _filterCtrl.clear();
                                    } else {
                                      _filterCtrl.text = nearLine;
                                    }
                                    setState(() {});
                                    _runSearch();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  // Ilmoitus, kun haetun linjan tai Kaikkia-haun vuoroja etsitään tai niitä ei ole ajossa
                  if ((live.lineFilter.trim().isNotEmpty || live.isAllNearbyLinesActive) && live.vehicles.isEmpty) ...[
                    const SizedBox(height: 6),
                    if (live.isSearchingRoutes || live.isAwaitingHfpVehicles || _isSearching)
                      Card(
                        elevation: 3,
                        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: HslColors.primaryBlue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  live.isAllNearbyLinesActive
                                      ? 'Haetaan kaikkien lähipysäkkien linjojen ajossa olevia vuoroja...'
                                      : 'Haetaan linjan "${live.lineFilter}" ajossa olevia vuoroja...',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                tooltip: 'Keskeytä kysely',
                                visualDensity: VisualDensity.compact,
                                onPressed: _cancelCurrentSearch,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        elevation: 3,
                        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18, color: HslColors.warningAmber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  live.isAllNearbyLinesActive
                                      ? 'Lähipysäkkien linjoilla ei ole tällä hetkellä ajossa olevia vuoroja.'
                                      : 'Linjalla "${live.lineFilter}" ei ole tällä hetkellä ajossa olevia vuoroja.',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                tooltip: 'Sulje ilmoitus',
                                visualDensity: VisualDensity.compact,
                                onPressed: _cancelCurrentSearch,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // Map Action Buttons (Toggle Search Header & Locate me)
          Positioned(
            right: 16,
            bottom: isKeyboardVisible ? (keyboardHeight + 56) : (selected != null ? 240 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'live_toggle_header',
                  tooltip: _showSearchHeader ? 'Piilota hakukentät' : 'Näytä hakukentät',
                  backgroundColor: Theme.of(context).cardColor,
                  child: Icon(
                    _showSearchHeader ? Icons.expand_less : Icons.search_rounded,
                    color: HslColors.primaryBlue,
                  ),
                  onPressed: () => setState(() => _showSearchHeader = !_showSearchHeader),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'live_locate',
                  backgroundColor: Theme.of(context).cardColor,
                  child: const Icon(Icons.my_location, color: HslColors.primaryBlue),
                  onPressed: () async {
                    await loc.locate();
                    if (!mounted) return;
                    final pos = loc.positionOrDefault;
                    _mapController.move(pos, 14.5);
                    live.setArea(pos, 5000, force: true);
                  },
                ),
              ],
            ),
          ),

          // Kelluva "Sulje näppäimistö" -painike suoraan näppäimistön yläpuolelle
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

          // Floating Route Banner kun linja on näkyvissä mutta vuorolista on suljettu ruksista
          if (live.selectedPattern != null && !live.isVehicleCardVisible)
            Positioned(
              top: 76,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LineBadge(
                      mode: selected?.mode ?? live.selectedLine?.mode ?? TransitMode.bus,
                      line: selected?.line ?? live.selectedLine?.shortName ?? '',
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        final sel = selected;
                        if (sel != null) {
                          live.select(sel);
                        } else {
                          live.showVehicleCard();
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (selected?.headsign.isNotEmpty == true)
                                ? selected!.headsign
                                : (live.selectedPattern?.headsign ?? ''),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.info_outline, size: 15, color: HslColors.ferryCyan),
                          const SizedBox(width: 2),
                          const Text('Avaa lista', style: TextStyle(color: HslColors.ferryCyan, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: live.clearSelection,
                      child: const Icon(Icons.close, size: 16, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

          // 2) Bottom Detail Card for Selected Vehicle (suljetaan x-ruksista, jolloin linjakartta jää näkyviin)
          if (selected != null && live.isVehicleCardVisible)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _VehicleDetailCard(
                vehicle: selected,
                line: live.selectedLine,
                pattern: live.selectedPattern,
                times: live.tripTimes,
                upcomingStops: live.upcomingStopTimes,
                nextStopTime: live.nextStopTime,
                nextStopFallback: live.nextStopFallback,
                selectedStop: live.selectedStop,
                onStopSelected: (stop, time) {
                  live.selectStop(stop, time);
                  if (live.selectedStop != null) {
                    _mapController.move(
                      stop.position,
                      math.max(_mapController.camera.zoom, 15.0),
                    );
                  }
                },
                loading: live.loadingSelection,
                isFollowing: live.follow,
                onFollowToggle: live.toggleFollow,
                onClose: live.closeVehicleCard,
              ),
            ),
        ],
      ),
    );
  }

  /// 1) Rakentaa live-pysäkin callout-infokuplan siten, että 2 tai useammat labelit
  /// (nimi, pysäkkikoodi, saapumisajat tai useammat laiturit) asetetaan aina allekkain, ei päällekkäin!
  Marker _buildSelectedStopCallout(
    Stop stop,
    TripStopTime? time,
    List<TripStopTime> allTimes,
    List<Stop> patternStops,
  ) {
    // Etsitään kaikki tämän pysäkkialueen pysäkkiajat (samannimiset tai < 40 m etäisyydellä olevat)
    final matchingVisits = allTimes.where((t) {
      if (t.stop.gtfsId == stop.gtfsId) return true;
      if (t.stop.name.toLowerCase() == stop.name.toLowerCase()) return true;
      return distanceMeters(t.stop.position, stop.position) < 40;
    }).toList();

    // Etsitään kaikki tämän pysäkkialueen pysäkit linjakuvasta
    final matchingStops = patternStops.where((s) {
      if (s.gtfsId == stop.gtfsId) return true;
      if (s.name.toLowerCase() == stop.name.toLowerCase()) return true;
      return distanceMeters(s.position, stop.position) < 40;
    }).toList();

    final count = math.max(
      1,
      matchingVisits.isNotEmpty ? matchingVisits.length : matchingStops.length,
    );
    final calloutHeight = 54.0 + (count * 34.0);

    return Marker(
      point: stop.position,
      width: 270,
      height: calloutHeight,
      alignment: Alignment(0.0, -1.0 - (16.0 / calloutHeight)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          openGoogleStreetView(context, position: stop.position, stopName: stop.name);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      stop.mode.icon,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pysäkin / aseman pääotsikko
                        Text(
                          stop.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Kaikki 2 tai useammat labelit selkeästi allekkain (ei päällekkäin!)
                        if (matchingVisits.isNotEmpty) ...[
                          for (var i = 0; i < matchingVisits.length; i++) ...[
                            if (i > 0)
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 2.5),
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            _buildStopLabelRow(matchingVisits[i].stop, matchingVisits[i]),
                          ],
                        ] else if (matchingStops.isNotEmpty) ...[
                          for (var i = 0; i < matchingStops.length; i++) ...[
                            if (i > 0)
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 2.5),
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            _buildStopLabelRow(matchingStops[i], time),
                          ],
                        ] else ...[
                          _buildStopLabelRow(stop, time),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.streetview_rounded, color: Colors.amber, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: 'Google Street View',
                    onPressed: () => openGoogleStreetView(context, position: stop.position, stopName: stop.name),
                  ),
                ],
              ),
            ),
            const CustomPaint(
              size: Size(10, 6),
              painter: _PointerArrowDownPainter(color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopLabelRow(Stop s, TripStopTime? t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.code != null && s.code!.isNotEmpty)
          Text(
            'Pysäkki ${s.code}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (t != null)
          Text(
            'Saapuu ${hm(t.realtime)}',
            style: const TextStyle(
              color: HslColors.ferryCyan,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}

/// Kulkusuuntaa osoittava siisti pieni nuoli vuororenkaan eteen
class _DirectionArrowPainter extends CustomPainter {
  final Color color;
  final Color strokeColor;

  const _DirectionArrowPainter({required this.color, required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    // Nuoli osoittaa ylös suoraan kulkusuuntaan
    path.moveTo(w / 2, 0); // Kärki eteenpäin
    path.lineTo(w, h);
    path.lineTo(w / 2, h * 0.65); // Tyven viisto
    path.lineTo(0, h);
    path.close();

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawPath(path.shift(const Offset(0, 1.0)), shadowPaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_DirectionArrowPainter oldDelegate) =>
      color != oldDelegate.color || strokeColor != oldDelegate.strokeColor;
}

class _VehicleMarkerWidget extends StatelessWidget {
  final Vehicle vehicle;
  final bool isSelected;
  final bool isCompact;

  const _VehicleMarkerWidget({
    required this.vehicle,
    required this.isSelected,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = lineColor(vehicle.mode, vehicle.line);
    final delayCol = vehicleStatusColor(vehicle);

    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Päällä: a) Linjanumero + b) Vuoron määränpää (kun ei tiivistetyssä kaukozoomissa) + viiveindikaattori
        Container(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 4 : 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.white : delayCol,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vehicle.line,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: vehicle.line.length > 3 ? 9 : (isCompact ? 10 : 11),
                ),
              ),
              if (!isCompact && vehicle.headsign.isNotEmpty) ...[
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 68),
                  child: Text(
                    vehicle.headsign,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(width: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: delayCol,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 1),

        // Alinna: Vuororengas + liikkeessä olevan vuoron kulkusuuntaa osoittava 3x suurempi nuoli renkaan eteen
        SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1) 3x suurempi nuoli vuororenkaan eteen (näytetään liikkeessä olevalle vuorolle, ei päätepysäkillä 0 km/h)
              if (vehicle.showHeadingArrow)
                Transform.rotate(
                  angle: vehicle.heading * math.pi / 180.0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: CustomPaint(
                      size: const Size(24, 18),
                      painter: _DirectionArrowPainter(
                        color: baseColor,
                        strokeColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Vuororengas: 20x20 pyöreä ikoni
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: baseColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    vehicle.mode.icon,
                    size: 12,
                    color: baseColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VehicleDetailCard extends StatefulWidget {
  final Vehicle vehicle;
  final LineInfo? line;
  final LinePattern? pattern;
  final List<TripStopTime> times;
  final List<TripStopTime> upcomingStops;
  final TripStopTime? nextStopTime;
  final Stop? nextStopFallback;
  final Stop? selectedStop;
  final void Function(Stop stop, TripStopTime? time)? onStopSelected;
  final bool loading;
  final bool isFollowing;
  final VoidCallback onFollowToggle;
  final VoidCallback onClose;

  const _VehicleDetailCard({
    required this.vehicle,
    required this.line,
    required this.pattern,
    required this.times,
    this.upcomingStops = const [],
    this.nextStopTime,
    this.nextStopFallback,
    this.selectedStop,
    this.onStopSelected,
    required this.loading,
    required this.isFollowing,
    required this.onFollowToggle,
    required this.onClose,
  });

  @override
  State<_VehicleDetailCard> createState() => _VehicleDetailCardState();
}

class _VehicleDetailCardState extends State<_VehicleDetailCard> {
  bool _showAllStops = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vehicle = widget.vehicle;
    final line = widget.line;
    final pattern = widget.pattern;
    final times = widget.times;
    final upcomingStops = widget.upcomingStops;
    final nextStopTime = widget.nextStopTime;
    final nextStopFallback = widget.nextStopFallback;
    final delayCol = vehicleStatusColor(vehicle);
    final destinationName = resolveDestinationHeadsign(
      headsign: vehicle.headsign.isNotEmpty
          ? vehicle.headsign
          : (pattern != null && pattern.headsign.isNotEmpty
              ? pattern.headsign
              : (times.isNotEmpty ? times.last.stop.name : '')),
      routeLongName: line?.longName,
      directionId: vehicle.direction,
    );

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: a) Line badge (linjan numero), b) destination headsign (määränpää), close button
            Row(
              children: [
                LineBadge(mode: vehicle.mode, line: vehicle.line),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destinationName.isNotEmpty ? destinationName : vehicle.line,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: delayCol),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            vehicleStatusText(vehicle),
                            style: TextStyle(fontSize: 12, color: delayCol, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${vehicle.speedKmh.round()} km/h',
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                          if (vehicle.occupancy != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.people_alt_rounded,
                              size: 13,
                              color: vehicle.occupancy! > 75
                                  ? HslColors.safetyRed
                                  : (vehicle.occupancy! > 35 ? HslColors.warningAmber : HslColors.successGreen),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${vehicle.occupancy}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: vehicle.occupancy! > 75
                                    ? HslColors.safetyRed
                                    : (vehicle.occupancy! > 35 ? HslColors.warningAmber : HslColors.successGreen),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Next Stop & Route Progress
            if (widget.loading)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (nextStopTime != null) ...[
              Text(
                vehicle.isWaitingForDeparture ? 'Lähtöpysäkki:' : '${AppStrings.get('next_stop')}:',
                style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onStopSelected?.call(nextStopTime.stop, nextStopTime),
                  onLongPress: () => openGoogleStreetView(context, position: nextStopTime.stop.position, stopName: nextStopTime.stop.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.selectedStop?.gtfsId == nextStopTime.stop.gtfsId
                          ? HslColors.primaryBlue.withValues(alpha: 0.12)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      border: widget.selectedStop?.gtfsId == nextStopTime.stop.gtfsId
                          ? Border.all(color: HslColors.primaryBlue, width: 1.5)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.selectedStop?.gtfsId == nextStopTime.stop.gtfsId
                              ? Icons.place
                              : Icons.fmd_good,
                          size: 16,
                          color: HslColors.primaryBlue,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            nextStopTime.stop.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        if (widget.selectedStop?.gtfsId == nextStopTime.stop.gtfsId) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: HslColors.primaryBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Kartalla',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        Text(
                          hm(nextStopTime.realtime),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: HslColors.primaryBlue),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else if (nextStopFallback != null) ...[
              Text(
                '${AppStrings.get('next_stop')}:',
                style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.fmd_good, size: 16, color: HslColors.primaryBlue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      nextStopFallback.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ] else if (pattern != null && pattern.stops.isNotEmpty) ...[
              Text(
                'Päätepysäkki: ${pattern.stops.last.name}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],

            // Laajennettava lista tulevista pysäkeistä saapumisajoilla
            if (_showAllStops && upcomingStops.length > 1) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: upcomingStops.length,
                  itemBuilder: (context, i) {
                    final st = upcomingStops[i];
                    final isNext = i == 0;
                    final isSelected = widget.selectedStop?.gtfsId == st.stop.gtfsId;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => widget.onStopSelected?.call(st.stop, st),
                        onLongPress: () => openGoogleStreetView(context, position: st.stop.position, stopName: st.stop.name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? HslColors.primaryBlue.withValues(alpha: 0.12)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: HslColors.primaryBlue, width: 1.2)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.place
                                    : (isNext ? Icons.radio_button_checked : Icons.circle_outlined),
                                size: isSelected ? 14 : 12,
                                color: isSelected
                                    ? HslColors.primaryBlue
                                    : (isNext ? HslColors.primaryBlue : theme.hintColor),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  st.stop.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: (isSelected || isNext) ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? HslColors.primaryBlue : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: HslColors.primaryBlue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Kartalla',
                                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                              Text(
                                hm(st.realtime),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: (isSelected || isNext) ? FontWeight.bold : FontWeight.w500,
                                  color: (isSelected || isNext) ? HslColors.primaryBlue : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 10),
            // Action Buttons (Follow vehicle, Show all stops)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(widget.isFollowing ? Icons.location_disabled : Icons.navigation_rounded, size: 16),
                    label: Text(widget.isFollowing ? 'Lopeta seuranta' : AppStrings.get('follow_vehicle')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.isFollowing ? HslColors.safetyRed : HslColors.primaryBlue,
                      side: BorderSide(color: widget.isFollowing ? HslColors.safetyRed : HslColors.primaryBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: widget.onFollowToggle,
                  ),
                ),
                if (upcomingStops.length > 1) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: Icon(_showAllStops ? Icons.expand_less : Icons.format_list_bulleted, size: 16),
                    label: Text(_showAllStops ? 'Piilota' : 'Pysäkit (${upcomingStops.length})'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HslColors.primaryBlue,
                      side: const BorderSide(color: HslColors.primaryBlue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => setState(() => _showAllStops = !_showAllStops),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PointerArrowDownPainter extends CustomPainter {
  final Color color;
  const _PointerArrowDownPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerArrowDownPainter oldDelegate) =>
      oldDelegate.color != color;
}
