/// Hälytysten äänityypit / äänilajit.
enum AlarmSoundType {
  siren(
    id: 'siren',
    displayName: 'Voimakas sireeni',
    description: 'Kova kaksitaajuuksinen hälytyssireeni',
    assetPath: 'sounds/siren.wav',
  ),
  digitalClock(
    id: 'digital_clock',
    displayName: 'Digitaalinen herätyskello',
    description: 'Terävä ja tiheä pulssipiippaus',
    assetPath: 'sounds/digital_clock.wav',
  ),
  transitChime(
    id: 'transit_chime',
    displayName: 'Pikajuna & Asemakello',
    description: 'Rautatieaseman ja pikajunan huomiogongi',
    assetPath: 'sounds/transit_chime.wav',
  ),
  emergencyPulse(
    id: 'emergency_pulse',
    displayName: 'Hätäpulssi & Tutka',
    description: 'Korkea nouseva varoitusääni',
    assetPath: 'sounds/emergency_pulse.wav',
  );

  final String id;
  final String displayName;
  final String description;
  final String assetPath;

  const AlarmSoundType({
    required this.id,
    required this.displayName,
    required this.description,
    required this.assetPath,
  });

  static AlarmSoundType fromId(String? id) =>
      AlarmSoundType.values.firstWhere((e) => e.id == id, orElse: () => AlarmSoundType.siren);
}

