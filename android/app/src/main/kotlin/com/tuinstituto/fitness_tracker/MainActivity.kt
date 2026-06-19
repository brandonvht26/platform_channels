package com.tuinstituto.fitness_tracker

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import kotlin.math.sqrt

/**
 * MainActivity: punto de entrada de la aplicación Android.
 *
 * Extiende FlutterFragmentActivity (necesario para BiometricPrompt).
 * Centraliza la configuración de los 3 Platform Channels:
 *   1. Biometría   → MethodChannel
 *   2. Acelerómetro → EventChannel + MethodChannel (/control)
 *   3. GPS          → MethodChannel + EventChannel (/stream)
 */
class MainActivity: FlutterFragmentActivity() {

    // ========================================================================
    // PLATFORM CHANNELS — Nombres (deben coincidir con Dart)
    // ========================================================================
    private val BIOMETRIC_CHANNEL = "com.tuinstituto.fitness/biometric"
    private val ACCELEROMETER_CHANNEL = "com.tuinstituto.fitness/accelerometer"
    private val GPS_CHANNEL = "com.tuinstituto.fitness/gps"

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

        executor = ContextCompat.getMainExecutor(this)

        setupBiometricChannel(flutterEngine)
        setupAccelerometerChannel(flutterEngine)
        setupGpsChannel(flutterEngine)
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
                    result.success(checkBiometricSupport())
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
    //   Estrategia de mitigación:
    //   • SENSOR_DELAY_NORMAL (~200ms, 5 Hz) — seguro para el Exynos
    //   • Filtro de paso bajo (media móvil de 10 muestras) contra jitter
    //   • Throttling: 1 de cada 3 muestras va a Flutter (≈1.6 eventos/s)
    //   • onCancel desregistra el listener → evita drenaje fantasma
    //
    // ========================================================================
    private fun setupAccelerometerChannel(flutterEngine: FlutterEngine) {
        val sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        var stepCount = 0
        var lastFilteredMagnitude = 0.0
        var sensorEventListener: SensorEventListener? = null

        val magnitudeHistory = mutableListOf<Double>()
        val historySize = 10
        var sampleCount = 0
        var lastActivityType = "stationary"
        var activityConfidence = 0

        // --- EventChannel: stream continuo ---
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
                            val rawMagnitude = sqrt(x * x + y * y + z * z)

                            // Low-Pass Filter: media móvil de 10 muestras
                            magnitudeHistory.add(rawMagnitude)
                            if (magnitudeHistory.size > historySize) {
                                magnitudeHistory.removeAt(0)
                            }
                            val filteredMagnitude = magnitudeHistory.average()

                            // Detección de paso sobre señal filtrada
                            if (filteredMagnitude > 12.0 && lastFilteredMagnitude <= 12.0) {
                                stepCount++
                            }
                            lastFilteredMagnitude = filteredMagnitude

                            // Clasificación de actividad con histéresis (3 muestras)
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

                            // Enviar 1 de cada 3 muestras a Flutter
                            sampleCount++
                            if (sampleCount >= 3) {
                                sampleCount = 0
                                events?.success(mapOf(
                                    "stepCount" to stepCount,
                                    "activityType" to finalActivityType,
                                    "magnitude" to filteredMagnitude
                                ))
                            }
                        }
                    }
                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                }

                sensorManager.registerListener(
                    sensorEventListener,
                    accelerometer,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
            }

            override fun onCancel(arguments: Any?) {
                sensorEventListener?.let { sensorManager.unregisterListener(it) }
                sensorEventListener = null
            }
        })

        // --- MethodChannel de control ---
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "$ACCELEROMETER_CHANNEL/control"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { stepCount = 0; result.success(null) }
                "stop"  -> { result.success(null) }
                "reset" -> { stepCount = 0; result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    // ========================================================================
    // MÓDULO 3 — GPS (MethodChannel + EventChannel /stream)
    // ========================================================================
    //
    // HARDWARE OBJETIVO: Samsung Galaxy A54 (Exynos 1380)
    //
    //   El GPS es el sensor más costoso en batería y temperatura.
    //   En el A54, PRIORITY_HIGH_ACCURACY sostenido >15 min eleva el chip
    //   GPS a 45-50°C → thermal throttling → pérdida de precisión.
    //
    //   ESTRATEGIA DE MITIGACIÓN (aplicada aquí):
    //
    //   1. Intervalo mínimo: 5000 ms (5 segundos) entre lecturas.
    //      ▸ Valor original del taller: 1000 ms → CORREGIDO.
    //      ▸ 5 s es suficiente para tracking de running/caminata
    //        (a 10 km/h se recorren ~14 m entre lecturas).
    //
    //   2. Distancia mínima: 5 metros para disparar update.
    //      ▸ Valor original del taller: 0 m → CORREGIDO.
    //      ▸ Descarta micro-desplazamientos por drift del GPS (~1-3 m),
    //        que son ruido sin valor para el tracking.
    //
    //   3. Fallback de proveedor: si GPS no tiene última ubicación,
    //      se consulta NETWORK_PROVIDER (torres celulares/WiFi).
    //      Esto es más rápido y no activa el chip GPS.
    //
    //   4. onCancel: removeUpdates() desvincula el listener Y apaga
    //      el chip GPS si no hay otros listeners activos.
    //
    //   MEJORA PARA PRODUCCIÓN:
    //   Reemplazar LocationManager por FusedLocationProviderClient
    //   (Google Play Services). Fusiona GPS + WiFi + sensores inerciales,
    //   es más preciso y un 30-40% más eficiente en batería.
    //
    // ========================================================================
    private fun setupGpsChannel(flutterEngine: FlutterEngine) {
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        var locationListener: LocationListener? = null

        // ====================================================================
        // MethodChannel: comandos puntuales (isGpsEnabled, getCurrentLocation)
        // ====================================================================
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GPS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGpsEnabled" -> {
                    val enabled = locationManager.isProviderEnabled(
                        LocationManager.GPS_PROVIDER
                    )
                    result.success(enabled)
                }

                "getCurrentLocation" -> {
                    if (!hasLocationPermission()) {
                        result.error(
                            "PERMISSION_DENIED",
                            "Permisos de ubicación no concedidos",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        // Intentar GPS primero, fallback a red (torres/WiFi)
                        val location = locationManager
                            .getLastKnownLocation(LocationManager.GPS_PROVIDER)
                            ?: locationManager
                                .getLastKnownLocation(LocationManager.NETWORK_PROVIDER)

                        if (location != null) {
                            result.success(locationToMap(location))
                        } else {
                            result.error(
                                "NO_LOCATION",
                                "Ubicación no disponible aún",
                                null
                            )
                        }
                    } catch (e: SecurityException) {
                        result.error(
                            "SECURITY_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }

        // ====================================================================
        // EventChannel: stream continuo de ubicaciones → Flutter
        // ====================================================================
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "$GPS_CHANNEL/stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                if (!hasLocationPermission()) {
                    events?.error(
                        "PERMISSION_DENIED",
                        "Permisos de ubicación no concedidos",
                        null
                    )
                    return
                }

                locationListener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        events?.success(locationToMap(location))
                    }
                    @Deprecated("")
                    override fun onStatusChanged(
                        provider: String?,
                        status: Int,
                        extras: Bundle?
                    ) { }
                    override fun onProviderEnabled(provider: String) { }
                    override fun onProviderDisabled(provider: String) { }
                }

                try {
                    //
                    //   CORREGIDO para Galaxy A54:
                    //
                    //   minTimeMs = 5000 (era 1000 → 5x más espaciado)
                    //   minDistanceM = 5f (era 0f → ignora drift < 5m)
                    //
                    //   Esto reduce los wakeups del chip GPS de
                    //   ~60/min a ~12/min. Diferencia de batería:
                    //   ~8-10% por hora con la config original
                    //   ~2-3% por hora con la config corregida.
                    //
                    locationManager.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        5000L,   // mínimo 5 segundos entre lecturas
                        5f,      // mínimo 5 metros de desplazamiento
                        locationListener!!
                    )
                } catch (e: SecurityException) {
                    events?.error("SECURITY_ERROR", e.message, null)
                }
            }

            // ----------------------------------------------------------------
            // CRÍTICO: onCancel DESVINCULA el listener Y apaga el chip GPS.
            //
            // removeUpdates() le dice al LocationManager que este listener
            // ya no necesita datos. Si era el único listener activo, el
            // chip GPS se apaga en segundos. Si esto no se llama, el GPS
            // sigue emitiendo con la app en background:
            //
            //   - A54: batería agotada en ~3 horas (5000 mAh)
            //   - Temperatura del chip: 45°C+ constante
            //   - CPU: wakelock implícito que impide deep sleep
            // ----------------------------------------------------------------
            override fun onCancel(arguments: Any?) {
                locationListener?.let {
                    locationManager.removeUpdates(it)
                }
                locationListener = null
            }
        })
    }

    // ========================================================================
    // HELPERS — GPS
    // ========================================================================

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun locationToMap(location: Location): Map<String, Any> {
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "altitude" to location.altitude,
            "speed" to location.speed.toDouble(),
            "accuracy" to location.accuracy.toDouble(),
            // Enviamos el timestamp real del GPS (epoch millis).
            // El lado Flutter actualmente usa DateTime.now() en fromMap,
            // pero este campo queda disponible para cuando corrijamos eso.
            "timestamp" to location.time
        )
    }
}
