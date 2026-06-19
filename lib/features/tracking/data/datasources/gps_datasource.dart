import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/platform/platform_channels.dart';
import '../../domain/entities/location_point.dart';

// ============================================================================
// CONTRATO
// ============================================================================
abstract class GpsDataSource {
  Future<LocationPoint?> getCurrentLocation();
  Stream<LocationPoint> get locationStream;
  Future<bool> isGpsEnabled();
  Future<bool> requestPermissions();
}

// ============================================================================
// IMPLEMENTACIÓN FLUTTER
// ============================================================================
class GpsDataSourceImpl implements GpsDataSource {
  // MethodChannel: comandos puntuales (ubicación única, estado del GPS)
  final MethodChannel _methodChannel =
      const MethodChannel(PlatformChannels.gps);

  // EventChannel: stream continuo de ubicaciones
  final EventChannel _eventChannel =
      const EventChannel('${PlatformChannels.gps}/stream');

  // --------------------------------------------------------------------------
  // UBICACIÓN ÚNICA (MethodChannel)
  // --------------------------------------------------------------------------
  @override
  Future<LocationPoint?> getCurrentLocation() async {
    try {
      final result = await _methodChannel.invokeMethod('getCurrentLocation');
      if (result != null) {
        return LocationPoint.fromMap(result as Map<dynamic, dynamic>);
      }
      return null;
    } on PlatformException catch (e) {
      print('Error obteniendo ubicación: ${e.message}');
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // STREAM CONTINUO (EventChannel)
  // --------------------------------------------------------------------------
  //
  //   ADVERTENCIA DE BATERÍA — Samsung Galaxy A54 (Exynos 1380):
  //
  //   El GPS es el sensor que más batería consume y más calor genera.
  //   En el A54, PRIORITY_HIGH_ACCURACY sostenido >15 minutos eleva la
  //   temperatura del chip GPS hasta 45-50°C, lo que dispara thermal
  //   throttling y reduce la precisión (el chip baja su ciclo de trabajo).
  //
  //   Estrategia de mitigación en Kotlin (Android):
  //
  //   1. FusedLocationProviderClient con LocationRequest:
  //
  //        locationRequest = LocationRequest.Builder(
  //            LocationRequest.PRIORITY_HIGH_ACCURACY,  // solo en tracking
  //            5000  // intervalo mínimo 5 segundos
  //        ).apply {
  //            setMinUpdateDistanceMeters(5f)   // ignorar cambios < 5m
  //            setMaxUpdateDelayMillis(10000)    // batch de hasta 10s
  //        }.build()
  //
  //      - 5 segundos entre lecturas es suficiente para running/caminata.
  //      - 5 metros de distancia mínima evita micro-actualizaciones que
  //        dispararían el chip GPS sin aportar información utilizable.
  //
  //   2. Alternar prioridad según estado:
  //      - Tracking activo: PRIORITY_HIGH_ACCURACY (GPS + redes)
  //      - En pausa: PRIORITY_BALANCED_POWER_ACCURACY (solo WiFi/celular)
  //      - App en background: remover updates inmediatamente.
  //
  //   3. onCancel del EventChannel DEBE llamar a:
  //
  //        fusedLocationClient.removeLocationUpdates(locationCallback)
  //
  //      Si no se remueve, el GPS sigue encendido con la app en background
  //      → batería del A54 drenada en ~3 horas incluso sin usar la app.
  //
  //   Estas optimizaciones se implementan en el lado Android (próximo paso).
  //   Este DataSource de Flutter solo consume el stream ya optimizado.
  //
  // --------------------------------------------------------------------------
  @override
  Stream<LocationPoint> get locationStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return LocationPoint.fromMap(event as Map<dynamic, dynamic>);
    });
  }

  // --------------------------------------------------------------------------
  // VERIFICACIÓN DE GPS HABILITADO
  // --------------------------------------------------------------------------
  @override
  Future<bool> isGpsEnabled() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isGpsEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // PERMISOS DE UBICACIÓN
  //
  // Estrategia: primero pedir el permiso "siempre" (location). Si se deniega,
  // degradar a "solo en uso" (locationWhenInUse) como fallback. Esto es
  // importante en Android 12+ donde el usuario puede elegir "Precisa" vs
  // "Aproximada" — para tracking necesitamos la ubicación precisa.
  // --------------------------------------------------------------------------
  @override
  Future<bool> requestPermissions() async {
    final locationStatus = await Permission.location.request();
    if (!locationStatus.isGranted) {
      final whenInUseStatus = await Permission.locationWhenInUse.request();
      return whenInUseStatus.isGranted;
    }
    return locationStatus.isGranted;
  }
}
