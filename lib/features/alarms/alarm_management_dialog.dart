import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets.dart';
import '../../state/alarm_controller.dart';
import '../../theme/hsl_colors.dart';

String _formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Hälytysten hallintaikkuna, josta käyttäjä näkee asetetut hälytykset ja voi poistaa niitä.
class AlarmManagementDialog extends StatelessWidget {
  const AlarmManagementDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alarmCtrl = context.watch<AlarmController>();
    final alarms = alarmCtrl.alarms;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: HslColors.primaryBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.alarm_rounded,
                      color: HslColors.primaryBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Matkahälytykset',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Hälytys soi 7 min ennen kävelyn alkua',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Sulje',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Alarms list or empty state
              Expanded(
                child: alarms.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 54,
                                color: theme.hintColor.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Ei aktiivisia hälytyksiä',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Aseta hälytys painamalla pitkään reitin aloituskuvaketta Reittioppaassa tai vuorolistan linjalaatikkoa Lähipysäkeissä.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: alarms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final alarm = alarms[index];
                          final isTriggered = alarm.isTriggered;

                          return Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isTriggered
                                    ? Colors.grey.withValues(alpha: 0.3)
                                    : HslColors.primaryBlue.withValues(alpha: 0.4),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Badge
                                if (alarm.line != null && alarm.line!.isNotEmpty)
                                  LineBadge(
                                    mode: alarm.mode,
                                    line: alarm.line!,
                                    small: true,
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: HslColors.walkGray.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.directions_walk_rounded,
                                      size: 18,
                                      color: HslColors.walkGray,
                                    ),
                                  ),
                                const SizedBox(width: 10),

                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        alarm.destination.isNotEmpty
                                            ? '${alarm.line != null ? "${alarm.line} " : ""}${alarm.destination}'
                                            : alarm.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (alarm.stopName != null &&
                                          alarm.stopName!.isNotEmpty)
                                        Text(
                                          alarm.stopName!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.hintColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.alarm_rounded,
                                            size: 13,
                                            color: isTriggered
                                                ? theme.hintColor
                                                : HslColors.warningAmber,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Hälytys ${_formatHm(alarm.alarmTime)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isTriggered
                                                  ? theme.hintColor
                                                  : HslColors.warningAmber,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '• Lähtö ${_formatHm(alarm.departureTime)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: theme.hintColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Status & Delete
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  tooltip: 'Poista hälytys',
                                  onPressed: () {
                                    alarmCtrl.removeAlarm(alarm.id);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              const Divider(height: 20),

              // Bottom actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (alarms.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('Poista kaikki'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: () {
                        alarmCtrl.clearAllAlarms();
                      },
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HslColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Valmis'),
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
