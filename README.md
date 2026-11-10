# FI Liikenne & Reittiopas (Flutter)

Moderni, monipuolinen ja responsiivinen Flutter-sovellus pääkaupunkiseudun (HSL), Waltti-kaupunkiseutujen (Tampere, Turku, Oulu, Jyväskylä, Kuopio, Lahti ym.) sekä koko Suomen VR-kaukoliikenteen reaaliaikaiseen seurantaan, reittisuunnitteluun ja turvallisuuteen niin puhelimilla kuin tableteilla.

---

## 🌟 Tärkeimmät ominaisuudet

### 1) Matkan suunnittelu (Reittiopas)
- **Monipistehaku (Välipisteet)**: Lisää reitille useita välipisteitä (`+ Lisää välipiste`), poista ja järjestä reittipisteitä vapaasti.
- **Koko Suomen kaukoliikenne & VR-kaukojunat**: Kaupunkien väliset reitit (esim. Helsinki ➔ Tampere, Tampere ➔ Turku, Oulu ➔ Helsinki) lasketaan automaattisesti valtakunnallisella Matka.fi-reitittimellä (VR:n InterCity-, Pendolino- ja taajamajunat sekä kaukobussit).
- **Kulkumuotojen pikasuodatus**: Valitse hakukortin suodattimista halutessasi pelkät junat (`Juna (VR & lähijunat)`), bussit, ratikat, metro tai lautat.
- **Valtakunnallinen paikkahaku**: Haku tunnistaa suoraan kaikki Suomen rautatieasemat (esim. Tampereen asema, Helsingin päärautatieasema, Turun asema), lentokentät, satamat, kaupungit ja osoitteet.
- **Nopeimmat reittiyhdistelmät**: Reittilaskenta metro-, juna-, ratikka-, bussi-, runkolinja-, lautta- ja kävely-yhteyksille.
- **Optimointivalinnat**: Nopein reitti, vähiten vaihtoja tai vähiten kävelyä.
- **Yksityiskohtaiset vaiheet**: Reitin esittäminen kartalla värillisinä polyviivoina, vaihtoasemat, arvioidut matka-ajat ja välipysäkit.
- **Poikkeustilannevaroitukset**: Jos valitun reitin jollain osuudella on voimassa oleva häiriö tai poikkeusreitti, reittikortissa näytetään suoraan varoitus ja kiertoreitin kuvaus.

### 2) Kulkuneuvojen seuranta ja reaaliaika (Live-kartta)
- **Huipputarkka kahden lähteen reaaliaikapaikannus**:
  - **HSL MQTT (HFP v3.1.1)** (`mqtt.hsl.fi`) erittäin tiheään telemetriaan.
  - **Digitransit HTTPS GraphQL -varajärjestelmä**: Vuorot, aikataulut ja reitit haetaan varmatoimisesti Digitransitista, joten live-seuranta toimii aina vaikka MQTT-yhteys katkeaisi tai olisi mobiiliverkossa estetty.
- **Sulava liikeinterpolointi & kulkusuuntanuoli**:
  - Ajoneuvojen sijainti, kulkusuunta (heading) ja nopeus interpoloidaan sekunnin murto-osan tarkkuudella pysäkkien välillä (2 s välein ilman turhaa verkkoliikennettä), joten kulkuneuvot liikkuvat kartalla pehmeästi.
  - Ajoneuvon paikka sovitetaan tien ja radan todelliseen GTFS-polyviivageometriaan (`snapToPolyline`, `interpolateAlongPolyline`), jolloin vuorot eivät koskaan oikaise talojen tai kortteleiden yli mutkissa.
  - **Kulkusuuntanuoli vuororenkaan edessä**: Liikkeessä olevalle vuorolle näytetään vuororenkaan edessä selkeä, siisti nuoli, joka osoittaa menosuuntaan. Jos vuoro seisoo päätepysäkillä lähtöä odottamassa ja nopeus on 0 km/h, suuntanuolta ei näytetä.
- **Älykäs lähipysäkkien linjavalinta, "Kaikkia"-painike & keskeytys**:
  - Yläpalkin pikanapit suodattavat automaattisesti näkyviin vain ne lähilinjat (5 km säteellä), joilla kyselyn hetkellä on vuoroja ajossa.
  - **"Kaikkia"-painonappi**: Yhdellä napautuksella otetaan live-seurantaan kaikki lähipysäkkien aktiiviset linjat ja niiden vuorot.
  - **Kyselyn keskeytys (x-ruksi)**: Sekä tietyn linjan että "Kaikkia"-haun kyselyn tai seurannan voi keskeyttää välittömästi hakupalkin x-painikkeesta, tilakortin x-ruksista tai napauttamalla aktiivista pikanappia uudelleen.
- **Kirjoitusnäppäimistön sulkeminen karttaa häiritsemättä**:
  - Hakukenttään kirjoitettaessa näppäimistön voi sulkea hakurivin kuvakkeesta tai suoraan näppäimistön yläpuolelle ilmestyvästä kelluvasta *"Sulje näppäimistö"* -painikkeesta.
  - Kartan napauttaminen tai siirtäminen näppäimistön ollessa auki sulkee näppäimistön vaikuttamatta kartan tilaan (ei poista valittua vuoroa, linjaa tai pysäkkiä kartalta).
- **Katkeamaton yöliikenteen tuki (klo 00–05)**:
  - Huomioi joukkoliikenteen liikennevuorokauden vaihdon (klo 04:30): hakee automaattisesti sekä edellisen että alkavan vuorokauden vuorot ja käsittelee yli 24 tunnin GTFS-aikaleimat oikein.
- **Päätepysäkillä lähtöä odottavan vuoron tila**:
  - Kun liikenneväline seisoo päätepysäkillä lähtöä odottamassa (nopeus 0 km/h), tilana näytetään selkeästi **"Lähtöön 21 min"** (eikä virheellisesti "21 min etuajassa").
  - Alakortissa näytetään tällöin *"Lähtöpysäkki"* ja tarkka lähtöaika. Päätepysäkillä taukoa pitävä vuoro säilyy kartalla jopa 10 minuuttia.
- **Tulevien pysäkkien interaktiivinen tarkastelu linjalta kartalla**:
  - Kun seurattavan vuoron tulevia pysäkkejä listataan alakortissa, minkä tahansa pysäkin napauttaminen näyttää ja korostaa kyseisen pysäkin suoraan vuoron reittiviivalta kartalla.
  - Kartta siirtyy valitulle pysäkille, ja pysäkin yläpuolelle avautuu tyylikäs infokupla (pysäkin nimi, tunnus/laituri ja saapumisaika). Useat pysäkkimerkinnät asetellaan siististi allekkain ilman päällekkäisyyttä.
  - Vuoron pysäkkilistan sulkeminen x-ruksista sulkee vain alakortin: reittiviiva ja pysäkit säilyvät kartalla ja lista on helppo avata uudelleen kelluvasta palkista.
- **Google Street View -tuki kaikilla sivuilla (pitkä painallus pysäkkiin)**:
  - Minkä tahansa pysäkin painaminen pitkään avaa suoraan **Google Street View** -360°-panoraaman pysäkin tarkasta sijainnista kaikissa päänäkymissä:
    - **Linjat**: Reitin pysäkit, hakutulosmerkit ja valitun pysäkin infolaatikko.
    - **Lähipysäkit**: Kartan pysäkkimerkit, reittipysäkit ja pysäkkilistan otsikkorivit.
    - **Live-kartta**: Vuoron reitin pysäkkirenkaat kartalla, valitun pysäkin infokupla sekä tulevien pysäkkien lista.
    - **Reittiopas**: Reittiosuuksien nousu- ja poistumispysäkit kartalla.
- **Linjahaku ja pikavalinnat**:
  - Tunnistaa runkonumerot ja kirjainvariantit symmetrisesti (esim. haku "69" löytää myös "69N", ja haku "9" löytää ratikan 9 ja 9N muttei väärää linjaa 90).
  - Tukee usean linjan hakua pilkulla eroteltuna (esim. "9, 69").
  - Ajoneuvoa napauttamalla aukeaa kattava alakortti: reitin eteneminen, tulevat pysäkit ja saapumisajat, nopeus sekä ajoneuvon seuraaminen kartalla (`Seuraa vuoroa`).

### 3) Vuorolistan kuormitustieto (Täyttöaste & matkustajamäärä - HSL:n käytäntö)
- **Automaattinen kuormitustiedon nouto**:
  - Vuorotietoihin haetaan aina automaattisesti Digitransitin GraphQL API:sta reaaliaikainen `occupancy { occupancyStatus }` -tila (`MANY_SEATS_AVAILABLE`, `FEW_SEATS_AVAILABLE`, `STANDING_ROOM_ONLY`, `FULL` jne.).
  - Jos vuorolle on saatavilla kuormitustieto, vuororivillä näytetään kompakti kuormituskuvake (`Icon`) ja tilan mukainen värikoodi (vihreä, keltainen/oranssi, punainen).
- **Kuormitustiedon avaaminen vuoroa pitkään painamalla (tai napauttamalla)**:
  - Vuororivin pitkä painallus (tai napautus) avaa **Vuoron kuormitustieto** -alalevyn (`showDepartureOccupancySheet`).
  - Hakee reaaliaikaisesti tuoreimman kuormitusennusteen `trip(id: ...)` ja yhdistää sen mahdolliseen HFP MQTT -live-ajoneuvoon (`occu` %).
  - Näyttää HSL:n mukaisen 4-portaisen visuaalisen kuormitusmittarin, sanallisen selitteen istumapaikkatilanteesta ja APC-ohjeistuksen:
    - *Vihreä*: Paljon istumapaikkoja vapaana (runsaasti tilaa)
    - *Keltainen/oranssi*: Vähän istumapaikkoja vapaana
    - *Oranssi*: Vain seisomapaikkoja
    - *Punainen*: Erittäin täynnä / Täynnä
    - *Harmaa*: Kuormitustietoa ei saatavilla tälle vuorolle (ajoneuvoyksikössä ei ole automaattisia matkustajalaskureita).
  - Mahdollisuus asettaa lähtöhälytys suoraan samasta näkymästä yhdellä napautuksella.

### 4) Linjareitit ja pysäkkiaikataulut (Linjat-sivu)
- **Oma "Linjat"-näkymä päänäppäimistössä ja navigaatiossa**:
  - Helppo pääsy suoraan päänäkymän navigaatiopalkista (`Linjat` / `Icons.timeline_rounded`).
- **Monipuolinen kaksoishakutila (Linja- tai Pysäkkihaku)**:
  - Hakukentän vierestä voi yhdellä napautuksella valita haetaanko **Linjaa** vai **Pysäkkiä** (`SegmentedButton`).
  - **Välilyöntien automaattinen siivous**: Siivoaa automaattisesti turhat välilyönnit edestä ja takaa (`trim()`) sekä linja- että pysäkkikyselyissä.
  - **Pysäkkikoodien ja nimien täysi tuki**: Haku tunnistaa suoraan HSL-pysäkkikoodit niin pienellä kuin isolla kirjaimella (esim. `h080`, `H0801`, `h 080` tai pelkkä numerotunnus `0801`) sekä pysäkkien nimet (esim. `Kamppi`, `Erottaja`). Jos koodilla löytyy useita pysäkkejä (kuten `h080` -> Aleksanterin teatteri, Erottaja, Fredrikinkatu), kaikki löytyneet pysäkit merkitään kartalle ja esitetään pikanappeina helppoa valintaa varten.
  - Tekstikentässä on integroitu **x-ruksi** tekstikentän nopeaa nollausta varten, erillinen **Hae**-painonappi sekä painike mobiilinäppäimistön piilottamiseksi.
- **Linjareitin, päätepysäkkien ja välipysäkkien piirto kartalle**:
  - Linjan haussa kartalle piirretään linjan virallinen GTFS-reittigeometria (selkeä kaksivärinen polyviiva).
  - Päätepysäkit (lähtö- ja pääteasema) korostetaan erityisinä ikoneina (lähtöpysäkki ja lippu/maali) ja kaikki niiden väliset välipysäkit merkitään selkeästi kartalle.
  - Jos linjalla on useita suuntia tai reittikuvioita (esim. menopaluu tai haarautuvat reitit), suuntaa voi vaihtaa suoraan suuntanapeista (pattern chips).
- **Interaktiivinen pysäkin valinta ja 24 tunnin vuoroaikataulu**:
  - Pysäkkiä kartalta napauttamalla valittu pysäkki **markeerataan selkeästi lähipysäkkikartan tyyliin**:
    - Pysäkkirengas alkaa hohtaa kulkumuodon värissä (`BoxShadow`-hehku, valkoinen reunus ja kulkumuotokuvake).
    - Pysäkin viereen avautuu tyylikäs tumma infolaatikko ja osoitinnuoli, joka asettuu automaattisesti reittiviivan suunnan mukaan (oikealle tai yläpuolelle) peittämättä linjageometriaa.
  - Kartan alapuolelle avautuu kattava aikataulukortti:
    - Pysäkin tiedot (nimi, koodi, vyöhyke, laituritieto ja kulkumuoto).
    - Koko vuorokauden vuorolähdöt aikajärjestyksessä reaaliaikaennusteineen ja mahdolliset häiriömerkinnät.
    - **Aikataulukauden valinta**: Aikatauluja voi tarkastella kätevästi tänään, arkisin, lauantaisin ja sunnuntaisin.
  - **Markeerauksen säilyminen aikataululistan sulkemisen jälkeen**:
    - Kun aikataulukortti suljetaan oikean yläkulman x-ruksista, **valitun pysäkin markeeraus ja infokupla säilyvät kartalla**.
    - Ruudun alalaitaan ilmestyy huomaamaton kelluva painike (`[Pysäkin nimi] aikataulu`), josta aikataulun voi avata heti takaisin.
- **Google Street View -panoraaman avaus pysäkistä**:
  - **Pitkä painallus pysäkkiin**: Pysäkkirengasta tai infokuplaa pitkään painamalla sovellus värähtää haptisesti ja avaa suoraan **Google Street View** -näkymän kyseisen pysäkin tarkasta sijainnista.
  - Street View voidaan avata myös yhdellä napautuksella suoraan infolaatikon tai aikataulukortin keltaisesta Street View -kuvakkeesta.
- **Pysäkkihaku ja lähtevien linjojen tutkiminen**:
  - Pysäkin nimellä tai koodilla haettaessa pysäkki keskitetään ja näytetään kartalla.
  - Alapuolelle avautuu pysäkiltä lähtevien linjojen lista sekä vuorokohtaiset pysäkkiajat.
  - **Linjan reitti kartalla pysäkkiä korostaen**: Kun pysäkin listasta valitaan tietty linja, kyseisen linjan reitti piirretään välittömästi kartalle päätepysäkkeineen ja välipysäkkeineen siten, että valittu pysäkki pysyy korostettuna linjan kyseisessä menosuunnassa.

### 5) Omat reitit, pysäkit ja matkahälytykset
- **Tallennetut reitit**: Tallenna usein kuljetut reitit (esim. "Koti ➔ Työpaikka Otaniemi") välipisteineen nopeaa yhden napautuksen käyttöä varten.
- **Suosikkipysäkit ja lähdöt**: Nopea pääsy usein käytettyjen asemien lähtötauluihin ja laituritietoihin.
- **Matka- ja lähtöhälytykset (Trip Alarms)**:
  - Aseta hälytys tietylle lähdölle tai pysäkille pitkällä painalluksella (esim. 5 tai 10 min ennen bussiin/junaan nousua).
  - Hälytysten hallintadialogi aukeaa yläpalkin herätyskellokuvakkeesta, josta voi tarkastella, poistaa ja kuitata soivia hälytyksiä.
- **Kartan ja hakukortin joustava näkyvyys**:
  - Yläpalkin pikanäppäimillä voidaan helposti piilottaa tai palauttaa hakukenttä tai kartta, jotta näyttötila saadaan optimoitua tilanteen mukaan (esim. täysikokoinen karttanäkymä tai pitkä pysäkkilista).
- **Pysyvä tallennus**: Kaikki suosikit ja hälytykset säilyvät laitteen muistissa `SharedPreferences`-kirjaston avulla.

### 6) Paikkakunnat, valtakunnallinen tuki ja oletusasetukset
- **Dynaaminen alue- ja reititinvalitsin (HSL / Waltti / Koko Suomi)**:
  - Sovellus tukee nyt kaikkia Suomen joukkoliikennealueita samalla Digitransit-reitityksellä:
    - **Automaattinen (GPS)** *(Oletus)*: Päättelee paikkakunnan automaattisesti käyttäjän sijainnin mukaan (Helsinki ➔ HSL, Tampere/Turku/Oulu/Jyväskylä ➔ Waltti, muualla ➔ Koko Suomi).
    - **Pääkaupunkiseutu (HSL)**: Helsinki, Espoo, Vantaa, Kauniainen, lähialueet.
    - **Waltti-kaupungit**: Tampere (Nysse), Turku (Föli), Oulu, Jyväskylä (Linkki), Kuopio (Vilkku), Lahti (LSL) ja muut Waltti-seudut.
    - **Koko Suomi (VR & Kaukoliikenne)**: Koko valtakunnan kattava Matka.fi-reititin (VR-kaukojunat, Matkahuollon kaukobussit ja seutuyhteydet).
  - Alueen voi vaihtaa milloin tahansa yläpalkin tai hakukentän pikanapista (`TransitRegionSelectorPill`) tai suoraan `Asetukset`-valikosta.
- **Valtakunnallinen osoite- ja asemapaikkahaku (Pelias)**:
  - Osoite- ja paikkahausta poistettu vanha HSL-aluereunusrajaus (`boundary.rect`), jolloin haku toimii koko Suomen laajuisesti (`boundary.country: FIN`).
  - Haku löytää suoraan **VR:n rautatieasemat** (esim. Tampereen rautatieasema, Helsingin päärautatieasema, Turun asema), lentokentät, satamat, kaupungit ja osoitteet.
  - Haku käyttää aktiivisen alueen dynaamista kohdistuspistettä (`focus.point`): kun valittuna on Tampere, Tampereen kohteet sijoittuvat listan kärkeen; kun HSL, pääkaupunkiseudun kohteet.
- **Älykäs reititysautomaatio kaupunkien ja VR-kaukoliikenteen välillä**:
  - Reittiopas päättelee automaattisesti oikean reitityspalvelimen: paikallismatkat (esim. Tampereen sisällä) reititetään kaupungin paikallisverkolla (Nysse-ratikat ja bussit), ja kaupunkien väliset tai seuturajan ylittävät matkat (esim. Helsinki ➔ Tampere, etäisyys > 38 km) reititetään valtakunnallisella Koko Suomen reitittimellä (VR:n InterCity-, Pendolino- ja taajamajunat sekä kaukobussit).
  - Jos paikallisreititin ei löydä yhteyttä, kysely kokeilee automaattisesti valtakunnallista reititintä.
- **Oletuskarttana OpenStreetMap (OSM)**:
  - Sovelluksen oletuskarttana käytetään avointa **OpenStreetMap**-tiilipalvelinta (`https://tile.openstreetmap.org`).
  - Asetuksista (`Lisää` ➔ `Asetukset`) karttapohjaksi voi vaihtaa myös **Digitransit (HSL)**- tai **CARTO tumma** -karttatiilet.
- **Lähipysäkkien oletusetäisyys 1,5 km (1500 m)**:
  - Lähipysäkkien haun oletussäteenä käytetään **1,5 km** (1500 metriä), mikäli käyttäjä ei ole määrittänyt toista sätearvoa.
  - Sädettä voi säätää vapaasti sekä suoraan `Lähipysäkit`-näkymän liukusäätimestä että `Asetukset`-valikosta (500 m – 3 000 m).
- **Teema ja kieli**:
  - Tuki tummalle, vaalealle ja järjestelmän teemalle sekä kielivalinnoille (suomi, ruotsi, englanti).

### 7) Liikennetiedotteet ja häiriöinfot
- **Älykkäät push-ilmoitukset**:
  - Vastaanota hälytykset reitti- ja aikataulumuutoksista, perutuista vuoroista sekä laajoista joukkoliikenteen häiriötilanteista myös silloin, kun sovellus on suljettuna.
  - Mahdollisuus testata ilmoituksia suoraan sovelluksesta ("Testaa hälytystä").
  - Unread-ilmoituslaskuri navigointipalkissa.
- **Liikennemuotojen tilannekatsaus**: Reaaliaikainen yhteenveto metron, ratikoiden, junien, bussien ja lauttojen liikennetilanteesta.
- **Poikkeusreitit kartalla ja reittihaussa**: Ajantasainen tieto työmaista ja korvaavista vuoroista.

### 8) Turvallisuus ja tuki (Turvavalvomot)
- **Suorat hätäyhteystiedot yhdellä napautuksella** (puhelu käynnistyy suoraan `tel:`-linkillä):
  - **112**: Yleinen hätänumero
  - **Kaupunkiliikenne Oy (HKL)**: Metron ja raitioliikenteen turvavalvomo (24/7): `09 310 1200`
  - **VR / Liikenteenohjaus**: Lähijunien ja asemien turvakeskus: `0800 166 888`
  - **HSL Asiakaspalvelu**: `09 4766 4000`
  - **Löytötavarapalvelu**: `0600 41006`
- **Toimintaohjeet**: Ohjeet asemien ja junien hätäpysäyttimien, laituriturvallisuuden, SOS-kutsutolppien ja häiriökäyttäytymisen ilmoittamiseen.
- **SOS-pikavalintapainike**: Aina saatavilla oleva punainen SOS-painike karttanäkymässä.

---

## 📱 Responsiivinen mobiili- ja tablettituki
- **Puhelimet**: Sulava alareunan navigointipalkki, laajennettavat alalevyt (bottom sheets) ja yhden käden pikatoiminnot.
- **Tabletit**: Sivupalkki (`NavigationRail`) suurentaa kartta-alaa ja mahdollistaa rinnakkaisen käytön vaaka- ja pystyasennossa.
- **Android-sovellusikoni & brändi**:
  - HSL-brändin mukainen moderni ja tyylikäs joukkoliikenneikoni (HSL-sininen tausta, valkoinen virtaviivainen kulkuneuvosilhuetti, heijastustuulilasi, LED-linjataulu ja elävä GPS-reittikaari).
  - Täysi tuki Android 8+ (API 26+) mukautuville kuvakkeille (`Adaptive Icon` / `mipmap-anydpi-v26`), pyöreille kuvakkeille (`ic_launcher_round.png`) ja squircle-kuvakkeille kaikilla tiheyksillä (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi) sekä 512×512 Google Play -assetille (`assets/icon/app_icon.png`).
  - Sovelluksen nimi Android-laitteen kotinäytöllä selkeästi **"FI Liikenne"**.

---

## 🚀 Sovelluksen ajaminen

### Työpöytä (Linux):
```bash
flutter run -d linux
```

### Verkkoselain (Web):
```bash
flutter run -d chrome
```

### Android-laite tai emulaattori:
```bash
flutter emulators --launch Pixel_7
flutter run -d android
```

### Testien ajaminen:
```bash
flutter test
```
