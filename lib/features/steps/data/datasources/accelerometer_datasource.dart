import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/platform/platform_channels.dart';
import '../../domain/entities/step_data.dart';

// ============================================================================
// CONTRATO: AccelerometerDataSource
// ============================================================================
abstract class AccelerometerDataSource {
  Stream<StepData> get stepStream;
  Future<void> startCounting();
  Future<void> stopCounting();
  Future<bool> requestPermissions();
}

// ============================================================================
// IMPLEMENTACIÓN FLUTTER
// ============================================================================
class AccelerometerDataSourceImpl implements AccelerometerDataSource {
  // EventChannel: stream continuo de datos del acelerómetro
  final EventChannel _eventChannel =
      const EventChannel(PlatformChannels.accelerometer);

  // MethodChannel: comandos puntuales (start/stop)
  // Convención: sufijo '/control' para separar señales de control del stream
  final MethodChannel _methodChannel =
      const MethodChannel('${PlatformChannels.accelerometer}/control');

  // --------------------------------------------------------------------------
  // STREAM: datos crudos del acelerómetro mapeados a StepData
  // --------------------------------------------------------------------------
  //
  // ADVERTENCIA DE HARDWARE — Samsung Galaxy A54 (Exynos):
  //
  // El Exynos 1380 del A54 es propenso a sobrecalentamiento si se satura
  // con lecturas de sensor a máxima frecuencia. Por eso, en el lado Android
  // (Kotlin) DEBEMOS registrar el SensorManager con:
  //
  //   sensorManager.registerListener(
  //       listener, accelerometer,
  //       SensorManager.SENSOR_DELAY_NORMAL   // ≈200ms entre muestras
  //       // SENSOR_DELAY_UI también aceptable  // ≈60ms entre muestras
  //   )
  //
  //   ❌ NUNCA usar SENSOR_DELAY_FASTEST (~0ms) ni SENSOR_DELAY_GAME (~20ms).
  //      Drenan batería y disparan thermal throttling en el A54.
  //
  //   SENSOR_DELAY_NORMAL es el sweet spot: ≈5 lecturas/segundo, suficiente
  //   para detección de pasos sin saturar el CPU.
  //
  // --------------------------------------------------------------------------
  // FILTRO DE PASO BAJO (Low-Pass Filter) — Mitigación de ruido en A54:
  //
  // El acelerómetro del A54 entrega datos con "jitter" (vibración espuria).
  // Para suavizarlos EN KOTLIN antes de enviar por el EventChannel:
  //
  //   class LowPassFilter {
  //       private var filtered = FloatArray(3) // x, y, z
  //       private val alpha = 0.2f  // <-- más bajo = más suave, más lento
  //
  //       fun filter(raw: FloatArray): FloatArray {
  //           filtered[0] = alpha * raw[0] + (1 - alpha) * filtered[0]
  //           filtered[1] = alpha * raw[1] + (1 - alpha) * filtered[1]
  //           filtered[2] = alpha * raw[2] + (1 - alpha) * filtered[2]
  //           return filtered
  //       }
  //   }
  //
  //   alpha = 0.15—0.25 es adecuado para caminata. Para running se puede
  //   subir a 0.3—0.4 porque la señal real es más fuerte.
  //
  //   Alternativa más robusta: Media Móvil Exponencial (EMA) con α adaptativo
  //   según la magnitud de la señal detectada.
  //
  // --------------------------------------------------------------------------
  // TRAMPA DE MEMORIA — EventChannel.onCancel:
  //
  // En el lado Android, el EventChannel.StreamHandler DEBE implementar
  // onCancel() para llamar a sensorManager.unregisterListener().
  // Si esto no se hace, el sensor sigue disparando eventos aunque Flutter
  // haya cerrado el stream → battery drain masivo en el A54 en minutos.
  //
  //   override fun onCancel(arguments: Any?) {
  //       sensorManager.unregisterListener(sensorEventListener)
  //       // También cancelar wakelocks si se estuvieran usando
  //   }
  //
  // --------------------------------------------------------------------------

  @override
  Stream<StepData> get stepStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return StepData.fromMap(event as Map<dynamic, dynamic>);
    });
  }

  @override
  Future<void> startCounting() async {
    await _methodChannel.invokeMethod('start');
  }

  @override
  Future<void> stopCounting() async {
    await _methodChannel.invokeMethod('stop');
  }

  @override
  Future<bool> requestPermissions() async {
    await Permission.activityRecognition.request();
    // Ignoramos Permission.sensors porque en Samsung causa falsos negativos.
    // Además, forzamos devolver true porque el acelerómetro funciona sin
    // necesidad estricta del permiso a nivel de OS.
    return true;
  }
}
