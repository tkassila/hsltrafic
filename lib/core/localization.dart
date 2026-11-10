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
    'help_and_info': {AppLang.fi: 'Ohje & Paikkakunnat', AppLang.sv: 'Hjälp & Regioner', AppLang.en: 'Help & Regions'},

    // Regions & Waltti guide
    'transit_region_title': {AppLang.fi: 'Liikennealue & Paikkakunta', AppLang.sv: 'Trafikregion & Stad', AppLang.en: 'Transit Region & City'},
    'waltti_cities_title': {AppLang.fi: 'Mitä ovat Waltti-kaupungit?', AppLang.sv: 'Vad är Waltti-städer?', AppLang.en: 'What are Waltti cities?'},
    'waltti_cities_desc': {
      AppLang.fi: 'Waltti on Suomen kaupunkiseutujen yhteinen joukkoliikennejärjestelmä. Sovelluksen Waltti-reititin kattaa seuraavien kaupunkien ja alueiden paikallisliikenteen aikataulut, linjat ja pysäkit:',
      AppLang.sv: 'Waltti är ett gemensamt kollektivtrafiksystem för Finlands stadsregioner. Waltti-routern täcker lokal kollektivtrafik i följande städer och regioner:',
      AppLang.en: 'Waltti is the shared public transport system for Finnish city regions. The Waltti router covers timetables, lines, and stops for the following cities and regions:',
    },
    'waltti_cities_list': {
      AppLang.fi: '• Tampere (Nysse)\n• Turku (Föli)\n• Oulu (Oulun joukkoliikenne)\n• Jyväskylä (Linkki)\n• Kuopio (Vilkku)\n• Lahti (LSL)\n• Hämeenlinna\n• Joensuu (JOJO)\n• Kotka\n• Kouvola (Koutsi)\n• Lappeenranta (Jouko)\n• Mikkeli\n• Pohjois-Pohjanmaa / Raahe\n• Rauma\n• Riihimäki\n• Rovaniemi (Linkkari)\n• Salo\n• Vaasa (Lifti)\n• Kajaani',
      AppLang.sv: '• Tammerfors (Nysse)\n• Åbo (Föli)\n• Uleåborg (Oulu)\n• Jyväskylä (Linkki)\n• Kuopio (Vilkku)\n• Lahtis (LSL)\n• Tavastehus (Hämeenlinna)\n• Joensuu (JOJO)\n• Kotka\n• Kouvola (Koutsi)\n• Villmanstrand (Jouko)\n• S:t Michel (Mikkeli)\n• Norra Österbotten / Brahestad (Raahe)\n• Raumo (Rauma)\n• Riihimäki\n• Rovaniemi (Linkkari)\n• Salo\n• Vasa (Lifti)\n• Kajana (Kajaani)',
      AppLang.en: '• Tampere (Nysse)\n• Turku (Föli)\n• Oulu\n• Jyväskylä (Linkki)\n• Kuopio (Vilkku)\n• Lahti (LSL)\n• Hämeenlinna\n• Joensuu (JOJO)\n• Kotka\n• Kouvola (Koutsi)\n• Lappeenranta (Jouko)\n• Mikkeli\n• Northern Ostrobothnia / Raahe\n• Rauma\n• Riihimäki\n• Rovaniemi (Linkkari)\n• Salo\n• Vaasa (Lifti)\n• Kajaani',
    },
    'region_guide_hsl': {
      AppLang.fi: 'Pääkaupunkiseutu (HSL): Helsinki, Espoo, Vantaa, Kauniainen, Kirkkonummi, Kerava, Sipoo, Tuusula ja Siuntio (bussit, ratikat, metro, lähijunat, lautta).',
      AppLang.sv: 'Huvudstadsregionen (HRT/HSL): Helsingfors, Esbo, Vanda, Grankulla, Kyrkslätt, Kervo, Sibbo, Tusby och Sjundeå (bussar, spårvagnar, metro, närtåg, färja).',
      AppLang.en: 'Helsinki Region (HSL): Helsinki, Espoo, Vantaa, Kauniainen, Kirkkonummi, Kerava, Sipoo, Tuusula, and Siuntio (buses, trams, metro, commuter trains, ferry).',
    },
    'region_guide_finland': {
      AppLang.fi: 'Koko Suomi (VR & Kaukoliikenne): Koko valtakunnan kattava Matka.fi-reititin, mukaan lukien VR:n kaukojunat, Matkahuollon kaukobussit, OnniBus ja seutuliikenteet.',
      AppLang.sv: 'Hela Finland (VR & Fjärrtrafik): Rikstäckande Matka.fi-router, inklusive VR:s fjärrtåg, Matkahuoltos fjärrbussar, OnniBus och regionaltrafik.',
      AppLang.en: 'All Finland (VR & Long-distance): Nationwide Matka.fi router, including VR intercity trains, Matkahuolto long-distance coaches, OnniBus, and regional lines.',
    },
    'region_guide_auto': {
      AppLang.fi: 'Automaattinen (GPS): Sovellus tunnistaa paikkakuntasi ja valitsee oikean reitityspalvelimen puolestasi laitteen GPS-sijainnin perusteella.',
      AppLang.sv: 'Automatisk (GPS): Appen känner igen din plats och väljer rätt router automatiskt baserat på enhetens GPS-position.',
      AppLang.en: 'Automatic (GPS): The app detects your city and automatically selects the correct router based on your device GPS location.',
    },
    'region_guide_intercity': {
      AppLang.fi: 'Reittiopas & Kaukoliikenne: Reittiopas reitittää automaattisesti kaupunkien väliset matkat (esim. Helsinki ➔ Tampere) valtakunnallisella VR:n kaukojunilla (InterCity, Pendolino) ja kaukobusseilla. Hakukortista voit myös suodattaa kulkumuotoja (Juna, Bussi, Ratikka, Metro, Lautta).',
      AppLang.sv: 'Ruttplanerare & Fjärrtrafik: Ruttplaneraren dirigerar automatiskt resor mellan städer (t.ex. Helsingfors ➔ Tammerfors) med VR:s fjärrtåg (InterCity, Pendolino) och fjärrbussar. Du kan också filtrera färdmedel direkt i sökkortet (Tåg, Buss, Spårvagn, Metro, Färja).',
      AppLang.en: 'Route Planner & Long-distance: The route planner automatically routes intercity trips (e.g. Helsinki ➔ Tampere) using nationwide VR trains (InterCity, Pendolino) and coaches. You can also filter modes directly in the search card (Train, Bus, Tram, Metro, Ferry).',
    },
  };

  static String get(String key) {
    return _strings[key]?[currentLang] ?? _strings[key]?[AppLang.fi] ?? key;
  }
}
