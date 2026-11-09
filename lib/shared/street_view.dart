import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

/// Avaa Google Street View -panoraamanäytön annetusta GPS-koordinaattipisteestä.
Future<void> openGoogleStreetView(
  BuildContext context, {
  required LatLng position,
  String? stopName,
}) async {
  HapticFeedback.mediumImpact();
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  final displayName = stopName != null && stopName.isNotEmpty ? ' ($stopName)' : '';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.streetview_rounded, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Avataan Google Street View$displayName...',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );

  final url =
      'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${position.latitude},${position.longitude}';
  final uri = Uri.parse(url);
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  } catch (_) {
    try {
      await launchUrl(uri);
    } catch (_) {}
  }
}

