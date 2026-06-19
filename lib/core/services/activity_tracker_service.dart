import 'dart:async';
import 'dart:math' as math;
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'tts_service.dart';

// ============================================================================
// ESTADOS DE ACTIVIDAD
// ============================================================================
enum ActivityState {
  /// Inmóvil — magnitud oscilando cerca de la gravedad (~9.8 m/s²)
  still,

  /// Caminando — picos moderados entre 11 y 18 m/s²
  walking,

  /// Corriendo — picos altos entre 18 y 30 m/s²
  running,
}

// ============================================================================
// THRESHOLDS — calibrados para Galaxy A54 (acelerómetro ICM-42605-P)
//
//   Valores en m/s² (incluyendo gravedad, ~9.8 en reposo).
//   El acelerómetro del A54 reporta con ±0.5 m/s² de ruido en reposo,
//   por eso el umbral still es ligeramente holgado (11.0 en vez de 10.5).
// ============================================================================
const _kStillMax = 10.3; // < 10.3 → still
const _kWalkingMax = 18.0; // 11.0 — 18.0 → walking
// > 18.0 y < 30.0 → running
const _kFallImpactMin = 15.0; // ≥ 15.0 → impacto claro
const _kFallStillMax = 10.2; // (Ya no se usa, usamos Delta < 1.0)
const _kFallWindowMs = 1500; // ventana de verificación post-impacto reducida a 1.5s

// ============================================================================
// ActivityTrackerService — cerebro del Mega Reto
//
//   Arquitectura de streams:
//
//   accelerometerEventStream()
//         │
//         ▼
//   rawMagnitude$  ──┬── .debounceTime(3s) ──► classify ──► distinct ──► TTS
//   (PublishSubject) │                                      (actividad)
//                     │
//                     └── .listen(real-time) ──► fall detection ──► TTS
//                                                          (caída, urgente)
//
//   La caída NO pasa por el debounce — es un camino de emergencia
//   que pisa cualquier frase en curso.
// ============================================================================
class ActivityTrackerService {
  final TtsService _tts;

  ActivityTrackerService({required TtsService tts}) : _tts = tts;

  // --------------------------------------------------------------------------
  // FUENTE — acelerómetro crudo (con gravedad)
  // --------------------------------------------------------------------------
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;

  /// Magnitud cruda, sin filtrar. Alimenta ambos caminos de procesamiento.
  final PublishSubject<double> _rawMagnitude$ = PublishSubject<double>();

  // --------------------------------------------------------------------------
  // OUTPUTS — streams que consume la UI
  // --------------------------------------------------------------------------
  final BehaviorSubject<ActivityState> _activityState$ =
      BehaviorSubject<ActivityState>.seeded(ActivityState.still);

  final PublishSubject<void> _fallDetected$ = PublishSubject<void>();

  final BehaviorSubject<double> _currentMagnitude$ =
      BehaviorSubject<double>.seeded(0.0);

  /// Estado de actividad clasificado (Still / Walking / Running).
  /// Emite solo cuando cambia el estado (gracias a [distinct]).
  Stream<ActivityState> get activityState => _activityState$.stream;

  /// Emite un evento por cada caída confirmada (impacto + inmovilidad).
  Stream<void> get fallDetected => _fallDetected$.stream;

  /// Servicio de voz expuesto para pruebas manuales
  TtsService get tts => _tts;

  /// Magnitud actual del acelerómetro en m/s² (para depuración / UI).
  Stream<double> get currentMagnitude => _currentMagnitude$.stream;

  // --------------------------------------------------------------------------
  // SUSCRIPCIONES INTERNAS
  // --------------------------------------------------------------------------
  StreamSubscription<ActivityState>? _activitySubscription;
  StreamSubscription<double>? _fallSubscription;

  // --------------------------------------------------------------------------
  // MÁQUINA DE ESTADOS — variables de control
  // --------------------------------------------------------------------------
  ActivityState _previousState = ActivityState.still;
  bool _isTracking = false;

  // Detección de caída
  bool _fallWindowActive = false;
  DateTime _fallWindowStart = DateTime.now();
  final List<double> _fallWindowSamples = [];

  // ==========================================================================
  // CICLO DE VIDA
  // ==========================================================================

  /// Inicia el tracking: suscribe el acelerómetro, inicializa TTS y habla la
  /// bienvenida. Debe llamarse UNA vez al comenzar la sesión.
  Future<void> startTracking() async {
    if (_isTracking) return;

    await _tts.initialize();
    _isTracking = true;

    // --- Suscribir acelerómetro (con gravedad incluida) ---
    _sensorSubscription = accelerometerEventStream().listen(
      _onAccelerometerEvent,
      onError: (error) {
        // En el A54, errores de sensor son raros; si ocurren,
        // simplemente detenemos el tracking de forma segura.
        stopTracking();
      },
    );

    // --- Camino 1: Actividad estándar (Amplitud Max-Min) ---
    // Medimos la vibración real (Delta = Max - Min) en ventanas de 2 segundos.
    // Esto es 100% inmune a la gravedad porque mide la variación.
    _activitySubscription = _rawMagnitude$
        .bufferTime(const Duration(seconds: 2))
        .map((samples) {
          if (samples.isEmpty) return _previousState;
          
          final maxMag = samples.reduce(math.max);
          final minMag = samples.reduce(math.min);
          final delta = maxMag - minMag;
          
          if (delta < 0.8) return ActivityState.still;
          if (delta < 10.0) return ActivityState.walking;
          return ActivityState.running;
        })
        .distinct()
        .debounceTime(const Duration(milliseconds: 1500)) // Agregado a petición
        .listen(_handleActivityTransition);

    // --- Camino 2: Caídas (tiempo real, sin debounce) ---
    _fallSubscription = _rawMagnitude$.listen(_processFallDetection);

    // Bienvenida
    await _tts.speakWelcome();
  }

  /// Detiene el tracking, libera suscripciones y despide la sesión por voz.
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    _isTracking = false;
    await _tts.speakSessionEnd();

    await _sensorSubscription?.cancel();
    await _activitySubscription?.cancel();
    await _fallSubscription?.cancel();

    _sensorSubscription = null;
    _activitySubscription = null;
    _fallSubscription = null;
    _fallWindowActive = false;
  }

  /// Libera todos los recursos. Llamar cuando el servicio ya no se use.
  Future<void> dispose() async {
    await stopTracking();
    await _rawMagnitude$.close();
    await _activityState$.close();
    await _fallDetected$.close();
    await _currentMagnitude$.close();
    await _tts.dispose();
  }

  // ==========================================================================
  // PROCESAMIENTO DEL ACELERÓMETRO
  // ==========================================================================

  void _onAccelerometerEvent(AccelerometerEvent event) {
    // Magnitud del vector de aceleración (incluye gravedad)
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    _currentMagnitude$.add(magnitude);
    _rawMagnitude$.add(magnitude);
  }

  // ==========================================================================
  // CLASIFICACIÓN DE ACTIVIDAD
  // ==========================================================================

  ActivityState _classifyActivity(double magnitude) {
    if (magnitude < _kStillMax) return ActivityState.still;
    if (magnitude < _kWalkingMax) return ActivityState.walking;
    if (magnitude < _kFallImpactMin) return ActivityState.running;
    // ≥ 30 es territorio de caída, pero para la máquina de estados
    // de actividad lo tratamos como running (la caída se maneja aparte)
    return ActivityState.running;
  }

  // ==========================================================================
  // MÁQUINA DE ESTADOS — Actividad + TTS
  // ==========================================================================

  void _handleActivityTransition(ActivityState newState) {
    final prev = _previousState;
    _previousState = newState;

    // Emitir al stream de UI siempre
    _activityState$.add(newState);

    // Solo hablar en transiciones significativas
    if (prev == newState) return;

    switch (newState) {
      case ActivityState.still:
        // De caminar/correr → quieto = estiramiento
        if (prev == ActivityState.walking || prev == ActivityState.running) {
          _tts.speakStopped();
        }
        break;

      case ActivityState.walking:
        if (prev == ActivityState.running) {
          // Correr → caminar = recuperación
          _tts.speakCoolDown();
        } else {
          // Still → caminar = inicio de actividad
          _tts.speakWalking();
        }
        break;

      case ActivityState.running:
        if (prev == ActivityState.walking) {
          // Caminar → correr = aceleración
          _tts.speakSpeedUp();
        } else {
          // Still → correr (arranque directo)
          _tts.speakRunning();
        }
        break;
    }
  }

  // ==========================================================================
  // DETECCIÓN DE CAÍDA — Máquina de estados imperativa (sin debounce)
  //
  //   Firma de una caída real:
  //   1. Pico de impacto: magnitud ≥ 30 m/s² (cambio súbito de aceleración).
  //   2. Inmovilidad post-impacto: magnitud < 11 m/s² durante 2.5 segundos
  //      consecutivos (el cuerpo queda en reposo en el suelo).
  //
  //   Falsos positivos comunes que EVITAMOS:
  //   - Sacudir el teléfono (hay impacto pero hay movimiento después).
  //   - Dejar caer el teléfono sobre la mesa (impacto, luego inmovilidad
  //     del teléfono, pero no del usuario — este caso es difícil de
  //     distinguir sin giroscopio; el umbral de 30 ayuda a filtrarlo).
  //   - Saltar o hacer burpees (impactos < 30, o si son > 30 hay
  //     movimiento post-impacto).
  // ==========================================================================

  void _processFallDetection(double magnitude) {
    // --- Fase 1: Detección de impacto ---
    // Si la magnitud supera el umbral, INICIAMOS o REINICIAMOS la ventana.
    // Esto es crucial porque al alzar la mano para tirar el celular se puede
    // generar un impacto falso que inicie la ventana prematuramente.
    if (magnitude >= _kFallImpactMin) {
      _fallWindowActive = true;
      _fallWindowStart = DateTime.now();
      _fallWindowSamples.clear();
      return;
    }

    if (!_fallWindowActive) return; // nada que procesar

    // --- Fase 2: Ventana de verificación de inmovilidad ---
    _fallWindowSamples.add(magnitude);
    final elapsed =
        DateTime.now().difference(_fallWindowStart).inMilliseconds;

    if (elapsed >= _kFallWindowMs) {
      _fallWindowActive = false;

      // Evaluar inmovilidad usando DELTA (Max - Min) en lugar de Promedio.
      // Esto resuelve el problema de sensores descalibrados en Samsung
      // donde la gravedad no lee exactamente 9.8.
      final lastSamples = _fallWindowSamples.length > 20 
          ? _fallWindowSamples.sublist(_fallWindowSamples.length - 20) 
          : _fallWindowSamples;
      
      if (lastSamples.isEmpty) return;

      final maxMag = lastSamples.reduce(math.max);
      final minMag = lastSamples.reduce(math.min);
      final delta = maxMag - minMag;
          
      // Si el delta es menor a 1.0, significa que el teléfono no está vibrando
      final allStill = delta < 1.0;

      if (allStill) {
        _fallDetected$.add(null);
        _tts.speakFallDetected();
      }
    }
  }
}
