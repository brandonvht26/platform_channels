import 'package:equatable/equatable.dart';

/// Tipos de actividad detectados
enum ActivityType { stationary, walking, running }

/// Datos del acelerómetro procesados en un "frame" de pasos.
///
/// **Aclaración de arquitectura:** esta entidad pertenece al feature `steps`,
/// NO a `auth`. Ubicarla bajo `auth/domain/entities/` rompe el vertical slicing
/// y mezcla responsabilidades de autenticación con tracking de movimiento.
class StepData extends Equatable {
  final int stepCount;
  final ActivityType activityType;
  final double magnitude;

  const StepData({
    required this.stepCount,
    required this.activityType,
    required this.magnitude,
  });

  /// Calorías estimadas (0.04 cal por paso como aproximación genérica)
  double get estimatedCalories => stepCount * 0.04;

  /// Factory para crear desde Map del Platform Channel
  factory StepData.fromMap(Map<dynamic, dynamic> map) {
    final activityTypeString = map['activityType'] as String;

    return StepData(
      stepCount: map['stepCount'] as int,
      activityType: _parseActivityType(activityTypeString),
      magnitude: (map['magnitude'] as num).toDouble(),
    );
  }

  static ActivityType _parseActivityType(String type) {
    switch (type) {
      case 'walking':
        return ActivityType.walking;
      case 'running':
        return ActivityType.running;
      default:
        return ActivityType.stationary;
    }
  }

  @override
  List<Object> get props => [stepCount, activityType, magnitude];
}
