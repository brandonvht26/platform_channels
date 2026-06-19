import 'dart:async';
import 'package:flutter/material.dart' hide Route;
import '../../data/datasources/gps_datasource.dart';
import '../../domain/entities/location_point.dart';

// ============================================================================
// PALETA "BURBUJAS — MARINO CARIBE" (consistente con StepCounterWidget)
// ============================================================================
const _cyanPrimary = Color(0xFF26C6DA);
const _greenAccent = Color(0xFF66BB6A);
const _coralWarm = Color(0xFFFF8A65);
const _dangerSoft = Color(0xFFEF5350);
const _surfaceTint = Color(0xFFE0F7FA);
const _onSurfaceDark = Color(0xFF006064);

// ============================================================================
// RouteMapWidget — visualización premium de ruta GPS
// ============================================================================
class RouteMapWidget extends StatefulWidget {
  const RouteMapWidget({super.key});

  @override
  State<RouteMapWidget> createState() => _RouteMapWidgetState();
}

class _RouteMapWidgetState extends State<RouteMapWidget> {
  final GpsDataSource _dataSource = GpsDataSourceImpl();
  final Route _route = Route();

  StreamSubscription<LocationPoint>? _subscription;
  bool _isTracking = false;
  String _statusMessage = 'Presiona Iniciar';

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      _stopTracking();
    } else {
      await _startTracking();
    }
  }

  Future<void> _startTracking() async {
    final hasPermission = await _dataSource.requestPermissions();
    if (!hasPermission) {
      if (mounted) setState(() => _statusMessage = 'Permisos denegados');
      return;
    }

    final gpsEnabled = await _dataSource.isGpsEnabled();
    if (!gpsEnabled) {
      if (mounted) setState(() => _statusMessage = 'Activa el GPS');
      return;
    }

    _subscription = _dataSource.locationStream.listen(
      (point) {
        if (!mounted) return;

        final shouldAdd = _route.points.isEmpty ||
            _route.points.last.distanceTo(point) >= 1.0; // 1 metro equilibrado

        if (shouldAdd) {
          setState(() {
            _route.addPoint(point);
            _statusMessage = 'Tracking \u2022 ${_route.points.length} pts';
          });
        }
      },
      onError: (error) {
        if (mounted) setState(() => _statusMessage = 'Error: $error');
      },
    );

    if (mounted) setState(() => _isTracking = true);
  }

  void _stopTracking() {
    _subscription?.cancel();
    _route.finish();
    if (mounted) {
      setState(() {
        _isTracking = false;
        _statusMessage = 'Ruta finalizada';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: _cyanPrimary.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      color: _surfaceTint.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                  'Ruta GPS',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _onSurfaceDark.withValues(alpha: 0.85),
                  ),
                ),
                _BubbleToggleButton(
                  isActive: _isTracking,
                  onTap: _toggleTracking,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: _isTracking
                      ? _greenAccent
                      : _onSurfaceDark.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ----------------------------------------------------------------
            // MINI-MAPA: ruta dibujada con CustomPainter
            // ----------------------------------------------------------------
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: _cyanPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _cyanPrimary.withValues(alpha: 0.15),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _cyanPrimary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CustomPaint(
                  painter: _RoutePainter(route: _route),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ----------------------------------------------------------------
            // MÉTRICAS: burbujas flotantes con íconos premium
            // ----------------------------------------------------------------
            _MetricsBar(route: _route),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _BubbleToggleButton — botón iniciar/detener estilo burbuja marino
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
    final icon =
        isActive ? Icons.stop_rounded : Icons.play_arrow_rounded;
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
// _MetricsBar — barra de 4 métricas con efecto "burbuja flotante"
// ============================================================================
class _MetricsBar extends StatelessWidget {
  final Route route;

  const _MetricsBar({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _cyanPrimary.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: _cyanPrimary.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MetricTile(
            icon: Icons.route_rounded,
            value: '${route.distanceKm.toStringAsFixed(2)} km',
            label: 'Distancia',
            color: _cyanPrimary,
          ),
          _MetricTile(
            icon: Icons.timer_outlined,
            value: _formatDuration(route.duration),
            label: 'Tiempo',
            color: _onSurfaceDark,
          ),
          _MetricTile(
            icon: Icons.speed_rounded,
            value: '${route.averageSpeed.toStringAsFixed(1)} km/h',
            label: 'Velocidad',
            color: _greenAccent,
          ),
          _MetricTile(
            icon: Icons.local_fire_department_rounded,
            value: route.estimatedCalories.toStringAsFixed(0),
            label: 'Calorías',
            color: _coralWarm,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// _MetricTile — una métrica individual con ícono + valor + etiqueta
// ============================================================================
class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _onSurfaceDark,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: _onSurfaceDark.withValues(alpha: 0.50),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// _RoutePainter — pinta la ruta GPS como una línea celeste con glow
// ============================================================================
class _RoutePainter extends CustomPainter {
  final Route route;

  _RoutePainter({required this.route});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.points.isEmpty) return;

    // Calcular bounding box
    double minLat = route.points.first.latitude;
    double maxLat = minLat;
    double minLon = route.points.first.longitude;
    double maxLon = minLon;

    for (final point in route.points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    const padding = 24.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;

    Offset toPixel(LocationPoint point) {
      final latRange = maxLat - minLat;
      final lonRange = maxLon - minLon;
      final x = lonRange == 0
          ? drawWidth / 2
          : ((point.longitude - minLon) / lonRange) * drawWidth;
      final y = latRange == 0
          ? drawHeight / 2
          : ((maxLat - point.latitude) / latRange) * drawHeight;
      return Offset(x + padding, y + padding);
    }

    // Construir path
    final path = Path();
    final firstPixel = toPixel(route.points.first);
    path.moveTo(firstPixel.dx, firstPixel.dy);
    for (int i = 1; i < route.points.length; i++) {
      final pixel = toPixel(route.points[i]);
      path.lineTo(pixel.dx, pixel.dy);
    }

    // Capa 1: glow (trazo ancho semitransparente)
    final glowPaint = Paint()
      ..color = _cyanPrimary.withValues(alpha: 0.18)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(path, glowPaint);

    // Capa 2: trazo principal (celeste vibrante)
    final linePaint = Paint()
      ..color = _cyanPrimary
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Capa 3: punto de inicio (círculo pulsante)
    if (route.points.isNotEmpty) {
      final startPixel = toPixel(route.points.first);
      canvas.drawCircle(
        startPixel,
        6,
        Paint()..color = _greenAccent,
      );
      canvas.drawCircle(
        startPixel,
        10,
        Paint()
          ..color = _greenAccent.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.route.points.length != route.points.length;
}
