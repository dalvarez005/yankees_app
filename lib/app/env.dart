import 'dart:io' show Platform;

/// Configuración por ambiente. Se sobrescribe al compilar con
/// `--dart-define=API_BASE_URL=local`, etc.
class Env {
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// API del club en el servidor (HTTPS por el túnel de Cloudflare).
  static const productionApiBaseUrl = 'https://yankeesapi.quantis.site';

  /// API levantada en la máquina de desarrollo: el emulador de Android
  /// llega a ella por 10.0.2.2; el simulador de iOS por localhost.
  static String get localApiBaseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:5114' : 'http://localhost:5114';

  /// URL de la API: la del servidor, salvo que se compile con
  /// `--dart-define=API_BASE_URL=...` (`local` usa [localApiBaseUrl]).
  static String get apiBaseUrl => switch (_apiBaseUrl) {
    '' => productionApiBaseUrl,
    'local' => localApiBaseUrl,
    _ => _apiBaseUrl,
  };

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
}
