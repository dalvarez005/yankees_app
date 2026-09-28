import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error de la API ya traducido a un mensaje para mostrar al usuario.
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode});

  final String message;

  /// responseCode de la API: "05" no autorizado, "30" campo inválido,
  /// "96" error del sistema.
  final String? code;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Provee el token de sesión y lo renueva. Lo implementa SessionManager.
abstract class Authenticator {
  /// Token vigente (lo renueva antes si está por vencer); null sin sesión.
  Future<String?> accessToken();

  /// Fuerza la renovación tras un 401; null si no se pudo.
  Future<String?> refreshAccessToken();
}

/// Cliente JSON para la API de Yankees. Los errores llegan como
/// `{ "responseCode": "30", "message": "..." }`.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, this.authenticator})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Si hay sesión, cada request lleva `Authorization: Bearer <token>`.
  Authenticator? authenticator;

  static const _timeout = Duration(seconds: 30);

  /// [authenticated] en false para endpoints que no deben llevar ni renovar
  /// el token (login, registro, el propio refresh).
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) => _request('POST', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) =>
      _request('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authenticated,
  }) async {
    final auth = authenticated ? authenticator : null;
    final token = await auth?.accessToken();
    var response = await _send(method, path, body, token);

    // Token vencido o revocado: se renueva una vez y se reintenta.
    if (response.statusCode == 401 && token != null && auth != null) {
      final renewed = await auth.refreshAccessToken();
      if (renewed != null) response = await _send(method, path, body, renewed);
    }

    final json = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json ?? const {};
    }
    final code = json?['responseCode']?.toString();
    if (kDebugMode) {
      debugPrint(
        'API $method $path → ${response.statusCode}: ${response.body}',
      );
    }
    throw ApiException(
      response.statusCode == 429
          ? 'Demasiados intentos. Espera un momento e intenta de nuevo.'
          : _friendlyMessage(code, json?['message']?.toString()),
      code: code,
      statusCode: response.statusCode,
    );
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? token,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final request = method == 'GET'
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body));
      return await request.timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'El servidor tardó demasiado en responder. Intenta de nuevo.',
      );
    } on SocketException {
      throw const ApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    } on http.ClientException {
      throw const ApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión.',
      );
    }
  }

  Map<String, dynamic>? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// La API devuelve mensajes técnicos en mayúsculas; los de validación de
  /// datos (código 30) sí sirven al usuario, el resto se generaliza.
  static String _friendlyMessage(String? code, String? message) {
    switch (code) {
      case '96':
        return 'Ocurrió un error en el servidor. Intenta más tarde.';
      case '05':
        return 'No se pudo verificar tu identidad. Intenta de nuevo.';
    }
    if (message == null || message.isEmpty || message == 'SOLICITUD INVALIDA') {
      return 'No se pudo procesar la solicitud. Revisa los datos.';
    }
    return translate(message);
  }

  /// Mensajes conocidos de la API (vienen en inglés o técnicos) → español.
  static const _known = {
    'EMAIL ALREADY EXISTS': 'Ya existe una cuenta con ese correo.',
    'USERNAME ALREADY EXISTS': 'Ya existe una cuenta con ese correo.',
    'CUI YA ASOCIADO A UN DEPENDIENTE ACTIVO': 'Ese CUI ya está registrado.',
    'DEPENDENT NOT FOUND': 'No se encontró el registro. Actualiza la lista.',
    'NO FIELDS TO UPDATE': 'No hay cambios para guardar.',
  };

  /// Traduce los mensajes conocidos (pueden venir varios separados por
  /// coma); si no hay traducción se muestra el original legible.
  static String translate(String message) {
    final parts = message.split(',').map((m) => m.trim().toUpperCase());
    final translated = {
      for (final p in parts)
        if (p.isNotEmpty) _known[p] ?? sentenceCase(p),
    };
    return translated.join(' ');
  }

  /// "YA EXISTE EL CORREO" → "Ya existe el correo".
  static String sentenceCase(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return lower;
    return lower[0].toUpperCase() + lower.substring(1);
  }
}
