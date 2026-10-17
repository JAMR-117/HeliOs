import 'package:flutter/material.dart';

/// Paleta de colores oficial de HeliOs basada en la guía de diseño:
/// - Palladian: #EEE9DF
/// - Oatmeal: #C9C1B1
/// - Burning Flame: #FFB162
/// - Truffle Trouble: #A35139
/// - Blue Fantastic: #2C3B4D
/// - Abyssal Anchorfish Blue: #1B2632
class HeliosTheme {
  // Colores Base
  static const Color palladian = Color(0xFFEEE9DF);
  static const Color oatmeal = Color(0xFFC9C1B1);
  static const Color burningFlame = Color(0xFFFFB162);
  static const Color truffleTrouble = Color(0xFFA35139);
  static const Color blueFantastic = Color(0xFF2C3B4D);
  static const Color abyssalAnchorfishBlue = Color(0xFF1B2632);

  // -------------------------------------------------------------
  // DEGRADADOS MODO DÍA
  // -------------------------------------------------------------
  /// Fondo Día: Palladian en la parte superior con transición a Oatmeal
  /// y difusión cálida de Burning Flame en la base izquierda.
  static const LinearGradient dayBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.45, 0.8, 1.0],
    colors: [
      Color(0xFFF7F4EE), // Palladian claro
      Color(0xFFEEE9DF), // Palladian puro
      Color(0xFFDFD7C7), // Mezcla con Oatmeal
      Color(0xFFF5CFAB), // Resplandor cálido de Burning Flame
    ],
  );

  /// Degradado de cabecera en Día
  static const LinearGradient dayHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      truffleTrouble,
      burningFlame,
    ],
  );

  // -------------------------------------------------------------
  // DEGRADADOS MODO NOCHE
  // -------------------------------------------------------------
  /// Fondo Noche: Abyssal Anchorfish Blue en la zona superior
  /// combinando con Blue Fantastic y resplandor atmosférico cálido
  /// inferior de Truffle Trouble y Burning Flame.
  static const LinearGradient nightBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomLeft,
    stops: [0.0, 0.45, 0.8, 1.0],
    colors: [
      Color(0xFF1B2632), // Abyssal Anchorfish Blue
      Color(0xFF243344), // Transición a Blue Fantastic
      Color(0xFF3F3235), // Difusión atmosférica con Truffle
      Color(0xFF5D392B), // Bruma solar cálida nocturna
    ],
  );

  /// Degradado de cabecera en Noche
  static const LinearGradient nightHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1B2632),
      Color(0xFF2C3B4D),
    ],
  );

  /// Degradado solar de acento (Burning Flame a Truffle Trouble)
  static const LinearGradient solarAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      burningFlame,
      truffleTrouble,
    ],
  );

  /// Degradado para tarjetas destacadas en noche
  static const LinearGradient nightCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2C3B4D), // Blue Fantastic
      Color(0xFF22303F), // Abyssal suave
    ],
  );

  /// Degradado para tarjetas destacadas en día
  static const LinearGradient dayCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFFFBF9F5),
    ],
  );
}
