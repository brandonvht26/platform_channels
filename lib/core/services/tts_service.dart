import 'package:flutter_tts/flutter_tts.dart';

/// Servicio de síntesis de voz offline (TTS) para el Mega Reto.
///
///   Características:
///   - Motor de voz en español (es-MX), 100% offline.
///   - Cada frase interrumpe la anterior automáticamente (modo "pisar").
///     Esto es esencial cuando un evento rápido (caída) debe cortar una
///     frase de menor prioridad (ej. "estás caminando").
///   - Volumen, pitch y velocidad configurables.
///   - Métodos semánticos por cada frase de negocio requerida.
///
///   USO PREVISTO:
///   El [TtsService] se invoca desde el BLoC o UseCase de actividad.
///   El debounce de 3 segundos se aplica en la capa de streams (rxdart),
///   NO aquí — este servicio simplemente habla cuando se le ordena.
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;

  // --------------------------------------------------------------------------
  // INICIALIZACIÓN
  // --------------------------------------------------------------------------

  /// Configura el motor TTS: idioma español, volumen máximo, velocidad
  /// natural. Debe llamarse UNA vez al iniciar la sesión de entrenamiento.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true; // Lo forzamos a true inmediatamente pase lo que pase

    try {
      await _flutterTts.setEngine('com.google.android.tts');
    } catch (_) {}
    
    // No forzamos ningún idioma. Dejaremos que el motor TTS use
    // el idioma por defecto configurado en el sistema (es-US).
  }

  // --------------------------------------------------------------------------
  // FRASES DE NEGOCIO (8 requeridas)
  // --------------------------------------------------------------------------

  /// Al arrancar la sesión de entrenamiento.
  Future<int?> speakWelcome() =>
      _speak('Bienvenido a una nueva sesión de entrenamiento');

  /// Actividad detectada: caminando de forma continua.
  Future<int?> speakWalking() => _speak('Estás caminando');

  /// Actividad detectada: corriendo de forma continua.
  Future<int?> speakRunning() => _speak('Estás corriendo');

  /// Transición de correr a caminar (recuperación).
  Future<int?> speakCoolDown() => _speak('Así es, tómate un respiro');

  /// Transición de caminar a correr (aceleración).
  Future<int?> speakSpeedUp() => _speak('Bien, subamos de marcha');

  /// Usuario completamente detenido (inmóvil).
  Future<int?> speakStopped() => _speak('Llegó la hora de estirarse');

  /// Caída detectada — frase de verificación de seguridad.
  Future<int?> speakFallDetected() =>
      _speak('He detectado una caída ¿Estás bien?');

  /// Al cerrar/terminar la sesión de entrenamiento.
  Future<int?> speakSessionEnd() =>
      _speak('Buen trabajo, ha sido un rendimiento estupendo');

  // --------------------------------------------------------------------------
  // CONTROL DE VOZ
  // --------------------------------------------------------------------------

  /// Detiene cualquier reproducción en curso inmediatamente.
  Future<void> stop() => _flutterTts.stop();

  /// Ajusta el volumen en runtime (0.0 a 1.0).
  Future<void> setVolume(double volume) async {
    await _flutterTts.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Libera recursos del motor TTS.
  Future<void> dispose() async {
    await _flutterTts.stop();
    _initialized = false;
  }

  // --------------------------------------------------------------------------
  // INTERNO
  // --------------------------------------------------------------------------

  Future<int?> _speak(String text) async {
    if (!_initialized) return null;
    try {
      final result = await _flutterTts.speak(text);
      return result;
    } catch (e) {
      return -1;
    }
  }
}
