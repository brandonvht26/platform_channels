import 'package:flutter_tts/flutter_tts.dart';
import '../../features/steps/domain/entities/step_data.dart'; // Asegúrate de que ActivityType esté importado de tu entidad real

/// Clase independiente encargada exclusivamente de manejar la voz de la app.
/// Implementa buenas prácticas encapsulando el FlutterTts y controlando el estado
/// para evitar spam de audios.
class VoiceAnnouncer {
  final FlutterTts _flutterTts = FlutterTts();
  
  // LA VARIABLE SECRETA: guarda el último estado que se habló.
  ActivityType? _lastAnnouncedState;
  
  bool _initialized = false;

  /// Inicializa el motor. Puedes llamarlo una vez al iniciar la app.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // Forzamos el idioma por defecto del dispositivo
    try { await _flutterTts.setLanguage("es-MX"); } catch (_) {}
  }

  /// Función principal para hablar al cambiar de estado.
  Future<void> announceActivityChange(ActivityType newState) async {
    // 1. REGLA DE ORO: Si el estado nuevo es el mismo que el anterior, abortar.
    // Esto salva la memoria del celular y evita que FlutterTts se sature.
    if (_lastAnnouncedState == newState) return;
    
    // 2. Actualizamos el estado actual
    _lastAnnouncedState = newState;

    if (!_initialized) await initialize();

    // 3. Switch limpio y ordenado
    String phrase = "";
    switch (newState) {
      case ActivityType.walking:
        phrase = "Estás caminando";
        break;
      case ActivityType.running:
        phrase = "Estás corriendo";
        break;
      case ActivityType.stationary:
        phrase = "Llegó la hora de estirarse";
        break;
      case ActivityType.falling:
        // La caída la manejamos con la función especial announceFallEmergency(),
        // así que aquí no le asignamos frase para no sobreescribir audios.
        break;
    }

    if (phrase.isNotEmpty) {
      try {
        await _flutterTts.speak(phrase);
      } catch (e) {
        // Manejo silencioso
      }
    }
  }

  /// Función para emergencias (se salta la validación del estado anterior)
  Future<void> announceFallEmergency() async {
    if (!_initialized) await initialize();
    try {
      await _flutterTts.speak("He detectado una caída ¿Estás bien?");
    } catch (_) {}
  }
}
