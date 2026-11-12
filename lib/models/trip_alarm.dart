import '../models/transit_mode.dart';

/// Käyttäjän asettama reitti- tai pysäkkihälytys.
/// Hälytys laukeaa valitun ennakkoajan (oletus 7 min, min 2 min, max 30 min) ennen kävelyn alkamista.
class TripAlarm {
  final String id;
  final String title;
  final String? line;
  final TransitMode mode;
  final String destination;
  final String? stopName;
  final DateTime departureTime;
  final DateTime walkStartTime;
  final DateTime alarmTime;
  final String source; // 'planner' tai 'nearby'
  final int leadMinutes;
  bool isTriggered;

  TripAlarm({
    required this.id,
    required this.title,
    this.line,
    required this.mode,
    required this.destination,
    this.stopName,
    required this.departureTime,
    required this.walkStartTime,
    required this.alarmTime,
    required this.source,
    this.leadMinutes = 7,
    this.isTriggered = false,
  });

  bool get isExpired => DateTime.now().isAfter(departureTime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'line': line,
        'mode': mode.name,
        'destination': destination,
        'stopName': stopName,
        'departureTime': departureTime.toIso8601String(),
        'walkStartTime': walkStartTime.toIso8601String(),
        'alarmTime': alarmTime.toIso8601String(),
        'source': source,
        'leadMinutes': leadMinutes,
        'isTriggered': isTriggered,
      };

  factory TripAlarm.fromJson(Map<String, dynamic> json) {
    TransitMode parsedMode = TransitMode.bus;
    try {
      final modeStr = json['mode'] as String?;
      if (modeStr != null) {
        parsedMode = TransitMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => TransitMode.fromGtfs(modeStr),
        );
      }
    } catch (_) {}

    final walkStartTime = DateTime.parse(json['walkStartTime'] as String).toLocal();
    final alarmTime = DateTime.parse(json['alarmTime'] as String).toLocal();
    final rawLead = json['leadMinutes'] as int?;
    final int lead = rawLead ??
        walkStartTime.difference(alarmTime).inMinutes.clamp(2, 30);

    return TripAlarm(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      line: json['line'] as String?,
      mode: parsedMode,
      destination: json['destination'] as String? ?? '',
      stopName: json['stopName'] as String?,
      departureTime: DateTime.parse(json['departureTime'] as String).toLocal(),
      walkStartTime: walkStartTime,
      alarmTime: alarmTime,
      source: json['source'] as String? ?? 'unknown',
      leadMinutes: lead.clamp(2, 30),
      isTriggered: json['isTriggered'] as bool? ?? false,
    );
  }
}

