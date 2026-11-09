import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/trip_alarm.dart';

String _formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Järjestelmätason ilmoituspalvelu paikallisille hälytyksille (lukitusnäyttö, taustapalvelu, ääni ja tärinä).
class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  NotificationService._internal();

  bool get _hasPlatform {
    try {
      FlutterLocalNotificationsPlatform.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  static const String _channelId = 'trip_departure_alarms';
  static const String _channelName = 'Matkalähdöt ja kävelyhälytykset';
  static const String _channelDescription =
      'Hälyttää äänellä ja tärinällä 7 minuuttia ennen kävelyn alkua';

  Future<void> initialize() async {
    if (_initialized || !_hasPlatform) return;

    try {
      tz.initializeTimeZones();
    } catch (e) {
      debugPrint('Error initializing timezone: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('Notification clicked: ${response.payload}');
        },
      );

      // Luodaan korkeimman prioriteetin ilmoituskanava Androidille
      final androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing local notifications: $e');
    }
  }

  /// Pyytää tarvittavat ilmoitusoikeudet (Android 13+ POST_NOTIFICATIONS ja tarkat hälytykset)
  Future<bool> requestPermissions() async {
    if (!_hasPlatform) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final notifGranted = await android.requestNotificationsPermission();
        final exactGranted = await android.requestExactAlarmsPermission();
        return (notifGranted ?? true) && (exactGranted ?? true);
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }
    return true;
  }

  int _notificationId(String alarmId) => alarmId.hashCode.abs() % 100000;

  NotificationDetails _notificationDetails(TripAlarm alarm) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        styleInformation: BigTextStyleInformation(
          'Kävelyn alkuun on 7 minuuttia!\n'
          '${alarm.stopName != null ? "Pysäkki: ${alarm.stopName}\n" : ""}'
          'Kävely alkaa: klo ${_formatHm(alarm.walkStartTime)}\n'
          'Lähtöaika: klo ${_formatHm(alarm.departureTime)}',
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  /// Ajastaa järjestelmätason tarkan hälytyksen laitteen ilmoituskeskukseen ja lukitusnäytölle.
  Future<void> scheduleAlarm(TripAlarm alarm) async {
    if (!_hasPlatform) return;
    await initialize();

    final id = _notificationId(alarm.id);
    final title = 'HUOMIO: ${alarm.line != null ? "${alarm.line} " : ""}${alarm.destination}';
    final body = 'Lähtö lähestyy! Kävely alkaa klo ${_formatHm(alarm.walkStartTime)} (7 min kuluttua).';

    final details = _notificationDetails(alarm);

    final now = DateTime.now();
    if (alarm.alarmTime.isAfter(now)) {
      try {
        final scheduledDate = tz.TZDateTime.from(alarm.alarmTime, tz.local);
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('Error scheduling exact alarm, falling back to show: $e');
      }
    } else if (alarm.departureTime.isAfter(now)) {
      // Hälytysaika on jo heti käsillä
      try {
        await _plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
        );
      } catch (e) {
        debugPrint('Error showing immediate notification: $e');
      }
    }
  }

  Future<void> cancelAlarm(String alarmId) async {
    if (!_hasPlatform) return;
    try {
      await _plugin.cancel(id: _notificationId(alarmId));
    } catch (e) {
      debugPrint('Error cancelling alarm notification: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_hasPlatform) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }
}
