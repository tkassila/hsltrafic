import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/localization.dart';
import 'data/digitransit_client.dart';
import 'data/favorites_repository.dart';
import 'data/hfp_service.dart';
import 'data/location_service.dart';
import 'data/notification_service.dart';
import 'features/alarms/ringing_alarm_overlay.dart';
import 'features/lines/lines_view.dart';
import 'features/live_map/live_map_view.dart';
import 'features/more/more_view.dart';
import 'features/nearby/nearby_stops_view.dart';
import 'features/planner/planner_view.dart';
import 'state/alarm_controller.dart';
import 'state/app_state.dart';
import 'state/lines_controller.dart';
import 'state/live_map_controller.dart';
import 'state/nearby_controller.dart';
import 'state/planner_controller.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  final prefs = await SharedPreferences.getInstance();

  final services = Services(
    api: DigitransitClient(),
    hfp: HfpService(),
    location: LocationService(),
    repo: FavoritesRepository(prefs),
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<Services>.value(value: services),
        ChangeNotifierProvider(create: (_) => SettingsController(services)),
        ChangeNotifierProvider(create: (_) => LocationController(services)..locate()),
        ChangeNotifierProvider(create: (_) => FavoritesController(services)),
        ChangeNotifierProvider(create: (_) => AlertsController(services)),
        ChangeNotifierProxyProvider<LocationController, PlannerController>(
          create: (ctx) => PlannerController(services, ctx.read<LocationController>()),
          update: (_, loc, prev) => prev ?? PlannerController(services, loc),
        ),
        ChangeNotifierProxyProvider2<LocationController, SettingsController, NearbyController>(
          create: (ctx) => NearbyController(
            services,
            ctx.read<LocationController>(),
            ctx.read<SettingsController>(),
          ),
          update: (_, loc, settings, prev) =>
              prev ?? NearbyController(services, loc, settings),
        ),
        ChangeNotifierProxyProvider<LocationController, LinesController>(
          create: (ctx) => LinesController(services, ctx.read<LocationController>()),
          update: (_, loc, prev) => prev ?? LinesController(services, loc),
        ),
        ChangeNotifierProvider(create: (_) => LiveMapController(services)),
        ChangeNotifierProvider(create: (_) => AlarmController(services)),
      ],
      child: const HslTrafficApp(),
    ),
  );
}

class HslTrafficApp extends StatelessWidget {
  const HslTrafficApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      title: 'HSL Liikenne & Reittiopas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _views = const [
    PlannerView(),
    LiveMapView(),
    LinesView(),
    NearbyStopsView(),
    MoreView(),
  ];

  void _selectTab(int idx) {
    if (_currentIndex == idx) return;
    setState(() => _currentIndex = idx);
    final live = context.read<LiveMapController>();
    if (idx == 1) {
      final nearby = context.read<NearbyController>();
      final loc = context.read<LocationController>();
      if (loc.position == null) {
        loc.locate();
      }
      live.center = loc.position ?? nearby.origin?.position ?? loc.positionOrDefault;
    }
    live.setActive(idx == 1);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 720;

    // Tablet layout: NavigationRail on the side
    final Widget content;
    if (isTablet) {
      content = Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: _selectTab,
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.alt_route_outlined),
                  selectedIcon: const Icon(Icons.alt_route_rounded),
                  label: Text(AppStrings.get('tab_planner')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.explore_outlined),
                  selectedIcon: const Icon(Icons.explore_rounded),
                  label: Text(AppStrings.get('tab_live')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.timeline_outlined),
                  selectedIcon: const Icon(Icons.timeline_rounded),
                  label: Text(AppStrings.get('tab_lines')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.bus_alert_outlined),
                  selectedIcon: const Icon(Icons.bus_alert_rounded),
                  label: Text(AppStrings.get('tab_nearby')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.more_horiz_rounded),
                  selectedIcon: const Icon(Icons.more_horiz_rounded),
                  label: Text(AppStrings.get('tab_more')),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _views,
              ),
            ),
          ],
        ),
      );
    } else {
      // Phone layout: BottomNavigationBar
      content = Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _views,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.alt_route_outlined),
              selectedIcon: const Icon(Icons.alt_route_rounded),
              label: AppStrings.get('tab_planner'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore_rounded),
              label: AppStrings.get('tab_live'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.timeline_outlined),
              selectedIcon: const Icon(Icons.timeline_rounded),
              label: AppStrings.get('tab_lines'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.bus_alert_outlined),
              selectedIcon: const Icon(Icons.bus_alert_rounded),
              label: AppStrings.get('tab_nearby'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz_rounded),
              selectedIcon: const Icon(Icons.more_horiz_rounded),
              label: AppStrings.get('tab_more'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        content,
        const RingingAlarmOverlay(),
      ],
    );
  }
}
