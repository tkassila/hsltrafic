import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/digitransit_client.dart';
import '../models/place_stop.dart';
import '../models/vehicle.dart';
import '../theme/hsl_colors.dart';
import 'widgets.dart';

/// Avaa vuorolistan vuoron kuormitustietonäkymän (HSL:n käytäntö).
///
/// Hakee reaaliaikaisesti tuoreimman kuormitustiedon Digitransitista (GraphQL trip occupancy)
/// ja tarkistaa myös mahdolliset live-ajoneuvon tiedot HFP-telemetriasta.
Future<void> showDepartureOccupancySheet(
  BuildContext context, {
  required Departure departure,
  Stop? stop,
  DigitransitClient? client,
  List<Vehicle>? liveVehicles,
  VoidCallback? onSetAlarm,
}) async {
  HapticFeedback.mediumImpact();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DepartureOccupancySheet(
      departure: departure,
      stop: stop,
      client: client,
      liveVehicles: liveVehicles,
      onSetAlarm: onSetAlarm,
    ),
  );
}

class _DepartureOccupancySheet extends StatefulWidget {
  final Departure departure;
  final Stop? stop;
  final DigitransitClient? client;
  final List<Vehicle>? liveVehicles;
  final VoidCallback? onSetAlarm;

  const _DepartureOccupancySheet({
    required this.departure,
    this.stop,
    this.client,
    this.liveVehicles,
    this.onSetAlarm,
  });

  @override
  State<_DepartureOccupancySheet> createState() => _DepartureOccupancySheetState();
}

class _DepartureOccupancySheetState extends State<_DepartureOccupancySheet> {
  late Departure _currentDep;
  bool _isLoading = false;
  Vehicle? _matchingVehicle;

  @override
  void initState() {
    super.initState();
    _currentDep = widget.departure;
    _findMatchingVehicle();
    _refreshOccupancyIfNeeded();
  }

  void _findMatchingVehicle() {
    if (widget.liveVehicles == null || widget.liveVehicles!.isEmpty) return;
    final lineClean = _currentDep.line.trim().toLowerCase();
    for (final v in widget.liveVehicles!) {
      if (_currentDep.tripGtfsId != null && v.tripGtfsId == _currentDep.tripGtfsId) {
        _matchingVehicle = v;
        break;
      }
      if (v.line.trim().toLowerCase() == lineClean) {
        _matchingVehicle ??= v;
      }
    }
  }

  Future<void> _refreshOccupancyIfNeeded() async {
    final tripId = _currentDep.tripGtfsId;
    if (widget.client == null || tripId == null || tripId.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final status = await widget.client!.tripOccupancy(tripId);
      if (mounted && status != null) {
        setState(() {
          _currentDep = _currentDep.copyWith(occupancyStatus: status);
        });
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dep = _currentDep;
    final minutes = dep.minutesUntil();
    final timeStr = '${dep.realtime.hour.toString().padLeft(2, '0')}:${dep.realtime.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Ylärivi: linjatunnus, määränpää, lähtöaika ja sulkeminen
          Row(
            children: [
              LineBadge(mode: dep.mode, line: dep.line),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dep.headsign.isNotEmpty ? dep.headsign : 'Linja ${dep.line}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.stop != null)
                      Text(
                        '${widget.stop!.name}${widget.stop!.code != null ? " (${widget.stop!.code})" : ""}',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$minutes min',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: dep.isRealtime ? HslColors.successGreen : null,
                    ),
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Kuormitustiedon pääosio
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, size: 20, color: HslColors.primaryBlue),
              const SizedBox(width: 8),
              const Text(
                'Vuoron kuormitustieto (täyttöaste)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (_isLoading) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: HslColors.primaryBlue),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Kuormituskortti
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dep.hasOccupancy
                    ? dep.occupancyColor.withValues(alpha: 0.5)
                    : theme.dividerColor.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: dep.occupancyColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        dep.occupancyIcon,
                        color: dep.occupancyColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dep.occupancyDescription,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: dep.hasOccupancy ? dep.occupancyColor : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _statusSubtext(dep.occupancyStatus),
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 4-portainen kuormitusmittari
                _buildOccupancyBar(context, dep.occupancyStatus, dep.occupancyPercentage),

                // HFP MQTT live vehicle lisätieto (jos saatavilla)
                if (_matchingVehicle != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.sensors, size: 14, color: HslColors.successGreen),
                      const SizedBox(width: 6),
                      Text(
                        'Reaaliaikainen ajoneuvo: ${_matchingVehicle!.id}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (_matchingVehicle!.occupancy != null)
                        Text(
                          'Kuormitus ${_matchingVehicle!.occupancy} %',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _matchingVehicle!.occupancy! > 75
                                ? HslColors.safetyRed
                                : HslColors.successGreen,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // HSL käytännön ohjeteksti
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'HSL kerää kuormitustietoa automaattisilla matkustajalaskureilla (APC) varustetusta kalustosta. Mikäli ajoneuvoyksikössä ei ole laskureita, kuormitustietoa ei ole saatavilla.',
                    style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.3),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Painikkeet: Aseta lähtöhälytys ja Sulje
          Row(
            children: [
              if (widget.onSetAlarm != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HslColors.primaryBlue,
                      side: const BorderSide(color: HslColors.primaryBlue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.alarm_add_rounded, size: 18),
                    label: const Text('Aseta lähtöhälytys', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onSetAlarm!();
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: HslColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Sulje', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOccupancyBar(BuildContext context, String? status, int? pct) {
    int level = 0; // 0 = ei dataa, 1 = vihreä, 2 = keltainen, 3 = oranssi, 4 = punainen
    if (status != null) {
      switch (status.toUpperCase()) {
        case 'EMPTY':
        case 'MANY_SEATS_AVAILABLE':
          level = 1;
          break;
        case 'FEW_SEATS_AVAILABLE':
          level = 2;
          break;
        case 'STANDING_ROOM_ONLY':
          level = 3;
          break;
        case 'CRUSHED_STANDING_ROOM_ONLY':
        case 'FULL':
        case 'NOT_ACCEPTING_PASSENGERS':
          level = 4;
          break;
      }
    } else if (pct != null) {
      if (pct < 33) {
        level = 1;
      } else if (pct < 67) {
        level = 2;
      } else if (pct < 90) {
        level = 3;
      } else {
        level = 4;
      }
    }

    final barColors = [
      const Color(0xFF2E7D32), // Paljon istumapaikkoja
      const Color(0xFFF57C00), // Vähän istumapaikkoja
      const Color(0xFFE65100), // Vain seisomapaikkoja
      const Color(0xFFD32F2F), // Täynnä
    ];

    return Row(
      children: [
        for (int i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 8,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: level > 0 && i < level
                    ? barColors[level - 1]
                    : Colors.grey.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _statusSubtext(String? status) {
    if (status == null) return 'Kuormitustietoa ei ole toistaiseksi saatu tälle vuorolle.';
    switch (status.toUpperCase()) {
      case 'MANY_SEATS_AVAILABLE':
      case 'EMPTY':
        return 'Kulkuneuvossa on runsaasti tilaa ja vapaita istumapaikkoja.';
      case 'FEW_SEATS_AVAILABLE':
        return 'Kulkuneuvossa on vielä joitain istumapaikkoja vapaana.';
      case 'STANDING_ROOM_ONLY':
        return 'Istumapaikat ovat varattuja, mutta seisomatilaa on.';
      case 'CRUSHED_STANDING_ROOM_ONLY':
      case 'FULL':
        return 'Kulkuneuvo on erittäin täynnä. Seuraava vuoro saattaa olla väljempi.';
      case 'NOT_ACCEPTING_PASSENGERS':
        return 'Kulkuneuvo ei ota matkustajia.';
      default:
        return 'Reaaliaikainen kuormitusarvio.';
    }
  }
}
