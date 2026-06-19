import 'dart:math' as math;
import 'package:equatable/equatable.dart';

/// Punto de ubicación GPS recibido del Platform Channel.
///
/// Representa una lectura individual del sensor GPS del dispositivo.
/// En el Galaxy A54, la precisión típica del GPS es de 3-10 metros en
/// exteriores con buena visibilidad de satélites.
class LocationPoint extends Equatable {
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed; // m/s
  final double accuracy; // metros (radio de confianza del 68%)
  final DateTime timestamp;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.speed = 0,
    this.accuracy = 0,
    required this.timestamp,
  });

  /// Factory desde el Map que envía Android por el EventChannel.
  ///
  ///   TODO: El lado Android debería enviar el timestamp real del GPS
  ///   (location.time) en lugar de usar DateTime.now() aquí. El timestamp
  ///   nativo es esencial para calcular velocidad y ritmo con precisión.
  factory LocationPoint.fromMap(Map<dynamic, dynamic> map) {
    return LocationPoint(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.now(),
    );
  }

  /// Distancia en metros a otro punto usando la fórmula de Haversine.
  ///
  ///   Fórmula:  a = sin²(Δφ/2) + cos(φ1)·cos(φ2)·sin²(Δλ/2)
  ///             c = 2·atan2(√a, √(1−a))
  ///             d = R·c
  ///
  ///   donde R = 6,371,000 m (radio medio terrestre WGS-84).
  ///
  ///   Precisión: ~0.3% de error para distancias cortas (<100 km), adecuado
  ///   para tracking de running/caminata.
  double distanceTo(LocationPoint other) {
    const earthRadius = 6371000.0;

    final lat1Rad = latitude * math.pi / 180;
    final lat2Rad = other.latitude * math.pi / 180;
    final deltaLat = (other.latitude - latitude) * math.pi / 180;
    final deltaLon = (other.longitude - longitude) * math.pi / 180;

    // Evitamos calcular sin(delta/2) dos veces
    final sinHalfDLat = math.sin(deltaLat / 2);
    final sinHalfDLon = math.sin(deltaLon / 2);

    final a = sinHalfDLat * sinHalfDLat +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
            sinHalfDLon * sinHalfDLon;

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  @override
  List<Object?> get props => [latitude, longitude, timestamp];
}

/// Representa una ruta GPS completa (colección de [LocationPoint]).
///
///   MEJORA PARA PRODUCCIÓN: la distancia total se recalcula cada vez que
///   se accede a [totalDistance]. Para rutas largas (>1000 puntos) conviene
///   cachear incrementalmente: sumar la distancia del nuevo punto al
///   acumulador en [addPoint] en lugar de iterar toda la lista.
class Route {
  final List<LocationPoint> points;
  final DateTime startTime;
  DateTime? endTime;

  Route({
    List<LocationPoint>? points,
    DateTime? startTime,
  })  : points = points ?? [],
        startTime = startTime ?? DateTime.now();

  void addPoint(LocationPoint point) {
    points.add(point);
  }

  void finish() {
    endTime = DateTime.now();
  }

  /// Distancia total acumulada en metros (suma de segmentos Haversine).
  double get totalDistance {
    if (points.length < 2) return 0;

    double distance = 0;
    for (int i = 1; i < points.length; i++) {
      distance += points[i - 1].distanceTo(points[i]);
    }
    return distance;
  }

  /// Distancia en kilómetros.
  double get distanceKm => totalDistance / 1000;

  /// Duración total de la ruta.
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// Velocidad media en km/h.
  double get averageSpeed {
    final hours = duration.inSeconds / 3600;
    if (hours == 0) return 0;
    return distanceKm / hours;
  }

  /// Calorías estimadas (≈60 kcal por km, aproximación para running).
  ///
  ///   Valores de referencia:
  ///   - Caminata suave: ~40 kcal/km
  ///   - Running moderado: ~60 kcal/km
  ///   - Running intenso: ~80 kcal/km
  double get estimatedCalories => distanceKm * 60;
}
