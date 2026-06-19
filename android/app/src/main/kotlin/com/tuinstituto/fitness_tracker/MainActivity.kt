package com.tuinstituto.fitness_tracker

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import kotlin.math.sqrt

/**
 * MainActivity: punto de entrada de la aplicación Android
 * - Extiende FlutterFragmentActivity (necesario para BiometricPrompt)
 * - Configura Platform Channels para biometría y acelerómetro
 */
class MainActivity: FlutterFragmentActivity() {

    // ========================================================================
    // PLATFORM CHANNELS — Nombres (deben coincidir con Dart)
    // ========================================================================
    private val BIOMETRIC_CHANNEL = "com.tuinstituto.fitness/biometric"
    private val ACCELEROMETER_CHANNEL = "com.tuinstituto.fitness/accelerometer"

    // ========================================================================
    // BIOMETRÍA — Variables de estado
    // ========================================================================
    private lateinit var executor: Executor
    private lateinit var biometricPrompt: BiometricPrompt
    private var pendingResult: MethodChannel.Result? = null

    // ========================================================================
    // configureFlutterEngine: registro central de TODOS los Platform Channels
    // ========================================================================
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Inicializar executor para biometría
        executor = ContextCompat.getMainExecutor(this)

        // Configurar canales
        setupBiometricChannel(flutterEngine)
        setupAccelerometerChannel(flutterEngine)
    }

    // ========================================================================
    // MÓDULO 1 — BIOMETRÍA (MethodChannel)
    // ========================================================================
    private fun setupBiometricChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BIOMETRIC_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkBiometricSupport" -> {
                    val canAuth = checkBiometricSupport()
                    result.success(canAuth)
                }

                "authenticate" -> {
                    pendingResult = result
                    showBiometricPrompt()
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun checkBiometricSupport(): Boolean {
        val biometricManager = BiometricManager.from(this)
        return when (biometricManager.canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        )) {
            BiometricManager.BIOMETRIC_SUCCESS -> true
            else -> false
        }
    }

    private fun showBiometricPrompt() {
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Autenticación Biométrica")
            .setSubtitle("Usa tu huella dactilar")
            .setDescription("Coloca tu dedo en el sensor")
            .setNegativeButtonText("Cancelar")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        biometricPrompt = BiometricPrompt(this, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult
                ) {
                    super.onAuthenticationSucceeded(result)
                    pendingResult?.success(true)
                    pendingResult = null
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence
                ) {
                    super.onAuthenticationError(errorCode, errString)
                    pendingResult?.success(false)
                    pendingResult = null
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                }
            }
        )

        biometricPrompt.authenticate(promptInfo)
    }

    // ========================================================================
    // MÓDULO 2 — ACELERÓMETRO (EventChannel + MethodChannel de control)
    // ========================================================================
    //
    // HARDWARE OBJETIVO: Samsung Galaxy A54 (Exynos 1380)
    //
    //   Riesgos específicos del A54:
    //   1. Acelerómetro con jitter (ruido de alta frecuencia en reposo)
    //   2. CPU propenso a thermal throttling si se satura con lecturas
    //      ultrarrápidas del sensor
    //   3. Batería de 5000 mAh pero el sensor mal gestionado la drena
    //      rápidamente (el listener queda activo aunque Flutter cierre)
    //
    //   Estrategia de mitigación aplicada AQUÍ:
    //   • SENSOR_DELAY_NORMAL (~200ms, 5 Hz) — frecuencia segura para el
    //     Exynos, evita sobrecalentamiento y still captura pasos con precisión
    //   • Filtro de paso bajo (media móvil de 10 muestras) para suavizar
    //     el ruido del acelerómetro
    //   • Throttling: solo se envía 1 de cada 3 muestras a Flutter por el
    //     EventChannel (≈1.6 eventos/s con SENSOR_DELAY_NORMAL)
    //   • onCancel DESREGISTRA el listener — evita el drenaje fantasma
    //
    //   MEJORA FUTURA (producción):
    //   Reemplazar la media móvil simple por un EMA (Exponential Moving
    //   Average). La fórmula es:
    //
    //     filtered = alpha * raw + (1 - alpha) * previousFiltered
    //
    //   Ventajas del EMA sobre media móvil:
    //   - Solo necesita 1 valor previo (no un buffer de 10), ahorra RAM
    //   - Da más peso a las muestras recientes, responde más rápido a
    //     cambios reales de actividad
    //   - Un spike de ruido se diluye exponencialmente en vez de
    //     "contaminar" 10 muestras
    //   - alpha recomendado: 0.15—0.25 para caminata, 0.3—0.4 para running
    //
    //   Si implementas EMA, elimina magnitudeHistory y reemplaza:
    //     filtered = alpha * magnitude + (1 - alpha) * filteredPrev
    //
    // ========================================================================
    private fun setupAccelerometerChannel(flutterEngine: FlutterEngine) {
        val sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        // --- Estado compartido entre EventChannel y MethodChannel ---
        var stepCount = 0
        var lastFilteredMagnitude = 0.0
        var sensorEventListener: SensorEventListener? = null

        // Low-Pass Filter: media móvil de 10 muestras
        val magnitudeHistory = mutableListOf<Double>()
        val historySize = 10
        var sampleCount = 0
        var lastActivityType = "stationary"
        var activityConfidence = 0

        // ====================================================================
        // EventChannel: stream continuo de datos del sensor → Flutter
        // ====================================================================
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACCELEROMETER_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sensorEventListener = object : SensorEventListener {

                    override fun onSensorChanged(event: SensorEvent?) {
                        event?.let {
                            val x = it.values[0].toDouble()
                            val y = it.values[1].toDouble()
                            val z = it.values[2].toDouble()

                            // Magnitud del vector de aceleración (sin gravedad
                            // sustraída — suficiente para detección de pasos)
                            val rawMagnitude = sqrt(x * x + y * y + z * z)

                            // -------------------------------------------------
                            // FILTRO DE PASO BAJO — Media Móvil Simple
                            //
                            // Suaviza el jitter del acelerómetro del A54.
                            // Con 10 muestras @ SENSOR_DELAY_NORMAL (~200ms)
                            // la ventana cubre ≈2 segundos de historial.
                            // -------------------------------------------------
                            magnitudeHistory.add(rawMagnitude)
                            if (magnitudeHistory.size > historySize) {
                                magnitudeHistory.removeAt(0)
                            }
                            val filteredMagnitude = magnitudeHistory.average()

                            // -------------------------------------------------
                            // DETECCIÓN DE PASO sobre señal FILTRADA
                            //
                            //   CORREGIDO: antes usaba rawMagnitude aquí.
                            //   Con el jitter del A54 eso generaba falsos
                            //   positivos (picos espurios > 12).
                            //
                            //   Umbral 12: la magnitud en reposo ronda 9.8
                            //   (gravedad). Un paso añade ~2-5 unidades.
                            // -------------------------------------------------
                            if (filteredMagnitude > 12.0 && lastFilteredMagnitude <= 12.0) {
                                stepCount++
                            }
                            lastFilteredMagnitude = filteredMagnitude

                            // -------------------------------------------------
                            // CLASIFICACIÓN DE ACTIVIDAD con histéresis
                            //
                            // Requiere 3 muestras consecutivas del mismo tipo
                            // para cambiar. Esto evita oscilaciones espurias
                            // entre "walking" y "running" en cada zancada.
                            // -------------------------------------------------
                            val newActivityType = when {
                                filteredMagnitude < 10.5 -> "stationary"
                                filteredMagnitude < 13.5 -> "walking"
                                else -> "running"
                            }

                            activityConfidence = if (newActivityType == lastActivityType) {
                                activityConfidence + 1
                            } else {
                                0
                            }

                            val finalActivityType = if (activityConfidence >= 3) {
                                newActivityType
                            } else {
                                lastActivityType
                            }
                            lastActivityType = newActivityType

                            // -------------------------------------------------
                            // THROTTLING: enviar 1 de cada 3 muestras a Flutter
                            //
                            // Reduce el tráfico por EventChannel. A 5 Hz
                            // (SENSOR_DELAY_NORMAL) esto da ≈1.6 eventos/s,
                            // suficiente para UI en tiempo real sin saturar
                            // el message passing de Flutter.
                            // -------------------------------------------------
                            sampleCount++
                            if (sampleCount >= 3) {
                                sampleCount = 0
                                val data = mapOf(
                                    "stepCount" to stepCount,
                                    "activityType" to finalActivityType,
                                    "magnitude" to filteredMagnitude
                                )
                                events?.success(data)
                            }
                        }
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                        // No se requiere acción para acelerómetro
                    }
                }

                // Registrar listener del sensor
                //
                //   SENSOR_DELAY_NORMAL: ~200ms entre lecturas (5 Hz)
                //   Elección segura para el Exynos del A54.
                //   Alternativas comentadas para referencia:
                //
                //   SENSOR_DELAY_UI       ≈ 60ms (16 Hz) — más fluido pero
                //                          riesgo de calentamiento en A54
                //                          tras >20 min de uso continuo.
                //   SENSOR_DELAY_GAME     ≈ 20ms (50 Hz) — PROHIBIDO en A54.
                //   SENSOR_DELAY_FASTEST  ≈  0ms — PROHIBIDO.
                //
                sensorManager.registerListener(
                    sensorEventListener,
                    accelerometer,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
            }

            // ----------------------------------------------------------------
            // CRÍTICO: onCancel DEBE desregistrar el listener del sensor.
            //
            // Si esto no se hace, el sensor sigue emitiendo eventos aunque
            // Flutter haya cerrado el stream. En el A54 esto significa:
            // - CPU mantiene un wakelock implícito (el sensor no deja dormir)
            // - Batería drenada en 1-2 horas incluso con la app en background
            // - Sobrecalentamiento si el usuario abre/cierra el stream
            //   repetidamente sin que los listeners anteriores se limpien
            // ----------------------------------------------------------------
            override fun onCancel(arguments: Any?) {
                sensorEventListener?.let {
                    sensorManager.unregisterListener(it)
                }
                sensorEventListener = null
            }
        })

        // ====================================================================
        // MethodChannel auxiliar de control (start / stop / reset)
        //
        // Convención: el nombre del canal es <event_channel>/control
        // Esto separa señales de control (comandos) del flujo de datos
        // (stream) y evita colisiones de tipos de mensaje.
        // ====================================================================
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "$ACCELEROMETER_CHANNEL/control"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    stepCount = 0
                    result.success(null)
                }
                "stop" -> {
                    // El sensor sigue registrado (el EventChannel
                    // gestiona el ciclo de vida). Aquí solo
                    // reseteamos estado si se necesita.
                    result.success(null)
                }
                "reset" -> {
                    stepCount = 0
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
