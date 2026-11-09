import 'package:flutter/material.dart';

import '../models/transit_mode.dart';
import 'mode_style.dart';

/// Linjatunnus värillisessä kapselissa (kuten HSL:n sovelluksessa).
class LineBadge extends StatelessWidget {
  final TransitMode mode;
  final String line;
  final bool small;
  const LineBadge({super.key, required this.mode, required this.line, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = lineColor(mode, line);
    return Container(
      constraints: BoxConstraints(minWidth: small ? 32 : 40),
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mode.icon, size: small ? 12 : 15, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            line,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: small ? 12 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String durationText(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

String distanceText(num meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '${meters.round()} m';
