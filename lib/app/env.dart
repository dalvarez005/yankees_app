import 'dart:io' show Platform;

/// Configuración por ambiente. Se sobrescribe al compilar con
/// `--dart-define=API_BASE_URL=https://api.club.com`, etc.
class Env {
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// URL de la API. Por defecto la API local: el emulador de Android llega
  /// a la máquina por 10.0.2.2; el simulador de iOS por localhost.
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    return Platform.isAndroid
        ? 'http://10.0.2.2:5114'
        : 'http://localhost:5114';
  }

  /// Client ID "Web" de Google con el que la API valida el idToken
  /// (debe coincidir con Google__clientId del backend).
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '619026017478-6ceh6n1f42r6uqquia97305d9ic6c3a9.apps.googleusercontent.com',
  );

  /// Client ID de iOS (también en ios/Runner/Info.plist como GIDClientID).
  /// Android no lleva ID en código: Google lo reconoce por paquete + SHA-1.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '619026017478-lm9ffl7bhp8ohijfvluu9lam76j991bc.apps.googleusercontent.com',
  );

  /// `--dart-define=USE_MOCK=true` para trabajar sin API.
  static const useMock = bool.fromEnvironment('USE_MOCK');

  /// Pagos contra la API (`--dart-define=PAYMENTS_API=true`). Mientras el
  /// módulo no exista en la API se usan datos simulados en memoria.
  static const paymentsApi = bool.fromEnvironment('PAYMENTS_API');
}
