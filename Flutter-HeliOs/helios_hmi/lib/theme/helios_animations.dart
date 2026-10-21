import 'dart:async';
import 'package:flutter/material.dart';

/// Transición de página ultra-fluida con desaceleración cúbica (easeOutCubic),
/// combinando desvanecimiento (fade), escala sutil (0.96 -> 1.0) y desplazamiento suave.
class HeliosPageTransitionsBuilder extends PageTransitionsBuilder {
  const HeliosPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation);
    final scaleIn = Tween<double>(begin: 0.96, end: 1.0).animate(curvedAnimation);
    final slideIn = Tween<Offset>(
      begin: const Offset(0.035, 0.0),
      end: Offset.zero,
    ).animate(curvedAnimation);

    // Atenuación suave de la pantalla saliente para efecto de profundidad
    final fadeOut = Tween<double>(begin: 1.0, end: 0.88).animate(secondaryCurved);
    final scaleOut = Tween<double>(begin: 1.0, end: 0.98).animate(secondaryCurved);

    return FadeTransition(
      opacity: fadeOut,
      child: ScaleTransition(
        scale: scaleOut,
        child: FadeTransition(
          opacity: fadeIn,
          child: SlideTransition(
            position: slideIn,
            child: ScaleTransition(
              scale: scaleIn,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper para crear un PageRoute personalizado con duración y curva calibradas
PageRoute<T> smoothPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final secondaryCurved = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation);
      final scaleIn = Tween<double>(begin: 0.96, end: 1.0).animate(curvedAnimation);
      final slideIn = Tween<Offset>(
        begin: const Offset(0.035, 0.0),
        end: Offset.zero,
      ).animate(curvedAnimation);

      final fadeOut = Tween<double>(begin: 1.0, end: 0.88).animate(secondaryCurved);
      final scaleOut = Tween<double>(begin: 1.0, end: 0.98).animate(secondaryCurved);

      return FadeTransition(
        opacity: fadeOut,
        child: ScaleTransition(
          scale: scaleOut,
          child: FadeTransition(
            opacity: fadeIn,
            child: SlideTransition(
              position: slideIn,
              child: ScaleTransition(
                scale: scaleIn,
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Widget que anima los cambios de texto o métrica de forma deslizante y suave
class AnimatedMetricText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  const AnimatedMetricText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.0, 0.25),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(text),
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Envoltorio interactivo que aplica microanimación de escala y elevación al pasar el ratón o tocar
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 1.018,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double targetScale = _isPressed
        ? 0.985
        : (_isHovered ? widget.scaleFactor : 1.0);

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: targetScale,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Widget de latido o pulso suave (breathing glow) para indicadores y alarmas
class PulsingGlow extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minOpacity;
  final double maxOpacity;

  const PulsingGlow({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1800),
    this.minOpacity = 0.65,
    this.maxOpacity = 1.0,
  });

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: widget.minOpacity, end: widget.maxOpacity).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}

/// Entrada escalonada con desvanecimiento y deslizamiento vertical
class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDelay = const Duration(milliseconds: 40),
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slide = Tween<Offset>(begin: const Offset(0.0, 0.12), end: Offset.zero).animate(curved);

    final delay = widget.baseDelay * widget.index;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
