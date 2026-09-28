import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/env.dart';

/// Obtiene el idToken de Google que la API valida. Separado del repositorio
/// para poder reemplazarlo en pruebas.
abstract class GoogleIdTokenProvider {
  /// Devuelve null si el usuario cierra el selector de cuentas; cualquier
  /// otra falla se lanza como excepción.
  Future<String?> getIdToken();

  Future<void> signOut();
}

class GoogleSignInIdTokenProvider implements GoogleIdTokenProvider {
  Future<void>? _init;

  Future<void> _ensureInitialized() =>
      _init ??= GoogleSignIn.instance.initialize(
        serverClientId: Env.googleServerClientId,
        // En Android el clientId no se usa (va por paquete + SHA-1).
        clientId: Platform.isIOS ? Env.googleIosClientId : null,
      );

  @override
  Future<String?> getIdToken() async {
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'Sin idToken',
        );
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (_isUserCancel(e)) return null;
      // El detalle solo va al log de desarrollo; al usuario, mensaje genérico.
      if (kDebugMode) {
        debugPrint('GoogleSignIn falló: ${e.code} ${e.description}');
      }
      rethrow;
    }
  }

  /// Android reporta la falta del cliente OAuth (paquete + SHA-1) como
  /// "canceled" con "[16] Account reauth failed"; eso no es una cancelación.
  static bool _isUserCancel(GoogleSignInException e) =>
      (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) &&
      !(e.description ?? '').contains('reauth failed');

  @override
  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } on GoogleSignInException {
      // Si no había sesión de Google no hay nada que cerrar.
    }
  }
}
