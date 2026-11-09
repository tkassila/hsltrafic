import 'dart:async';
import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/geo.dart';
import '../models/vehicle.dart';

/// HSL:n High-frequency positioning (HFP) -ajoneuvosijainnit MQTT:llä.
///
/// Tilaa vain kartan näkymää/käyttäjän ympäristöä vastaavat geohash-ruudut ja päivittää
/// tilauksia kun näkymä liikkuu.
class HfpService {
  static const _host = 'mqtt.hsl.fi';
  static const _tlsPort = 8883;
  static const _tcpPort = 1883;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;
  final _vehicles = <String, Vehicle>{};
  final _controller = StreamController<List<Vehicle>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();
  final Set<String> _topics = {};
  Timer? _emitTimer;
  Timer? _cleanTimer;
  Timer? _reconnectTimer;
  Future<void>? _connectFuture;
  bool _paused = false;
  bool _disposed = false;
  LatLng? _wantedCenter;
  double _wantedRadius = 5000;
  List<String> _wantedRouteList = const [];
  Set<String> _wantedRouteIds = {};
  bool _routeOnlyMode = false;

  /// Aktiivinen linjahakumerkkijono (esim. "69" tai "9, 69") suoraa VP.desi-tunnistusta varten.
  String lineQuery = '';
  bool Function(String candidateLine, String query)? lineMatcher;

  Stream<List<Vehicle>> get stream => _controller.stream;
  Stream<bool> get connection => _statusController.stream;
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  List<Vehicle> get current => _vehicles.values.toList();

  /// Keskeyttää MQTT-yhteyden ja taustakyselyt kun käyttäjä poistuu Live-kartalta.
  void pause() {
    _paused = true;
    _emitTimer?.cancel();
    _cleanTimer?.cancel();
    _cleanTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _topics.clear();
    final c = _client;
    _client = null;
    _connectFuture = null;
    if (c != null) {
      c.autoReconnect = false;
      try {
        c.disconnect();
      } catch (_) {}
    }
    if (!_statusController.isClosed) {
      _statusController.add(false);
    }
  }

  /// Aseta alue (keskipiste + säde metreinä) ja valinnaiset reitti-ID:t (esim. 2 km pysäkkien linjat).
  Future<void> setArea(
    LatLng center,
    double radiusMeters, {
    Iterable<String>? routeIds,
    bool routeOnly = false,
  }) async {
    _paused = false;
    _wantedCenter = center;
    _wantedRadius = radiusMeters;
    if (routeIds != null) {
      final list = <String>[];
      final set = <String>{};
      for (final raw in routeIds) {
        final id = raw.replaceFirst('HSL:', '').trim();
        if (id.isNotEmpty && set.add(id)) {
          list.add(id);
        }
      }
      _wantedRouteList = list;
      _wantedRouteIds = set;
    }
    _routeOnlyMode = routeOnly;
    if (!isConnected) {
      await _connect();
      return; // _connect tilaa halutut aiheet yhdistyessään
    }
    _syncSubscriptions();
  }

  /// Tilaa suoraan tietyt linjat/reitit (esim. käyttäjän hakiessa linjaa) tai päivitä alueen linjat.
  Future<void> setRoutes(
    Iterable<String> routeIds, {
    bool routeOnly = false,
    LatLng? center,
    double? radiusMeters,
  }) async {
    _paused = false;
    if (center != null) _wantedCenter = center;
    if (radiusMeters != null) _wantedRadius = radiusMeters;
    final list = <String>[];
    final set = <String>{};
    for (final raw in routeIds) {
      final id = raw.replaceFirst('HSL:', '').trim();
      if (id.isNotEmpty && set.add(id)) {
        list.add(id);
      }
    }
    _wantedRouteList = list;
    _wantedRouteIds = set;
    _routeOnlyMode = routeOnly;
    if (!isConnected) {
      await _connect();
      return;
    }
    _syncSubscriptions();
  }

  Future<MqttServerClient?> _tryConnectPort(int port, {required bool secure}) async {
    final id = 'hsl${DateTime.now().millisecondsSinceEpoch % 100000000}$port';
    final c = MqttServerClient.withPort(_host, id, port)
      ..setProtocolV311()
      ..secure = secure
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..logging(on: false);
    c.onConnected = () {
      if (!_statusController.isClosed) _statusController.add(true);
    };
    c.onDisconnected = () {
      if (!_statusController.isClosed) _statusController.add(false);
    };
    c.onAutoReconnected = () {
      _topics.clear();
      _syncSubscriptions();
      if (!_statusController.isClosed) _statusController.add(true);
    };
    try {
      await c.connect().timeout(const Duration(seconds: 6));
      if (c.connectionStatus?.state == MqttConnectionState.connected) {
        return c;
      }
    } catch (_) {}
    try {
      c.autoReconnect = false;
      c.disconnect();
    } catch (_) {}
    return null;
  }

  Future<void> _connect() async {
    if (_paused || _disposed) return;
    if (_connectFuture != null) {
      await _connectFuture;
      if (isConnected && !_paused && !_disposed) {
        _syncSubscriptions();
      }
      return;
    }
    _reconnectTimer?.cancel();
    final future = _doConnect();
    _connectFuture = future;
    try {
      await future;
    } finally {
      if (identical(_connectFuture, future)) {
        _connectFuture = null;
      }
    }
  }

  Future<void> _doConnect() async {
    try {
      // Yritetään ensin TLS-porttia 8883, ja jos mobiiliverkko/kättely estää sen,
      // vaihdetaan automaattisesti suoraan TCP-porttiin 1883 (kuten varhaisemmassa versiossa).
      var c = await _tryConnectPort(_tlsPort, secure: true);
      if (c == null && !_paused && !_disposed) {
        c = await _tryConnectPort(_tcpPort, secure: false);
      }
      if (c == null) {
        throw Exception('MQTT connection failed on both 8883 and 1883');
      }
      _client = c;
      if (_paused || _disposed) {
        c.autoReconnect = false;
        c.disconnect();
        return;
      }
      _sub = c.updates?.listen(_onMessages);
      _topics.clear();
      _syncSubscriptions();
      _cleanTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => _removeStale());
    } catch (_) {
      try {
        _client?.disconnect();
      } catch (_) {}
      _client = null;
      if (!_statusController.isClosed) _statusController.add(false);
      // yritä uudelleen hetken päästä vain jos Live-näkymä on aktiivinen
      if (!_paused && !_disposed) {
        _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
      }
    }
  }

  void _syncSubscriptions() {
    final c = _client;
    if (c == null || !isConnected || _paused) return;

    final wantedTopics = <String>{};
    final center = _wantedCenter;

    // 1) Tilataan aktiivisten linjojen vuorot reitin varrelta (JORE/GTFS routeId).
    // Pidetään tilattavien reittiaiheiden määrä maltillisena, jotta mqtt.hsl.fi ei ylikuormitu.
    if (_wantedRouteList.isNotEmpty) {
      final maxRoutes = _routeOnlyMode ? 24 : 14;
      for (final routeId in _wantedRouteList.take(maxRoutes)) {
        wantedTopics.add(_routeTopic(routeId));
      }
    }

    // 2) Rinnakkainen suora geohash-aluetilaus (hfpCells) AINA kun keskipiste on tiedossa!
    // Näin ajoneuvot saadaan välittömästi suoraan MQTT:stä ilman riippuvuutta Digitransit GraphQL -hausta,
    // ja linjahaussakin lähialueen vuorot löytyvät suoraan VP.desi-linjanumerolla vaikka JORE-koodi puuttuisi.
    if (center != null) {
      final cells = hfpCells(
        center,
        _routeOnlyMode ? 5000 : _wantedRadius,
        maxCells: _routeOnlyMode ? 16 : 24,
      );
      for (final cell in cells) {
        wantedTopics.add(_cellTopic(cell));
      }
    }

    for (final topic in _topics.difference(wantedTopics)) {
      c.unsubscribe(topic);
    }
    for (final topic in wantedTopics.difference(_topics)) {
      c.subscribe(topic, MqttQos.atMostOnce);
    }
    _topics
      ..clear()
      ..addAll(wantedTopics);

    // EI tyhjennetä _vehicles-muistia linjapainikkeita vaihdettaessa, jotta lähialueella
    // jo vastaanotetut vuorot (esim. K-, I-, P-junat ja bussit) näkyvät välittömästi 0 ms viiveellä
    // kun käyttäjä napauttaa eri lähilinjojen painikkeita peräkkäin!
    // LiveMapController.vehicles huolehtii näytettävien ajoneuvojen suodatuksesta.
    _removeStale();
    _emitNow();
  }

  static String _routeTopic(String routeId) =>
      '/hfp/v2/journey/ongoing/vp/+/+/+/$routeId/#';

  static String _cellTopic(String cell) =>
      '/hfp/v2/journey/ongoing/vp/+/+/+/+/+/+/+/+/+/$cell/#';

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> msgs) {
    if (_paused || _disposed) return;
    final now = DateTime.now();
    bool changed = false;
    bool urgentMatch = false;

    for (final m in msgs) {
      final p = m.payload;
      if (p is! MqttPublishMessage) continue;

      final parts = m.topic.split('/');
      if (parts.length < 14) continue;

      final vehId = '${parts[7]}/${parts[8]}';
      final prev = _vehicles[vehId];
      if (prev != null && now.difference(prev.updatedAt).inMilliseconds < 1200) {
        continue;
      }

      try {
        final text = utf8.decode(p.payload.message);
        final v = Vehicle.fromHfp(m.topic, jsonDecode(text) as Map<String, dynamic>);
        if (v != null) {
          final shortRoute = v.routeGtfsId.replaceFirst('HSL:', '');
          final matchesSearchedRoute = _wantedRouteIds.contains(shortRoute) ||
              (lineQuery.isNotEmpty && (lineMatcher?.call(v.line, lineQuery) ?? false));

          if (!_routeOnlyMode &&
              !matchesSearchedRoute &&
              _wantedCenter != null &&
              distanceMeters(_wantedCenter!, v.position) > _wantedRadius * 2.5) {
            _vehicles.remove(v.id);
            continue;
          }

          if ( prev == null && (_routeOnlyMode ? matchesSearchedRoute : _vehicles.length < 5)) {
            urgentMatch = true;
          }
          _vehicles[v.id] = v;
          changed = true;
        }
      } catch (_) {/* ohita virheellinen viesti */}
    }
    if (urgentMatch) {
      _emitNow();
    } else if (changed) {
      _scheduleEmit();
    }
  }

  void _emitNow() {
    _emitTimer?.cancel();
    if (!_controller.isClosed && !_paused) {
      _controller.add(current);
    }
  }

  void _scheduleEmit() {
    if (_emitTimer?.isActive ?? false) return;
    _emitTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_controller.isClosed && !_paused) _controller.add(current);
    });
  }

  void _removeStale() {
    final before = _vehicles.length;
    _vehicles.removeWhere((_, v) => v.isStale());
    if (_vehicles.length != before) _scheduleEmit();
  }

  void dispose() {
    _disposed = true;
    pause();
    _controller.close();
    _statusController.close();
  }
}
