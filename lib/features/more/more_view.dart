import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../data/safety_contacts.dart';
import '../../models/transit_region.dart';
import '../../shared/region_selector.dart';
import '../../state/app_state.dart';
import '../../theme/hsl_colors.dart';

enum _MoreSection {
  emergency,
  alerts,
  settings,
  help,
}

class MoreView extends StatefulWidget {
  const MoreView({super.key});

  @override
  State<MoreView> createState() => _MoreViewState();
}

class _MoreViewState extends State<MoreView> {
  _MoreSection? _openSection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertsController>().refresh();
    });
  }

  void _toggleSection(_MoreSection section) {
    setState(() {
      if (_openSection == section) {
        _openSection = null;
      } else {
        _openSection = section;
      }
    });
  }

  Future<void> _makeCall(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _buildSectionHeader({
    required _MoreSection section,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? badgeText,
    Widget? trailingAction,
  }) {
    final isOpen = _openSection == section;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isOpen ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isOpen ? HslColors.primaryBlue : theme.dividerColor.withValues(alpha: 0.4),
          width: isOpen ? 1.8 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _toggleSection(section),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isOpen ? HslColors.primaryBlue : null,
                  ),
                ),
              ),
              if (badgeText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (trailingAction != null) ...[
                trailingAction,
                const SizedBox(width: 4),
              ],
              Icon(
                isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: isOpen ? HslColors.primaryBlue : theme.hintColor,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertsController>();
    final settings = context.watch<SettingsController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('tab_more')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Section: Safety & Emergency Contacts (112, HSL security)
          _buildSectionHeader(
            section: _MoreSection.emergency,
            icon: Icons.health_and_safety_rounded,
            iconColor: HslColors.safetyRed,
            title: AppStrings.get('emergency_contacts'),
            badgeText: '${safetyContacts.length}',
          ),
          if (_openSection == _MoreSection.emergency)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Column(
                children: [
                  for (final contact in safetyContacts)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: contact.isEmergency ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: contact.isEmergency
                            ? const BorderSide(color: HslColors.safetyRed, width: 1.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: contact.type.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(contact.type.icon, color: contact.type.color, size: 20),
                        ),
                        title: Text(contact.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          '${contact.subtitle} • ${contact.phoneNumber}\n${contact.description}',
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.phone_in_talk_rounded, color: HslColors.primaryBlue),
                          onPressed: () => _makeCall(contact.phoneNumber),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // 2. Section: Disruptions & Alerts
          _buildSectionHeader(
            section: _MoreSection.alerts,
            icon: Icons.warning_amber_rounded,
            iconColor: HslColors.warningAmber,
            title: AppStrings.get('disruptions_alerts'),
            badgeText: '${alerts.alerts.length}',
            trailingAction: alerts.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Päivitä',
                    onPressed: alerts.refresh,
                  ),
          ),
          if (_openSection == _MoreSection.alerts)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Column(
                children: [
                  if (alerts.alerts.isEmpty && !alerts.loading)
                    const Card(
                      margin: EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, color: HslColors.successGreen, size: 20),
                            SizedBox(width: 10),
                            Expanded(child: Text('Ei aktiivisia liikennehäiriöitä.')),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final alert in alerts.alerts.take(5))
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                alert.isSevere ? Icons.error_rounded : Icons.warning_rounded,
                                color: alert.isSevere ? HslColors.safetyRed : HslColors.warningAmber,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alert.header,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    if (alert.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        alert.description,
                                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // 3. Section: Map & App Settings
          _buildSectionHeader(
            section: _MoreSection.settings,
            icon: Icons.settings_rounded,
            iconColor: HslColors.primaryBlue,
            title: AppStrings.get('settings'),
          ),
          if (_openSection == _MoreSection.settings)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    // Transit Region & Routing Server
                    ListTile(
                      leading: const Icon(Icons.location_city_rounded, color: HslColors.primaryBlue),
                      title: const Text('Liikennealue & Paikkakunta'),
                      subtitle: Text(
                        settings.region == TransitRegion.auto
                            ? '${settings.region.name} • ${settings.region.effectiveDisplayName(settings.s.location.position)}'
                            : '${settings.region.name}\n${settings.region.description}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showTransitRegionSheet(context),
                    ),

                    const Divider(height: 1),

                    // Map Tile Source
                    ListTile(
                      leading: const Icon(Icons.layers_rounded, color: HslColors.primaryBlue),
                      title: Text(AppStrings.get('map_tile_source')),
                      subtitle: Text(settings.tile.label),
                      trailing: DropdownButton<TileSource>(
                        value: settings.tile,
                        underline: const SizedBox(),
                        items: TileSource.values
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) settings.setTile(v);
                        },
                      ),
                    ),

                    const Divider(height: 1),

                    // Nearby stops search radius
                    ListTile(
                      leading: const Icon(Icons.radar_rounded, color: HslColors.primaryBlue),
                      title: Text(AppStrings.get('search_radius')),
                      subtitle: Text(
                        settings.nearbyRadius >= 1000
                            ? '${(settings.nearbyRadius / 1000).toStringAsFixed(settings.nearbyRadius % 1000 == 0 ? 0 : 1)} km'
                            : '${settings.nearbyRadius} m',
                      ),
                      trailing: DropdownButton<int>(
                        value: [500, 800, 1000, 1500, 2000, 2500, 3000].contains(settings.nearbyRadius)
                            ? settings.nearbyRadius
                            : 1500,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 500, child: Text('500 m')),
                          DropdownMenuItem(value: 800, child: Text('800 m')),
                          DropdownMenuItem(value: 1000, child: Text('1,0 km')),
                          DropdownMenuItem(value: 1500, child: Text('1,5 km')),
                          DropdownMenuItem(value: 2000, child: Text('2,0 km')),
                          DropdownMenuItem(value: 2500, child: Text('2,5 km')),
                          DropdownMenuItem(value: 3000, child: Text('3,0 km')),
                        ],
                        onChanged: (v) {
                          if (v != null) settings.setNearbyRadius(v);
                        },
                      ),
                    ),

                    const Divider(height: 1),

                    // Language
                    ListTile(
                      leading: const Icon(Icons.language_rounded, color: HslColors.primaryBlue),
                      title: const Text('Kieli / Språk / Language'),
                      subtitle: Text(
                        AppStrings.currentLang == AppLang.fi
                            ? 'Suomi'
                            : (AppStrings.currentLang == AppLang.sv ? 'Svenska' : 'English'),
                      ),
                      trailing: DropdownButton<AppLang>(
                        value: AppStrings.currentLang,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: AppLang.fi, child: Text('Suomi')),
                          DropdownMenuItem(value: AppLang.sv, child: Text('Svenska')),
                          DropdownMenuItem(value: AppLang.en, child: Text('English')),
                        ],
                        onChanged: (lang) {
                          if (lang != null) {
                            setState(() => AppStrings.currentLang = lang);
                          }
                        },
                      ),
                    ),

                    const Divider(height: 1),

                    // Theme mode
                    ListTile(
                      leading: const Icon(Icons.palette_rounded, color: HslColors.primaryBlue),
                      title: const Text('Teema'),
                      subtitle: Text(
                        settings.themeMode == ThemeMode.dark
                            ? 'Tumma'
                            : (settings.themeMode == ThemeMode.light ? 'Vaalea' : 'Järjestelmä'),
                      ),
                      trailing: DropdownButton<ThemeMode>(
                        value: settings.themeMode,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: ThemeMode.dark, child: Text('Tumma')),
                          DropdownMenuItem(value: ThemeMode.light, child: Text('Vaalea')),
                          DropdownMenuItem(value: ThemeMode.system, child: Text('Järjestelmä')),
                        ],
                        onChanged: (m) {
                          if (m != null) settings.setTheme(m);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 4),

          // 4. Section: Ohje & Paikkakunnat (Help & Regions)
          _buildSectionHeader(
            section: _MoreSection.help,
            icon: Icons.help_outline_rounded,
            iconColor: HslColors.primaryBlue,
            title: AppStrings.get('help_and_info'),
            badgeText: 'Waltti & Suomi',
          ),
          if (_openSection == _MoreSection.help)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Waltti-kaupungit
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: HslColors.primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.location_city_rounded, color: HslColors.primaryBlue, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.get('waltti_cities_title'),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppStrings.get('waltti_cities_desc'),
                                  style: TextStyle(fontSize: 13, color: theme.hintColor, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? theme.colorScheme.surfaceContainerHigh
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          AppStrings.get('waltti_cities_list'),
                          style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Muut alueet
                      _buildHelpRegionItem(
                        icon: Icons.tram_rounded,
                        title: 'HSL',
                        desc: AppStrings.get('region_guide_hsl'),
                      ),
                      const SizedBox(height: 10),
                      _buildHelpRegionItem(
                        icon: Icons.train_rounded,
                        title: 'VR & Kaukoliikenne',
                        desc: AppStrings.get('region_guide_finland'),
                      ),
                      const SizedBox(height: 10),
                      _buildHelpRegionItem(
                        icon: Icons.my_location_rounded,
                        title: 'Automaattinen GPS',
                        desc: AppStrings.get('region_guide_auto'),
                      ),
                      const SizedBox(height: 10),
                      _buildHelpRegionItem(
                        icon: Icons.alt_route_rounded,
                        title: 'Reittiopas & Kaukoliikenne',
                        desc: AppStrings.get('region_guide_intercity'),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(AppStrings.get('transit_region_title')),
                          onPressed: () => showTransitRegionSheet(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildHelpRegionItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: HslColors.primaryBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(fontSize: 12, color: theme.hintColor, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}
