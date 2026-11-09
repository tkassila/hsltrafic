import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';

const String kUserAgentPackage = 'com.metait.hsltrafic';

/// Avoimeen karttadataan (OpenStreetMap / HSL:n Digitransit-tiilet) perustuva taustakartta.
TileLayer buildTileLayer(TileSource src, {bool dark = false}) {
  switch (src) {
    case TileSource.digitransit:
      return TileLayer(
        urlTemplate:
            'https://cdn.digitransit.fi/map/v3/hsl-map/{z}/{x}/{y}.png?digitransit-subscription-key=${AppConfig.digitransitApiKey}',
        userAgentPackageName: kUserAgentPackage,
        maxNativeZoom: 18,
        maxZoom: 20,
      );
    case TileSource.carto:
      return TileLayer(
        urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: kUserAgentPackage,
        retinaMode: true,
        maxNativeZoom: 19,
        maxZoom: 20,
      );
    case TileSource.osm:
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: kUserAgentPackage,
        maxNativeZoom: 19,
        maxZoom: 20,
      );
  }
}

/// Pakollinen OSM/HSL-attribuutio.
Widget buildAttribution(TileSource src) => RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      attributions: [
        const TextSourceAttribution('© OpenStreetMap-tekijät'),
        if (src == TileSource.digitransit) const TextSourceAttribution('Digitransit / HSL'),
        if (src == TileSource.carto) const TextSourceAttribution('© CARTO'),
      ],
    );

/// Sininen piste oman sijainnin kohdalla.
Marker userMarker(LatLng p) => Marker(
      point: p,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E88E5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
      ),
    );
