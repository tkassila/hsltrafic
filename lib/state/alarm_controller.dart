import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import '../data/notification_service.dart';
import '../models/alarm_sound_type.dart';
import '../models/transit_mode.dart';
import '../models/trip_alarm.dart';
import 'app_state.dart';

/// Hallinnoi käyttäjän matkahälytyksiä ja huomiohälytysäänen toistoa.
class AlarmController extends ChangeNotifier {
  static const Duration alarmDuration = Duration(minutes: 2);

  final Services _services;
  final NotificationService _notifications;
  final AudioPlayer? _injectedPlayer;
  final List<TripAlarm> _alarms = [];

  Timer? _checkTimer;
  Timer? _vibrateTimer;
  Timer? _ringTimeoutTimer;
  Timer? _countdownTimer;
  Timer? _previewTimer;

  AudioPlayer? _audioPlayer;
  AudioPlayer? _previewPlayer;
  TripAlarm? _ringingAlarm;
  DateTime? _ringingStartTime;
  int _ringingRemainingSeconds = 120;
  bool _isPreviewing = false;

  AlarmController(
    this._services, [
    NotificationService? notifications,
    AudioPlayer? injectedPlayer,
  ])  : _notifications = notifications ?? NotificationService.instance,
        _injectedPlayer = injectedPlayer {
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
  int get ringingRemainingSeconds => _ringingRemainingSeconds;
  bool get isPreviewing => _isPreviewing;

  bool get _canUseAudioPlayer {
    if (_injectedPlayer != null) return true;
    if (kIsWeb) return true;
    try {
      return !Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return true;
    }
  }

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

  /// Käynnistää huomiohälytyksen (maksimikesto 2 minuuttia tai kunnes kuitataan).
  void triggerAlarm(TripAlarm alarm) {
    _ringingAlarm = alarm;
    _ringingStartTime = DateTime.now();
    _ringingRemainingSeconds = 120;
    alarm.isTriggered = true;
    _saveToStorage();

    // Käynnistetään voimakas hälytysääni ja toistuva värinä
    _startAlarmAudioAndVibration();

    // Automaattinen hiljennys maksimissaan 2 minuutin kuluttua
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(alarmDuration, () {
      dismissRinging();
    });

    // Sekuntilaskuri käyttöliittymälle
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_ringingAlarm == null || _ringingStartTime == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_ringingStartTime!).inSeconds;
      final remaining = (120 - elapsed).clamp(0, 120);
      _ringingRemainingSeconds = remaining;
      notifyListeners();
      if (remaining <= 0) {
        timer.cancel();
        dismissRinging();
      }
    });

    notifyListeners();
  }

  Future<void> _startAlarmAudioAndVibration() async {
    _playVibration();
    _vibrateTimer?.cancel();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      _playVibration();
    });

    if (!_canUseAudioPlayer) {
      _playSystemAlert();
      return;
    }

    try {
      _audioPlayer ??= _injectedPlayer ?? AudioPlayer();
      await _audioPlayer!.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientExclusive,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.duckOthers,
          },
        ),
      ));

      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
      final volume = _services.settings.alarmVolume;
      await _audioPlayer!.setVolume(volume);

      final sound = _services.settings.alarmSound;
      await _audioPlayer!.play(AssetSource(sound.assetPath));
    } catch (e) {
      debugPrint('Error starting alarm audio player: $e');
      _playSystemAlert();
    }
  }

  void _playVibration() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  void _playSystemAlert() {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  /// Esikuuntele valittua hälytysääntä ja äänenvoimakkuutta.
  Future<void> previewSound(AlarmSoundType sound, double volume) async {
    await stopPreview();
    if (!_canUseAudioPlayer) {
      _playSystemAlert();
      return;
    }

    try {
      _previewPlayer ??= _injectedPlayer ?? AudioPlayer();
      await _previewPlayer!.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.duckOthers,
          },
        ),
      ));

      await _previewPlayer!.setVolume(volume.clamp(0.0, 1.0));
      await _previewPlayer!.setReleaseMode(ReleaseMode.stop);
      _isPreviewing = true;
      notifyListeners();

      await _previewPlayer!.play(AssetSource(sound.assetPath));

      _previewTimer?.cancel();
      _previewTimer = Timer(const Duration(seconds: 4), () {
        stopPreview();
      });
    } catch (e) {
      debugPrint('Error previewing sound: $e');
      _playSystemAlert();
      _isPreviewing = false;
      notifyListeners();
    }
  }

  /// Pysäyttää esikuuntelun.
  Future<void> stopPreview() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    if (_previewPlayer != null) {
      try {
        await _previewPlayer!.stop();
      } catch (_) {}
    }
    if (_isPreviewing) {
      _isPreviewing = false;
      notifyListeners();
    }
  }

  /// Kuittaa tai hiljentää soivan hälytyksen välittömästi.
  void dismissRinging() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;

    if (_audioPlayer != null) {
      try {
        _audioPlayer!.stop();
      } catch (_) {}
    }

    _ringingAlarm = null;
    _ringingRemainingSeconds = 120;
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
    _vibrateTimer?.cancel();
    _ringTimeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _previewTimer?.cancel();
    _audioPlayer?.dispose();
    _previewPlayer?.dispose();
    super.dispose();
  }
}
