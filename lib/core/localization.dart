enum AppLang { fi, sv, en }

class AppStrings {
  static AppLang currentLang = AppLang.fi;

  static const Map<String, Map<AppLang, String>> _strings = {
    'tab_live': {AppLang.fi: 'Live-kartta', AppLang.sv: 'Livekarta', AppLang.en: 'Live Map'},
    'tab_lines': {AppLang.fi: 'Linjat', AppLang.sv: 'Linjer', AppLang.en: 'Lines'},
    'tab_planner': {AppLang.fi: 'Reittiopas', AppLang.sv: 'Reseplanerare', AppLang.en: 'Journey Planner'},
    'tab_nearby': {AppLang.fi: 'Lähipysäkit', AppLang.sv: 'Närhållplatser', AppLang.en: 'Nearby Stops'},
    'tab_more': {AppLang.fi: 'Lisää', AppLang.sv: 'Mer', AppLang.en: 'More'},
    
    // Live Map
    'search_line_placeholder': {AppLang.fi: 'Hae linjaa (esim. 550, 4, M1)...', AppLang.sv: 'Sök linje...', AppLang.en: 'Search line...'},
    'vehicles_count': {AppLang.fi: 'ajoneuvoa alueella', AppLang.sv: 'fordon i området', AppLang.en: 'vehicles in area'},
    'vehicle_heading_to': {AppLang.fi: 'Määränpää', AppLang.sv: 'Destination', AppLang.en: 'Destination'},
    'next_stop': {AppLang.fi: 'Seuraava pysäkki', AppLang.sv: 'Nästa hållplats', AppLang.en: 'Next stop'},
    'route_details': {AppLang.fi: 'Linjan reitti', AppLang.sv: 'Linjerutt', AppLang.en: 'Line route'},
    'follow_vehicle': {AppLang.fi: 'Seuraa ajoneuvoa', AppLang.sv: 'Följ fordon', AppLang.en: 'Follow vehicle'},
    'live_connected': {AppLang.fi: 'Reaaliaika yhdistetty', AppLang.sv: 'Realtid ansluten', AppLang.en: 'Realtime connected'},
    'live_connecting': {AppLang.fi: 'Yhdistetään reaaliaikaan...', AppLang.sv: 'Ansluter...', AppLang.en: 'Connecting...'},

    // Nearby
    'nearby_title': {AppLang.fi: 'Lähipysäkit osoitteesta', AppLang.sv: 'Närhållplatser från adress', AppLang.en: 'Nearby Stops from Address'},
    'change_address': {AppLang.fi: 'Vaihda osoitetta', AppLang.sv: 'Ändra adress', AppLang.en: 'Change address'},
    'search_radius': {AppLang.fi: 'Hakusäde', AppLang.sv: 'Sökradie', AppLang.en: 'Search radius'},
    'no_stops_found': {AppLang.fi: 'Ei pysäkkejä valitulla säteellä.', AppLang.sv: 'Inga hållplatser inom radien.', AppLang.en: 'No stops found within radius.'},
    'increase_radius_hint': {AppLang.fi: 'Kokeile kasvattaa hakusädettä liukusäätimellä.', AppLang.sv: 'Försök öka radien med reglaget.', AppLang.en: 'Try increasing the radius slider.'},

    // Planner
    'from': {AppLang.fi: 'Mistä', AppLang.sv: 'Från', AppLang.en: 'From'},
    'to': {AppLang.fi: 'Mihin', AppLang.sv: 'Till', AppLang.en: 'To'},
    'add_via': {AppLang.fi: 'Lisää välipiste', AppLang.sv: 'Lägg till via-punkt', AppLang.en: 'Add waypoint'},
    'search_routes': {AppLang.fi: 'Hae reitit', AppLang.sv: 'Sök rutter', AppLang.en: 'Search routes'},
    'route_options': {AppLang.fi: 'Reittivaihtoehdot', AppLang.sv: 'Ruttalternativ', AppLang.en: 'Route alternatives'},

    // Safety & Info
    'emergency_contacts': {AppLang.fi: 'Turvallisuus & Yhteystiedot', AppLang.sv: 'Säkerhet & Kontakter', AppLang.en: 'Safety & Contacts'},
    'call_emergency': {AppLang.fi: 'Soita', AppLang.sv: 'Ring', AppLang.en: 'Call'},
    'disruptions_alerts': {AppLang.fi: 'Liikennehäiriöt & Tiedotteet', AppLang.sv: 'Trafikstörningar', AppLang.en: 'Disruptions & Alerts'},
    'favorites': {AppLang.fi: 'Suosikit', AppLang.sv: 'Favoriter', AppLang.en: 'Favorites'},
    'settings': {AppLang.fi: 'Asetukset', AppLang.sv: 'Inställningar', AppLang.en: 'Settings'},
    'map_tile_source': {AppLang.fi: 'Karttapohja', AppLang.sv: 'Kartbotten', AppLang.en: 'Map Base Layer'},
  };

  static String get(String key) {
    return _strings[key]?[currentLang] ?? _strings[key]?[AppLang.fi] ?? key;
  }
}
