import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/transit_mode.dart';
import '../../models/trip_alarm.dart';
import '../../shared/mode_style.dart';
import '../../shared/widgets.dart';
import '../../state/alarm_controller.dart';
import '../../state/app_state.dart';
import '../../theme/hsl_colors.dart';
import 'alarm_management_dialog.dart';

String _formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Dialogi uuden huomiohälytyksen asettamiseen ja ennakkoajan valintaan (2 - 30 min, oletus 7 min).
class SetTripAlarmDialog extends StatefulWidget {
  final String title;
  final String? line;
  final TransitMode mode;
  final String destination;
  final String? stopName;
  final DateTime departureTime;
  final DateTime walkStartTime;
  final String source; // 'planner' tai 'nearby'

  const SetTripAlarmDialog({
    super.key,
    required this.title,
    this.line,
    required this.mode,
    required this.destination,
    this.stopName,
    required this.departureTime,
    required this.walkStartTime,
    required this.source,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    String? line,
    required TransitMode mode,
    required String destination,
    String? stopName,
    required DateTime departureTime,
    required DateTime walkStartTime,
    required String source,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => SetTripAlarmDialog(
        title: title,
        line: line,
        mode: mode,
        destination: destination,
        stopName: stopName,
        departureTime: departureTime,
        walkStartTime: walkStartTime,
        source: source,
      ),
    );
  }

  @override
  State<SetTripAlarmDialog> createState() => _SetTripAlarmDialogState();
}

class _SetTripAlarmDialogState extends State<SetTripAlarmDialog> {
  late int _leadMinutes;
  bool _saveAsDefault = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _leadMinutes = settings.alarmLeadMinutes.clamp(2, 30);
  }

  DateTime get _calculatedAlarmTime =>
      widget.walkStartTime.subtract(Duration(minutes: _leadMinutes));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.read<SettingsController>();
    final alarmCtrl = context.read<AlarmController>();
    final isDark = theme.brightness == Brightness.dark;

    final alarmTimeStr = _formatHm(_calculatedAlarmTime);
    final walkTimeStr = _formatHm(widget.walkStartTime);
    final depTimeStr = _formatHm(widget.departureTime);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: HslColors.primaryBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.alarm_add_rounded,
                      color: HslColors.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aseta huomiohälytys',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.destination.isNotEmpty
                              ? (widget.line != null && widget.line!.isNotEmpty
                                  ? '${widget.line} ${widget.destination}'
                                  : widget.destination)
                              : widget.title,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.hintColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Sulje',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Compact Details & Alarm Card
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (widget.line != null && widget.line!.isNotEmpty)
                          LineBadge(mode: widget.mode, line: widget.line!, small: true)
                        else
                          Icon(widget.mode.icon, color: widget.mode.color, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.stopName != null && widget.stopName!.isNotEmpty
                                ? widget.stopName!
                                : widget.destination,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Kävely: $walkTimeStr', style: const TextStyle(fontSize: 12)),
                        const Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.grey),
                        Text(
                          'Lähtö: $depTimeStr',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: HslColors.primaryBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: isDark ? 0.2 : 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_on_rounded, color: Colors.amber, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Hälytys klo $alarmTimeStr ($_leadMinutes min ennen kävelyä)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.amber,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Slider and Steppers
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Vähennä 1 min',
                    onPressed: _leadMinutes > 2
                        ? () {
                            HapticFeedback.selectionClick();
                            setState(() => _leadMinutes--);
                          }
                        : null,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: HslColors.primaryBlue,
                        thumbColor: HslColors.primaryBlue,
                        overlayColor: HslColors.primaryBlue.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: _leadMinutes.toDouble(),
                        min: 2,
                        max: 30,
                        divisions: 28,
                        label: '$_leadMinutes min',
                        onChanged: (val) {
                          final newVal = val.round().clamp(2, 30);
                          if (newVal != _leadMinutes) {
                            HapticFeedback.selectionClick();
                            setState(() => _leadMinutes = newVal);
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Lisää 1 min',
                    onPressed: _leadMinutes < 30
                        ? () {
                            HapticFeedback.selectionClick();
                            setState(() => _leadMinutes++);
                          }
                        : null,
                  ),
                ],
              ),

              // Quick preset chips (min 2, default 7, max 30)
              Wrap(
                spacing: 5,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [2, 5, 7, 10, 15, 30].map((mins) {
                  final isSelected = _leadMinutes == mins;
                  final isDefault = mins == 7;
                  return ChoiceChip(
                    label: Text(
                      isDefault ? '$mins min (oletus)' : '$mins min',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: HslColors.primaryBlue,
                    onSelected: (selected) {
                      if (selected) {
                        HapticFeedback.selectionClick();
                        setState(() => _leadMinutes = mins);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),

              // Optional: Save as default
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _saveAsDefault,
                activeColor: HslColors.primaryBlue,
                title: const Text(
                  'Tallenna tämä aika oletukseksi',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: (val) {
                  setState(() => _saveAsDefault = val ?? false);
                },
              ),
              const SizedBox(height: 8),

              // Dialog Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Peruuta', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      key: const ValueKey('set_trip_alarm_confirm_button'),
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: Text(
                        'Aseta hälytys ($alarmTimeStr)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HslColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
                        if (_saveAsDefault) {
                          settings.setAlarmLeadMinutes(_leadMinutes);
                        }

                        final alarm = TripAlarm(
                          id: '${widget.source}_${DateTime.now().millisecondsSinceEpoch}_${widget.line ?? ""}_${widget.departureTime.millisecondsSinceEpoch}',
                          title: widget.title,
                          line: widget.line,
                          mode: widget.mode,
                          destination: widget.destination,
                          stopName: widget.stopName,
                          departureTime: widget.departureTime,
                          walkStartTime: widget.walkStartTime,
                          alarmTime: _calculatedAlarmTime,
                          source: widget.source,
                          leadMinutes: _leadMinutes,
                        );

                        final totalActive = await alarmCtrl.addAlarm(alarm);
                        if (!context.mounted) return;

                        Navigator.of(context).pop(true);

                        final routeDesc = widget.line != null && widget.line!.isNotEmpty
                            ? '${widget.line} (${widget.destination})'
                            : widget.destination;

                        final String message;
                        if (totalActive > 1) {
                          message =
                              'Hälytys asetettu klo $alarmTimeStr ($routeDesc, $_leadMinutes min ennen kävelyä).\nHuomio: Sinulla on nyt $totalActive aktiivista hälytystä!';
                        } else {
                          message =
                              'Hälytys asetettu klo $alarmTimeStr ($routeDesc, $_leadMinutes min ennen kävelyä).';
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: HslColors.primaryBlue,
                            duration: const Duration(seconds: 4),
                            action: SnackBarAction(
                              label: 'Hälytykset',
                              textColor: Colors.white,
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => const AlarmManagementDialog(),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
