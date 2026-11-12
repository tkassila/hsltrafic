import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets.dart';
import '../../state/alarm_controller.dart';
import '../../theme/hsl_colors.dart';

String _formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Näytetään ruudun päällä kun huomiohälytys laukeaa ja soi pitkään.
class RingingAlarmOverlay extends StatefulWidget {
  const RingingAlarmOverlay({super.key});

  @override
  State<RingingAlarmOverlay> createState() => _RingingAlarmOverlayState();
}

class _RingingAlarmOverlayState extends State<RingingAlarmOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarmCtrl = context.watch<AlarmController>();
    final alarm = alarmCtrl.ringingAlarm;
    if (alarm == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.redAccent, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing alarm icon
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.15).animate(
                      CurvedAnimation(
                        parent: _pulseController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.alarm_on_rounded,
                        color: Colors.redAccent,
                        size: 52,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header title
                  const Text(
                    'HUOMIOHÄLYTYS!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.redAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kävelyn alkuun ${alarm.leadMinutes} minuuttia!',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 2 min countdown timer badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: Colors.redAccent),
                            const SizedBox(width: 6),
                            Text(
                              'Soi vielä: ${alarmCtrl.ringingRemainingSeconds ~/ 60}:${(alarmCtrl.ringingRemainingSeconds % 60).toString().padLeft(2, '0')} (max 2 min)',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 180,
                            height: 4,
                            child: LinearProgressIndicator(
                              value: (alarmCtrl.ringingRemainingSeconds / 120).clamp(0.0, 1.0),
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Route info container
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (alarm.line != null && alarm.line!.isNotEmpty)
                              LineBadge(
                                mode: alarm.mode,
                                line: alarm.line!,
                                small: false,
                              )
                            else
                              const Icon(
                                Icons.directions_walk_rounded,
                                size: 28,
                                color: HslColors.walkGray,
                              ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                alarm.destination.isNotEmpty
                                    ? alarm.destination
                                    : alarm.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (alarm.stopName != null && alarm.stopName!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            alarm.stopName!,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.hintColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Kävely alkaa',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.hintColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatHm(alarm.walkStartTime),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text(
                                  'Lähtöaika',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.hintColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatHm(alarm.departureTime),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: HslColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Large dismiss button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.alarm_off_rounded, size: 22),
                      label: const Text(
                        'Kuittaa hälytys',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () {
                        alarmCtrl.dismissRinging();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
