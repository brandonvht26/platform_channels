import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/services/activity_tracker_service.dart';
import '../../../../core/services/tts_service.dart';

// ============================================================================
// PALETA "BURBUJAS — MARINO CARIBE"
// ============================================================================
const _cyanPrimary = Color(0xFF26C6DA);
const _greenAccent = Color(0xFF66BB6A);
const _dangerSoft = Color(0xFFEF5350);
const _surfaceTint = Color(0xFFE0F7FA);
const _onSurfaceDark = Color(0xFF006064);

// ============================================================================
// MegaRetoWidget — panel de entrenamiento con detección de actividad y caídas
// ============================================================================
class MegaRetoWidget extends StatefulWidget {
  const MegaRetoWidget({super.key});

  @override
  State<MegaRetoWidget> createState() => _MegaRetoWidgetState();
}

class _MegaRetoWidgetState extends State<MegaRetoWidget> {
  // --- Servicios ---
  final TtsService _tts = TtsService();
  late final ActivityTrackerService _tracker = ActivityTrackerService(tts: _tts);

  // --- Estado ---
  bool _isTracking = false;
  ActivityState _activityState = ActivityState.still;
  double _currentMagnitude = 0.0;

  // --- Suscripciones ---
  StreamSubscription<ActivityState>? _activitySub;
  StreamSubscription<void>? _fallSub;
  StreamSubscription<double>? _magnitudeSub;

  @override
  void dispose() {
    _activitySub?.cancel();
    _fallSub?.cancel();
    _magnitudeSub?.cancel();
    _tracker.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // CONTROL DE SESIÓN
  // --------------------------------------------------------------------------
  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await _stopTracking();
    } else {
      await _startTracking();
    }
  }

  Future<void> _startTracking() async {
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nota: Permisos sin confirmar por el OS, pero forzando inicio del sensor.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Eliminamos el 'return;' para NO bloquear la ejecución.
      // El acelerómetro crudo (sensors_plus) funciona en la mayoría de
      // dispositivos sin necesidad del permiso explícito en runtime.
    }

    await _tracker.startTracking();

    _activitySub = _tracker.activityState.listen((state) {
      if (mounted) setState(() => _activityState = state);
    });

    _magnitudeSub = _tracker.currentMagnitude.listen((mag) {
      if (mounted) setState(() => _currentMagnitude = mag);
    });

    _fallSub = _tracker.fallDetected.listen((_) {
      // Evento de caída — no usa setState para actividad,
      // usa showDialog directamente (overlay, no depende del árbol)
      if (mounted) _showFallDialog();
    });

    if (mounted) setState(() => _isTracking = true);
  }

  Future<void> _stopTracking() async {
    await _tracker.stopTracking();
    _activitySub?.cancel();
    _fallSub?.cancel();
    _magnitudeSub?.cancel();
    _activitySub = null;
    _fallSub = null;
    _magnitudeSub = null;
    if (mounted) {
      setState(() {
        _isTracking = false;
        _activityState = ActivityState.still;
        _currentMagnitude = 0.0;
      });
    }
  }

  // --------------------------------------------------------------------------
  // PROTOCOLO DE CAÍDA
  // --------------------------------------------------------------------------
  void _showFallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FallAlertDialog(
        onUserResponded: () {
          // El usuario confirmó "Estoy bien" — volver a la normalidad
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Nos alegra que estés bien'),
                backgroundColor: _greenAccent,
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: _cyanPrimary.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      color: _surfaceTint.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Header: título + botón ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Modo Entrenamiento',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _onSurfaceDark.withValues(alpha: 0.85),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.volume_up, size: 20, color: Colors.blue),
                      onPressed: () async {
                        await _tracker.tts.initialize();
                        final result = await _tracker.tts.speakWelcome();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('TTS Result: $result')),
                          );
                        }
                      },
                    ),
                  ],
                ),
                _BubbleToggleButton(
                  isActive: _isTracking,
                  onTap: _toggleTracking,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // --- Indicador visual de actividad ---
            _ActivityIndicator(
              state: _activityState,
              isTracking: _isTracking,
              magnitude: _currentMagnitude,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _BubbleToggleButton — iniciar/detener modo entrenamiento
// ============================================================================
class _BubbleToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _BubbleToggleButton({
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive ? _dangerSoft : _greenAccent;
    final icon = isActive ? Icons.stop_rounded : Icons.fitness_center_rounded;
    final label = isActive ? 'Detener' : 'Iniciar';

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(30),
      elevation: 1,
      shadowColor: bgColor.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        splashColor: Colors.white.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// _ActivityIndicator — refleja visualmente el estado actual del usuario
// ============================================================================
class _ActivityIndicator extends StatelessWidget {
  final ActivityState state;
  final bool isTracking;
  final double magnitude;

  const _ActivityIndicator({
    required this.state,
    required this.isTracking,
    required this.magnitude,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTracking) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: _cyanPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Icon(Icons.fitness_center_rounded,
                size: 48, color: _onSurfaceDark.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Text(
              'Presiona Iniciar para comenzar',
              style: TextStyle(
                color: _onSurfaceDark.withValues(alpha: 0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final config = _activityConfig(state);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: config.color.withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Círculo pulsante con ícono
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.9, end: 1.05),
            duration: config.pulseDuration,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            onEnd: () {
              // Forzar rebuild para loop de animación
              if (isTracking) {
                (context as Element).markNeedsBuild();
              }
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: config.color.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(config.icon, size: 36, color: config.color),
            ),
          ),
          const SizedBox(height: 14),

          // Etiqueta de estado
          Text(
            config.label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: config.color,
            ),
          ),
          const SizedBox(height: 4),

          // Magnitud actual
          Text(
            '${magnitude.toStringAsFixed(1)} m/s²',
            style: TextStyle(
              fontSize: 13,
              color: _onSurfaceDark.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Configuración visual por estado de actividad.
_ActivityVisualConfig _activityConfig(ActivityState state) {
  return switch (state) {
    ActivityState.still => const _ActivityVisualConfig(
        color: _onSurfaceDark,
        icon: Icons.accessibility_new_rounded,
        label: 'Quieto',
        pulseDuration: Duration(milliseconds: 2000),
      ),
    ActivityState.walking => const _ActivityVisualConfig(
        color: _cyanPrimary,
        icon: Icons.directions_walk_rounded,
        label: 'Caminando',
        pulseDuration: Duration(milliseconds: 900),
      ),
    ActivityState.running => const _ActivityVisualConfig(
        color: _greenAccent,
        icon: Icons.directions_run_rounded,
        label: 'Corriendo',
        pulseDuration: Duration(milliseconds: 500),
      ),
  };
}

class _ActivityVisualConfig {
  final Color color;
  final IconData icon;
  final String label;
  final Duration pulseDuration;

  const _ActivityVisualConfig({
    required this.color,
    required this.icon,
    required this.label,
    required this.pulseDuration,
  });
}

// ============================================================================
// _FallAlertDialog — diálogo de emergencia con timer de 15 segundos
//
//   Protocolo de seguridad:
//   1. Al abrirse, muestra mensaje de verificación y botón "Estoy bien".
//   2. Inicia un Timer de 15 segundos.
//   3. Si el usuario presiona "Estoy bien" → cancela timer, cierra diálogo.
//   4. Si el timer expira sin respuesta → cambia a mensaje de refuerzo
//      con alerta máxima parpadeante.
// ============================================================================
class _FallAlertDialog extends StatefulWidget {
  final VoidCallback onUserResponded;

  const _FallAlertDialog({required this.onUserResponded});

  @override
  State<_FallAlertDialog> createState() => _FallAlertDialogState();
}

class _FallAlertDialogState extends State<_FallAlertDialog>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _remainingSeconds = 15;
  bool _timerExpired = false;

  // Animación de parpadeo para el estado urgente
  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _blinkAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    _blinkController.repeat(reverse: true);

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          timer.cancel();
          _timerExpired = true;
        }
      });
    });
  }

  void _onUserOk() {
    _timer?.cancel();
    _timer = null;
    widget.onUserResponded();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: _timerExpired
          ? const Color(0xFFFFF5F5) // fondo rojo muy claro en estado urgente
          : Colors.white,
      title: _timerExpired ? _buildUrgentTitle() : _buildNormalTitle(),
      content: _timerExpired ? _buildUrgentContent() : _buildNormalContent(),
      actions: _timerExpired
          ? <Widget>[_buildUrgentActions()]
          : <Widget>[_buildNormalActions()],
    );
  }

  // ----- Estado normal: verificación inicial -----
  Widget _buildNormalTitle() {
    return const Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: _dangerSoft, size: 28),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '¿Estás bien?',
            style: TextStyle(
              color: _onSurfaceDark,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hemos detectado una caída fuerte.',
          style: TextStyle(fontSize: 15, color: _onSurfaceDark),
        ),
        const SizedBox(height: 14),
        // Barra de tiempo restante
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _remainingSeconds / 15.0,
            backgroundColor: _dangerSoft.withValues(alpha: 0.12),
            valueColor: const AlwaysStoppedAnimation(_dangerSoft),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Alerta en $_remainingSeconds s',
          style: TextStyle(
            fontSize: 12,
            color: _dangerSoft.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalActions() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _onUserOk,
        icon: const Icon(Icons.check_circle_outline, size: 20),
        label: const Text('Estoy bien'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _greenAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ----- Estado urgente: timer expirado, sin respuesta -----
  Widget _buildUrgentTitle() {
    return FadeTransition(
      opacity: _blinkAnimation,
      child: const Row(
        children: [
          Icon(Icons.emergency_rounded, color: _dangerSoft, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '¡ATENCIÓN!',
              style: TextStyle(
                color: _dangerSoft,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgentContent() {
    return const Text(
      'No hay respuesta.\n¿Requiere asistencia médica?',
      style: TextStyle(
        fontSize: 15,
        color: _onSurfaceDark,
        height: 1.5,
      ),
    );
  }

  Widget _buildUrgentActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: _onUserOk,
          style: TextButton.styleFrom(
            foregroundColor: _greenAccent,
          ),
          child: const Text('Estoy bien'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            // TODO (siguiente fase): disparar llamada a emergencias
            _timer?.cancel();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.phone, size: 18),
          label: const Text('Llamar ayuda'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _dangerSoft,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ],
    );
  }
}
