import 'package:flutter/material.dart';

enum ContactType {
  emergency112,
  metroTramSecurity,
  trainSecurity,
  hslService,
  lostProperty;

  Color get color {
    switch (this) {
      case ContactType.emergency112:
        return const Color(0xFFE53935);
      case ContactType.metroTramSecurity:
        return const Color(0xFFFF6319);
      case ContactType.trainSecurity:
        return const Color(0xFF8C4799);
      case ContactType.hslService:
        return const Color(0xFF007AC9);
      case ContactType.lostProperty:
        return const Color(0xFF43A047);
    }
  }

  IconData get icon {
    switch (this) {
      case ContactType.emergency112:
        return Icons.local_hospital_rounded;
      case ContactType.metroTramSecurity:
        return Icons.security_rounded;
      case ContactType.trainSecurity:
        return Icons.shield_rounded;
      case ContactType.hslService:
        return Icons.support_agent_rounded;
      case ContactType.lostProperty:
        return Icons.find_in_page_rounded;
    }
  }
}

class SafetyContact {
  final String id;
  final String title;
  final String subtitle;
  final String phoneNumber;
  final String description;
  final ContactType type;
  final String operatingHours;
  final bool isEmergency;

  const SafetyContact({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.phoneNumber,
    required this.description,
    required this.type,
    required this.operatingHours,
    this.isEmergency = false,
  });
}
