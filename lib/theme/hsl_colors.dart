import 'package:flutter/material.dart';

/// Official and curated HSL (Helsinki Regional Transport) design tokens.
class HslColors {
  // Brand colors
  static const Color primaryBlue = Color(0xFF007AC9);
  static const Color darkBlue = Color(0xFF005A96);
  static const Color lightBlue = Color(0xFFE5F3FD);
  static const Color navyBackground = Color(0xFF0A192F);

  // Transit Modes Colors
  static const Color metroOrange = Color(0xFFFF6319);
  static const Color tramGreen = Color(0xFF00985F);
  static const Color trainPurple = Color(0xFF8C4799);
  static const Color busBlue = Color(0xFF007AC9);
  static const Color trunkBusOrange = Color(0xFFFD4F00); // Runkolinja (500, 510, 550...)
  static const Color ferryCyan = Color(0xFF00B9E4);
  static const Color walkGray = Color(0xFF757575);
  static const Color bikeYellow = Color(0xFFFDCB02);

  // Status & Safety Colors
  static const Color safetyRed = Color(0xFFE53935);
  static const Color warningAmber = Color(0xFFFFB300);
  static const Color successGreen = Color(0xFF43A047);
  static const Color infoBlue = Color(0xFF1E88E5);

  // Surface & Neutral Colors
  static const Color cardDark = Color(0xFF162238);
  static const Color cardDarkElevated = Color(0xFF1F2F4A);
  static const Color backgroundLight = Color(0xFFD8C8AC); // Tummempi lämmin beige taustapohja
  static const Color surfaceLight = Color(0xFFE5D7BF); // Selkeä beige taustaväri korteille ja pinnoille
  static const Color surfaceContainerLight = Color(0xFFCBB899); // Tummempi beige syötekentille ja valinnoille
  static const Color borderLight = Color(0xFFB8A382); // Lämmin beigenruskea reunusväri
  static const Color onSurfaceLight = Color(0xFF231D15); // Tumma lämmin tekstiväri beigen päällä
  static const Color dividerDark = Color(0xFF26354D);
}
