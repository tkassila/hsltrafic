import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/place_stop.dart';
import '../models/transit_region.dart';
import '../state/app_state.dart';
import '../theme/hsl_colors.dart';

/// Koko ruudun osoite-/paikkahaku. Palauttaa valitun [GeoPlace]n.
///
/// [allowCurrent]: näytä "Oma sijainti" -vaihtoehto.
/// [isRailOnly]: priorisoi rautatieasemat ja kaupungit VR- ja junamatkoja varten.
Future<GeoPlace?> pickPlace(
  BuildContext context, {
  String title = 'Hae osoite',
  bool allowCurrent = true,
  bool isRailOnly = false,
}) {
  return Navigator.of(context).push<GeoPlace>(
    MaterialPageRoute(
      builder: (_) => _PlaceSearchPage(
        title: title,
        allowCurrent: allowCurrent,
        isRailOnly: isRailOnly,
      ),
    ),
  );
}

class _PlaceSearchPage extends StatefulWidget {
  final String title;
  final bool allowCurrent;
  final bool isRailOnly;

  const _PlaceSearchPage({
    required this.title,
    required this.allowCurrent,
    this.isRailOnly = false,
  });

  @override
  State<_PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<_PlaceSearchPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<GeoPlace> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_seq;
    setState(() => _loading = true);
    try {
      final loc = context.read<LocationController>();
      final settings = context.read<SettingsController>();
      final effectiveFocus = (settings.region != TransitRegion.auto && settings.region != TransitRegion.finland && settings.region.center != null)
          ? settings.region.center
          : (loc.position ?? settings.region.center);
      final r = await context.read<Services>().api.autocomplete(
            text,
            focus: effectiveFocus,
            isRailOnly: widget.isRailOnly,
          );
      if (!mounted || id != _seq) return;
      setState(() {
        _results = r;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _seq) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final favs = context.watch<FavoritesController>();
    final showSuggestions = _ctrl.text.trim().length < 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldTextColor = isDark ? Colors.white : HslColors.onSurfaceLight;
    final fieldHintColor = isDark ? Colors.white70 : const Color(0xFF423627);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: (t) {
            setState(() {});
            _onChanged(t);
          },
          style: TextStyle(color: fieldTextColor, fontSize: 17, fontWeight: FontWeight.w600),
          cursorColor: isDark ? Colors.white : HslColors.primaryBlue,
          decoration: InputDecoration(
            hintText: widget.title,
            hintStyle: TextStyle(color: fieldHintColor, fontWeight: FontWeight.w500),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
                setState(() {});
              },
            ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      body: ListView(
        children: [
          if (widget.allowCurrent && showSuggestions)
            ListTile(
              leading: const Icon(Icons.my_location, color: Color(0xFF1E88E5)),
              title: const Text('Oma sijainti'),
              onTap: () async {
                final loc = context.read<LocationController>();
                final nav = Navigator.of(context);
                if (loc.position == null) await loc.locate();
                nav.pop(GeoPlace(
                    label: 'Oma sijainti', position: loc.positionOrDefault, isCurrentLocation: true));
              },
            ),
          if (showSuggestions)
            for (final p in favs.places)
              ListTile(
                leading: const Icon(Icons.star_rounded, color: Colors.amber),
                title: Text(p.label),
                subtitle: p.secondary == null ? null : Text(p.secondary!),
                onTap: () => Navigator.pop(context, p),
              ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          for (final p in _results)
            ListTile(
              leading: _placeIcon(p),
              title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: p.secondary == null ? null : Text(p.secondary!),
              onTap: () => Navigator.pop(context, p),
            ),
          if (!showSuggestions && !_loading && _results.isEmpty && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Ei tuloksia'))),
        ],
      ),
    );
  }

  Widget _placeIcon(GeoPlace p) {
    if (p.isCurrentLocation) {
      return const Icon(Icons.my_location, color: Color(0xFF1E88E5));
    }
    final layer = p.layer?.toLowerCase();
    if (layer == 'locality' || layer == 'localadmin') {
      return const Icon(Icons.location_city_rounded, color: Color(0xFF1565C0));
    }
    if (layer == 'station') {
      final fullText = '${p.label} ${p.secondary ?? ''}'.toLowerCase();
      if (fullText.contains('linja-auto') || fullText.contains('bussi')) {
        return const Icon(Icons.directions_bus_rounded, color: Color(0xFFE65100));
      }
      if (fullText.contains('metro') || fullText.contains('(m)')) {
        return const Icon(Icons.subway_rounded, color: Color(0xFFFF5722));
      }
      return const Icon(Icons.train_rounded, color: Color(0xFF2E7D32));
    }
    if (layer == 'neighbourhood' || layer == 'borough' || layer == 'macrohood') {
      return const Icon(Icons.holiday_village_rounded, color: Color(0xFF7B1FA2));
    }
    if (p.stopGtfsId != null || layer == 'stop') {
      return const Icon(Icons.directions_bus_rounded, color: Color(0xFF007AC9));
    }
    return const Icon(Icons.place_outlined, color: Colors.grey);
  }
}
