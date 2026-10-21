import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/helios_animations.dart';
import '../../theme/helios_theme.dart';
import '../../theme/weather_palette.dart';

/// Barra de navegación inferior moderna con estilo Glassmorphism,
/// soporte de badges dinámicos de alarmas y microanimaciones táctiles.
class HeliosGlassBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool hasActiveAlarm;
  final int activeAlarmCode;
  final WeatherPalette palette;
  final bool isNight;

  const HeliosGlassBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.hasActiveAlarm = false,
    this.activeAlarmCode = 0,
    required this.palette,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomInset > 0 ? bottomInset + 4 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isNight ? 0.40 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          if (hasActiveAlarm)
            BoxShadow(
              color: HeliosTheme.truffleTrouble.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isNight
                  ? const Color(0xFF0F172A).withValues(alpha: 0.82)
                  : palette.cardColor.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasActiveAlarm && currentIndex != 1
                    ? HeliosTheme.truffleTrouble.withValues(alpha: 0.35)
                    : palette.cardBorderColor.withValues(alpha: 0.70),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.solar_power_rounded,
                  activeIcon: Icons.solar_power_rounded,
                  label: 'Monitoreo',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.warning_amber_rounded,
                  activeIcon: Icons.warning_rounded,
                  label: 'Bitácora SCADA',
                  showBadge: hasActiveAlarm,
                  badgeText: activeAlarmCode != 0 ? '$activeAlarmCode' : '!',
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.tune_rounded,
                  activeIcon: Icons.tune_rounded,
                  label: 'Configuración',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    bool showBadge = false,
    String? badgeText,
  }) {
    final bool isSelected = currentIndex == index;
    final Color activeColor = palette.accentSolar;
    final Color inactiveColor = palette.textMuted;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.35)
                      : Colors.transparent,
                  width: 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedScale(
                        scale: isSelected ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          isSelected ? activeIcon : icon,
                          color: isSelected ? activeColor : inactiveColor,
                          size: 22,
                        ),
                      ),
                      if (showBadge)
                        Positioned(
                          top: -4,
                          right: -10,
                          child: PulsingGlow(
                            duration: const Duration(milliseconds: 900),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: Text(
                                badgeText ?? '!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: isSelected ? activeColor : inactiveColor,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
