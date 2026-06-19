import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/datasources/accelerometer_datasource.dart';
import '../../domain/entities/step_data.dart';

import '../../../../core/services/voice_announcer.dart';

// ============================================================================
// PALETA "BURBUJAS — MARINO CARIBE"
//
//   cyanPrimary   = celeste caribe (contador principal, iconos activos)
//   greenAccent   = verde clarito (botón iniciar, chip caminando)
//   coralWarm     = toque cálido para calorías (contraste sin romper tema)
//   dangerSoft    = rojo suave (botón detener)
//   surfaceTint   = fondo translúcido de chips
//   onSurfaceDark = texto oscuro sobre fondos claros (contraste WCAG AA)
// ============================================================================
const _cyanPrimary = Color(0xFF26C6DA);
const _greenAccent = Color(0xFF66BB6A);
const _coralWarm = Color(0xFFFF8A65);
const _dangerSoft = Color(0xFFEF5350);
const _surfaceTint = Color(0xFFE0F7FA);
const _onSurfaceDark = Color(0xFF006064);

/// Widget que muestra el contador de pasos en tiempo real.
///
/// Se suscribe al [AccelerometerDataSource.stepStream] (EventChannel) y
/// refleja los datos que llegan del lado Android (Kotlin), ya filtrados
/// con el Low-Pass Filter para mitigar el ruido del Galaxy A54.
class StepCounterWidget extends StatefulWidget {
  const StepCounterWidget({super.key});

  @override
  State<StepCounterWidget> createState() => _StepCounterWidgetState();
}

class _StepCounterWidgetState extends State<StepCounterWidget> {
  final AccelerometerDataSource _dataSource = AccelerometerDataSourceImpl();

  StreamSubscription<StepData>? _subscription;
  StepData? _currentData;
  bool _isTracking = false;
  
  // Instancia del manejador de voz
  final VoiceAnnouncer _voiceAnnouncer = VoiceAnnouncer();
  
  // Variable de estado para controlar la alerta de caída
  bool _isFallDialogShowing = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _toggleTracking() {
    if (_isTracking) {
      _stopTracking();
    } else {
      _startTracking();
    }
  }

  void _handleFallDetection() {
    setState(() => _isFallDialogShowing = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
            SizedBox(width: 10),
            Text('¡Caída Detectada!'),
          ],
        ),
        content: const Text(
            'Hemos detectado un impacto brusco seguido de inmovilidad.\n\n'
            '¿Te encuentras bien?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isFallDialogShowing = false);
            },
            child: const Text('ESTOY BIEN', style: TextStyle(color: Colors.green)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isFallDialogShowing = false);
              // Lógica de SOS...
            },
            child: const Text('NECESITO AYUDA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _startTracking() async {
    final hasPermission = await _dataSource.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Permisos de sensores denegados'),
            backgroundColor: _dangerSoft,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await _dataSource.startCounting();
    
    // Inicializar el VoiceAnnouncer al arrancar el tracking
    await _voiceAnnouncer.initialize();

    _subscription = _dataSource.stepStream.listen(
      (data) {
        if (mounted) {
          setState(() => _currentData = data);
          
          // LÓGICA DE VOZ Y CAÍDA EXACTAMENTE COMO SE SOLICITÓ
          if (data.activityType == ActivityType.falling) {
            if (!_isFallDialogShowing) {
              _handleFallDetection();
              _voiceAnnouncer.announceFallEmergency();
            }
          } else if (!_isFallDialogShowing) {
            _voiceAnnouncer.announceActivityChange(data.activityType);
          }
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('Error en sensor: $error'),
              backgroundColor: _dangerSoft,
            ),
          );
        }
      },
    );

    if (mounted) setState(() => _isTracking = true);
  }

  Future<void> _stopTracking() async {
    await _dataSource.stopCounting();
    _subscription?.cancel();
    if (mounted) setState(() => _isTracking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: _cyanPrimary.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      color: _surfaceTint.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ----------------------------------------------------------------
            // HEADER: título + botón iniciar/detener
            // ----------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Contador de Pasos',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _onSurfaceDark.withValues(alpha: 0.85),
                  ),
                ),
                _BubbleButton(
                  onTap: _toggleTracking,
                  isActive: _isTracking,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ----------------------------------------------------------------
            // CONTADOR CENTRAL — número grande estilo burbuja
            // ----------------------------------------------------------------
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Text(
                '${_currentData?.stepCount ?? 0}',
                key: ValueKey(_currentData?.stepCount ?? 0),
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w800,
                  color: _cyanPrimary,
                  height: 1.1,
                ),
              ),
            ),
            Text(
              'pasos',
              style: TextStyle(
                fontSize: 15,
                color: _onSurfaceDark.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 18),

            // ----------------------------------------------------------------
            // CHIPS INFORMATIVOS: actividad + calorías
            // ----------------------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInfoChip(
                  icon: _getActivityIcon(_currentData?.activityType),
                  label: _getActivityLabel(_currentData?.activityType),
                  color: _greenAccent,
                ),
                _buildInfoChip(
                  icon: Icons.local_fire_department,
                  label:
                      '${_currentData?.estimatedCalories.toStringAsFixed(1) ?? "0.0"} cal',
                  color: _coralWarm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Chip tipo burbuja con icono + texto
  // --------------------------------------------------------------------------
  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Helpers de íconos y etiquetas por tipo de actividad
  // --------------------------------------------------------------------------
  IconData _getActivityIcon(ActivityType? type) {
    return switch (type) {
      ActivityType.walking => Icons.directions_walk,
      ActivityType.running => Icons.directions_run,
      ActivityType.stationary => Icons.accessibility_new,
      _ => Icons.help_outline,
    };
  }

  String _getActivityLabel(ActivityType? type) {
    return switch (type) {
      ActivityType.walking => 'Caminando',
      ActivityType.running => 'Corriendo',
      ActivityType.stationary => 'Quieto',
      _ => 'Detectando...',
    };
  }
}

// ============================================================================
// _BubbleButton — botón iniciar/detener con estética de burbuja
// ============================================================================
class _BubbleButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isActive;

  const _BubbleButton({required this.onTap, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive ? _dangerSoft : _greenAccent;
    final icon = isActive ? Icons.stop_rounded : Icons.play_arrow_rounded;
    final label = isActive ? 'Detener' : 'Iniciar';

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(30),
      elevation: 1,
      shadowColor: bgColor.withValues(alpha: 0.4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        splashColor: Colors.white.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: Colors.white),
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
