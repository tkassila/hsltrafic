import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/notification_service.dart';
import '../models/transit_mode.dart';
import '../models/trip_alarm.dart';
import 'app_state.dart';

/// Hallinnoi käyttäjän matkahälytyksiä ja huomiohälytysäänen toistoa.
class AlarmController extends ChangeNotifier {
  final Services _services;
  final NotificationService _notifications;
  final List<TripAlarm> _alarms = [];
  Timer? _checkTimer;
  Timer? _soundTimer;
  Timer? _ringTimeoutTimer;

  TripAlarm? _ringingAlarm;

  AlarmController(this._services, [NotificationService? notifications])
      : _notifications = notifications ?? NotificationService.instance {
    _loadFromStorage();
    _checkTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkAlarms());
  }

  List<TripAlarm> get alarms => List.unmodifiable(_alarms);

  /// Aktiiviset hälytykset, joita ei ole vielä kuitattu/laukaistu ja joiden lähtöaika on tulevaisuudessa.
  List<TripAlarm> get activeAlarms => _alarms
      .where((a) => !a.isTriggered && a.departureTime.isAfter(DateTime.now().subtract(const Duration(minutes: 5))))
      .toList();

  TripAlarm? get ringingAlarm => _ringingAlarm;
  bool get isRinging => _ringingAlarm != null;

  void _loadFromStorage() {
    try {
      final raw = _services.repo.loadAlarms();
      _alarms.clear();
      for (final item in raw) {
        _alarms.add(TripAlarm.fromJson(item));
      }
      _alarms.sort((a, b) => a.alarmTime.compareTo(b.alarmTime));
    } catch (e) {
      debugPrint('Error loading trip alarms: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final jsonList = _alarms.map((a) => a.toJson()).toList();
      await _services.repo.saveAlarms(jsonList);
    } catch (e) {
      debugPrint('Error saving trip alarms: $e');
    }
  }

  /// Lisää uuden hälytyksen. Palauttaa kokonaismäärän aktiivisia hälytyksiä.
  Future<int> addAlarm(TripAlarm alarm) async {
    // Poistetaan mahdollinen vanha duplikaatti samalle linjalle ja lähtöajalle
    _alarms.removeWhere(
      (a) =>
          a.line == alarm.line &&
          a.stopName == alarm.stopName &&
          a.departureTime == alarm.departureTime,
    );

    _alarms.add(alarm);
    _alarms.sort((a, b) => a.alarmTime.compareTo(b.alarmTime));
    await _saveToStorage();

    // Ajastetaan järjestelmätason paikallisilmoitus (lukitusnäyttö ja lepotila)
    try {
      await _notifications.requestPermissions();
      await _notifications.scheduleAlarm(alarm);
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }

    // Jos hälytysaika on jo heti käsillä tai menneisyydessä mutta lähtö tulevaisuudessa, laukaistaan heti
    final now = DateTime.now();
    if (!alarm.isTriggered && (now.isAfter(alarm.alarmTime) || now.isAtSameMomentAs(alarm.alarmTime))) {
      if (alarm.departureTime.isAfter(now)) {
        triggerAlarm(alarm);
      }
    }

    notifyListeners();
    return activeAlarms.length;
  }

  Future<void> removeAlarm(String id) async {
    _alarms.removeWhere((a) => a.id == id);
    if (_ringingAlarm?.id == id) {
      dismissRinging();
    }
    try {
      await _notifications.cancelAlarm(id);
    } catch (_) {}
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> clearAllAlarms() async {
    _alarms.clear();
    dismissRinging();
    try {
      await _notifications.cancelAll();
    } catch (_) {}
    await _saveToStorage();
    notifyListeners();
  }

  void _checkAlarms() {
    if (_ringingAlarm != null) return;
    final now = DateTime.now();

    for (final alarm in _alarms) {
      if (!alarm.isTriggered && (now.isAfter(alarm.alarmTime) || now.isAtSameMomentAs(alarm.alarmTime))) {
        // Jos hälytys ei ole vanhentunut yli 20 minuuttia sitten
        if (now.difference(alarm.alarmTime).inMinutes < 20) {
          triggerAlarm(alarm);
          break;
        } else {
          // Vanhentunut hälytys merkitään lauenneeksi ilman ääntä
          alarm.isTriggered = true;
          _saveToStorage();
        }
      }
    }
  }

  /// Käynnistää pitkään soivan huomiohälytyksen.
  void triggerAlarm(TripAlarm alarm) {
    _ringingAlarm = alarm;
    alarm.isTriggered = true;
    _saveToStorage();

    // Toistuva hälytysääni ja värinä
    _playAlertSoundAndVibration();
    _soundTimer?.cancel();
    _soundTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      _playAlertSoundAndVibration();
    });

    // Automaattinen hiljennys 90 sekunnin kuluttua
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(const Duration(seconds: 90), () {
      dismissRinging();
    });

    notifyListeners();
  }

  void _playAlertSoundAndVibration() {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Kuittaa tai hiljentää soivan hälytyksen.
  void dismissRinging() {
    _soundTimer?.cancel();
    _soundTimer = null;
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _ringingAlarm = null;
    notifyListeners();
  }

  /// Testikäyttöä varten
  void testRinging([TripAlarm? sampleAlarm]) {
    final alarm = sampleAlarm ??
        TripAlarm(
          id: 'test_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Testihälytys',
          line: '550',
          mode: TransitMode.bus,
          destination: 'Itäkeskus',
          stopName: 'Otaniemi',
          departureTime: DateTime.now().add(const Duration(minutes: 10)),
          walkStartTime: DateTime.now().add(const Duration(minutes: 7)),
          alarmTime: DateTime.now(),
          source: 'test',
        );
    triggerAlarm(alarm);
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _soundTimer?.cancel();
    _ringTimeoutTimer?.cancel();
    super.dispose();
  }
}
