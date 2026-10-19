import 'package:flutter/material.dart';

class WeatherPalette {
  final String weatherState;
  final bool isNight;
  final Color bgColor;
  final Color cardColor;
  final Color cardBorderColor;
  final Color textPrimary;
  final Color textMuted;
  final Color accentSolar;
  final Color accentSecondary;
  final Color glowColor;
  final double glowAlpha;
  final Color hillBottomColor;

  const WeatherPalette({
    required this.weatherState,
    required this.isNight,
    required this.bgColor,
    required this.cardColor,
    required this.cardBorderColor,
    required this.textPrimary,
    required this.textMuted,
    required this.accentSolar,
    required this.accentSecondary,
    required this.glowColor,
    this.glowAlpha = 0.11,
    required this.hillBottomColor,
  });

  // Estilo unificado para cápsulas / óvalos del Header
  Color get headerCapsuleBg => const Color(0xFFE2E8F0).withValues(alpha: 0.88);
  Color get headerCapsuleBorder => Colors.white.withValues(alpha: 0.60);
  Color get headerCapsuleText => const Color(0xFF0F172A);

  List<BoxShadow> get headerCapsuleShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];

  BoxDecoration get rootDecoration => BoxDecoration(
        color: bgColor,
        gradient: RadialGradient(
          center: Alignment.bottomLeft,
          radius: 0.68,
          colors: [
            glowColor.withValues(alpha: glowAlpha),
            bgColor,
          ],
          stops: const [0.0, 0.45],
        ),
      );

  static WeatherPalette getPalette(String weatherState, bool isNight) {
    if (isNight || weatherState == 'clear_night' || weatherState == 'cloudy_night') {
      return const WeatherPalette(
        weatherState: 'clear_night',
        isNight: true,
        bgColor: Color(0xFF0F172A),
        cardColor: Color(0xFF1E293B),
        cardBorderColor: Color(0xFF334155),
        textPrimary: Color(0xFFF1F5F9),
        textMuted: Color(0xFF94A3B8),
        accentSolar: Color(0xFFF59E0B),
        accentSecondary: Color(0xFF10B981),
        glowColor: Color(0xFFF97316),
        glowAlpha: 0.10,
        hillBottomColor: Color(0xFF0F172A),
      );
    }

    switch (weatherState) {
      case 'sunny':
        return const WeatherPalette(
          weatherState: 'sunny',
          isNight: false,
          bgColor: Color(0xFF13261C),
          cardColor: Color(0xFF1C3528),
          cardBorderColor: Color(0xFF2E5440),
          textPrimary: Color(0xFFF8FAFC),
          textMuted: Color(0xFFA7F3D0),
          accentSolar: Color(0xFFFBBF24),
          accentSecondary: Color(0xFF34D399),
          glowColor: Color(0xFFF97316),
          glowAlpha: 0.11,
          hillBottomColor: Color(0xFF13261C),
        );

      case 'rain':
        return const WeatherPalette(
          weatherState: 'rain',
          isNight: false,
          bgColor: Color(0xFF0F2537),
          cardColor: Color(0xFF17354D),
          cardBorderColor: Color(0xFF255070),
          textPrimary: Color(0xFFF0F9FF),
          textMuted: Color(0xFF93C5FD),
          accentSolar: Color(0xFF38BDF8),
          accentSecondary: Color(0xFF60A5FA),
          glowColor: Color(0xFFF97316),
          glowAlpha: 0.10,
          hillBottomColor: Color(0xFF0F2537),
        );

      case 'storm':
        return const WeatherPalette(
          weatherState: 'storm',
          isNight: false,
          bgColor: Color(0xFF0B1929),
          cardColor: Color(0xFF14273E),
          cardBorderColor: Color(0xFF213F60),
          textPrimary: Color(0xFFF0F9FF),
          textMuted: Color(0xFF93C5FD),
          accentSolar: Color(0xFF38BDF8),
          accentSecondary: Color(0xFFA855F7),
          glowColor: Color(0xFFF97316),
          glowAlpha: 0.11,
          hillBottomColor: Color(0xFF0B1929),
        );

      case 'partly_cloudy':
      case 'cloudy':
      default:
        return const WeatherPalette(
          weatherState: 'cloudy',
          isNight: false,
          bgColor: Color(0xFF1B2634),
          cardColor: Color(0xFF253447),
          cardBorderColor: Color(0xFF374960),
          textPrimary: Color(0xFFF1F5F9),
          textMuted: Color(0xFF94A3B8),
          accentSolar: Color(0xFFFBBF24),
          accentSecondary: Color(0xFF38BDF8),
          glowColor: Color(0xFFF97316),
          glowAlpha: 0.09,
          hillBottomColor: Color(0xFF1B2634),
        );
    }
  }
}
