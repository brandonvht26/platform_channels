import 'package:flutter/services.dart';
import '../../../../core/platform/platform_channels.dart';
import '../../domain/entities/auth_result.dart';

/// DataSource para autenticación biométrica usando Platform Channels
/// - Este es el LADO FLUTTER del Platform Channel
/// - Usamos MethodChannel porque es petición/respuesta
/// - El nombre del canal DEBE coincidir con el lado Android
abstract class BiometricDataSource {
  Future<bool> canAuthenticate();
  Future<AuthResult> authenticate();
}

class BiometricDataSourceImpl implements BiometricDataSource {
  /// MethodChannel: canal de comunicación Flutter ↔ Android
  /// El nombre debe ser exactamente igual en ambos lados
  final MethodChannel _channel = const MethodChannel(
    PlatformChannels.biometric
  );

  @override
  Future<bool> canAuthenticate() async {
    try {
      /// invokeMethod: envía un mensaje a Android y espera respuesta
      /// - Parámetro 1: nombre del método (debe coincidir en Android)
      /// - Retorna: un Future con la respuesta
      final result = await _channel.invokeMethod<bool>(
        'checkBiometricSupport'
      );

      return result ?? false;
    } on PlatformException catch (e) {
      print('Error verificando biometría: ${e.message}');
      return false;
    }
  }

  @override
  Future<AuthResult> authenticate() async {
    try {
      /// Llamamos al método 'authenticate' del lado Android
      final result = await _channel.invokeMethod<bool>('authenticate');

      return AuthResult(
        success: result ?? false,
        message: result == true ? 'Autenticación exitosa' : 'Autenticación fallida',
      );
    } on PlatformException catch (e) {
      return AuthResult(
        success: false,
        message: 'Error: ${e.message}',
      );
    }
  }
}
