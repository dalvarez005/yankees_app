import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error de la API ya traducido a un mensaje para mostrar al usuario.
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode, this.raw});

  final String message;

  /// Mensaje original de la API (para decidir reintentos, no para mostrar).
  final String? raw;

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

  /// Subir una foto con mala señal tarda más que un JSON.
  static const _uploadTimeout = Duration(seconds: 90);

  /// [authenticated] en false para endpoints que no deben llevar ni renovar
  /// el token (login, registro, el propio refresh).
  ///
  /// [bearer]: usar este token en vez del de la sesión (p. ej. para avisar
  /// a la API después de haber cerrado la sesión local). No se renueva.
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
    String? bearer,
  }) => _request(
    'POST',
    path,
    body: body,
    authenticated: authenticated,
    bearer: bearer,
  );

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) =>
      _request('GET', path, authenticated: authenticated);

  Future<Map<String, dynamic>> patch(
    String path, [
    Map<String, dynamic>? body,
  ]) => _request('PATCH', path, body: body, authenticated: true);

  /// POST `multipart/form-data` con un archivo (p. ej. un comprobante):
  /// desde disco ([filePath]) o ya en memoria ([bytes] + [fileName]).
  Future<Map<String, dynamic>> postFile(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    String? filePath,
    List<int>? bytes,
    String fileName = 'archivo',
  }) {
    assert(filePath != null || bytes != null, 'Falta el archivo');
    return _request(
      'POST',
      path,
      upload: _Upload(fields, fileField, filePath, bytes, fileName),
      authenticated: true,
    );
  }

  /// Headers para pedir recursos protegidos fuera del cliente (imágenes).
  Future<Map<String, String>> authHeaders() async {
    final token = await authenticator?.accessToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    _Upload? upload,
    required bool authenticated,
    String? bearer,
  }) async {
    final auth = authenticated && bearer == null ? authenticator : null;
    final token = bearer ?? await auth?.accessToken();
    var response = await _send(method, path, body, token, upload);

    // Token vencido o revocado: se renueva una vez y se reintenta.
    if (response.statusCode == 401 && token != null && auth != null) {
      final renewed = await auth.refreshAccessToken();
      if (renewed != null) {
        response = await _send(method, path, body, renewed, upload);
      }
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
      raw: json?['message']?.toString(),
    );
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? token, [
    _Upload? upload,
  ]) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      if (upload != null) {
        final request = http.MultipartRequest('POST', uri)
          ..fields.addAll(upload.fields)
          ..files.add(
            upload.bytes != null
                ? http.MultipartFile.fromBytes(
                    upload.field,
                    upload.bytes!,
                    filename: upload.fileName,
                  )
                : await http.MultipartFile.fromPath(upload.field, upload.path!),
          );
        if (token != null) request.headers['Authorization'] = 'Bearer $token';
        final streamed = await _client.send(request).timeout(_uploadTimeout);
        return await http.Response.fromStream(streamed);
      }
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'PATCH' => _client.patch(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        _ => _client.post(uri, headers: headers, body: jsonEncode(body)),
      };
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
    'USERNAME INVALIDO': 'No se pudo crear la cuenta. Intenta de nuevo.',
    'EMAIL NO VALIDO': 'Escribe un correo válido.',
    'EMAIL OBLIGATORIO O INVALIDO': 'Escribe un correo válido.',
    'AGE ES OBLIGATORIO': 'Escribe la edad.',
    'DATEBIRTHDAY ES OBLIGATORIO': 'Elige la fecha de nacimiento.',
    'FECHA OBLIGATORIA': 'Elige la fecha de nacimiento.',
    'DATEBIRTHDAY NO PUEDE SER UNA FECHA FUTURA':
        'La fecha de nacimiento no puede ser futura.',
    'FECHA DE NACIMIENTO NO PUEDE SER FUTURA':
        'La fecha de nacimiento no puede ser futura.',
    'RANGO DE EDAD OBLIGATORIO': 'Indica las edades de la categoría.',
    'INDIQUE EDAD MINIMA Y MAXIMA': 'Indica la edad mínima y la máxima.',
    'LAS EDADES DEBEN ESTAR ENTRE 0 Y 120':
        'Las edades deben estar entre 0 y 120 años.',
    'LA EDAD MINIMA NO PUEDE SER MAYOR A LA MAXIMA':
        'La edad mínima no puede ser mayor que la máxima.',
    'RANGO DE EDAD INVALIDO': 'El rango de edad no es válido.',
    'NO HAY UNA CATEGORIA ACTIVA PARA LA EDAD DEL DEPENDIENTE':
        'El club no tiene una categoría para esa edad. Consulta con el club.',
    'AGE DEBE ESTAR ENTRE 0 Y 120': 'La edad debe estar entre 0 y 120 años.',
    'EDAD DEBE ESTAR ENTRE 0 Y 120': 'La edad debe estar entre 0 y 120 años.',
    'CUI YA ASOCIADO A UN DEPENDIENTE ACTIVO': 'Ese CUI ya está registrado.',
    'DEPENDENT NOT FOUND': 'No se encontró el registro. Actualiza la lista.',
    'NO FIELDS TO UPDATE': 'No hay cambios para guardar.',
    'NO TIENE PERMISO PARA ESTA ACCION': 'No tienes permiso para esta acción.',
    'NOMBRE YA EXISTE': 'Ya existe uno con ese nombre.',
    'REGISTRO NO EXISTE O ESTA INACTIVO':
        'Ya no está disponible. Actualiza la lista.',
    'REGISTRO TIENE ASOCIACIONES':
        'No se puede desactivar: todavía está en uso.',
    'ROL DEL SISTEMA PROTEGIDO': 'Los roles del sistema no se modifican.',
    'NO PUEDE CAMBIAR LOS PERMISOS DE SU PROPIO ROL':
        'No puedes cambiar los permisos de tu propio rol.',
    'NO PUEDE OTORGAR PERMISOS QUE NO TIENE':
        'Solo puedes otorgar permisos que tú tienes.',
    'PERMISO NO EXISTE': 'Uno de los permisos ya no existe. Recarga.',
    'CAMBIO DE ROL NO AUTORIZADO': 'No tienes permiso para asignar ese rol.',
    'NO PUEDE MODIFICAR A OTRO SUPER_ADMIN':
        'Un super admin no se modifica desde la app.',
    'NO PUEDE CAMBIAR SU PROPIO ACCESO':
        'No puedes cambiar tu propio rol ni desactivarte.',
    'USUARIO NO EXISTE': 'No se encontró el usuario. Actualiza la lista.',
    'USUARIO NO EXISTE O ESTA INACTIVO':
        'El usuario no existe o está inactivo.',
    'ROL NO EXISTE O ESTA INACTIVO': 'Ese rol ya no está disponible.',
    'NO SE PUEDE ASIGNAR SUPER_ADMIN':
        'El rol de super admin no se asigna desde la app.',
    // Validación de usuarios y cuotas.
    'USUARIO YA VALIDADO': 'Este usuario ya fue validado. Actualiza la lista.',
    'USUARIO NO REQUIERE VALIDACION':
        'Este usuario es administrador: no se le cobran cuotas.',
    'MONTO INVALIDO': 'El monto debe ser mayor a Q 0 y hasta Q 100,000.',
    'INSCRIPCION YA PAGADA':
        'La inscripción ya se pagó o está en revisión: no se puede cambiar.',
    'PERFIL PENDIENTE DE VALIDACION':
        'Tu perfil aún está en configuración. El club te avisará cuando '
        'esté listo.',
    'CONFIGURACION INVALIDA':
        'Revisa los datos: día límite entre 1 y 28, montos no negativos y '
        'WhatsApp de 8 a 15 dígitos.',
    // Cobros y comprobantes.
    'COBRO NO EXISTE': 'No se encontró el cobro. Actualiza la lista.',
    'COBRO YA TIENE COMPROBANTE EN REVISION':
        'Ya enviaste un comprobante; está en revisión.',
    'COBRO YA PAGADO': 'Este cobro ya está pagado.',
    'NO SE PUEDE ANULAR UN COBRO PAGADO': 'No se puede anular un cobro pagado.',
    'MONTO NO COINCIDE CON EL COBRO':
        'El monto del comprobante debe ser igual al del cobro.',
    'REFERENCIA YA UTILIZADA':
        'Ese número de boleta o transferencia ya se usó en otro comprobante.',
    'COMPROBANTE DUPLICADO':
        'Este comprobante ya se había enviado antes. Si es un pago nuevo, '
        'sube la foto del comprobante correcto.',
    'ARCHIVO NO VALIDO': 'El archivo debe ser una foto (JPG, PNG o WebP).',
    'ARCHIVO DEMASIADO GRANDE': 'La foto es muy pesada (máximo 2 MB).',
    'FECHA DE PAGO INVALIDA': 'La fecha de pago no puede ser futura.',
    'DATOS DEL COMPROBANTE INCOMPLETOS':
        'Completa monto, número de boleta, descripción y fecha de pago.',
    'COMENTARIO OBLIGATORIO':
        'Escribe el motivo del rechazo (mínimo 10 caracteres).',
    'COMPROBANTE YA REVISADO': 'Otro administrador ya revisó este comprobante.',
    'NUMERO DE WHATSAPP INVALIDO':
        'Número inválido: código de país y número, solo dígitos.',
  };

  /// Traduce los mensajes conocidos (pueden venir varios separados por
  /// coma); si no hay traducción se muestra el original legible.
  static String translate(String message) {
    final parts = message.split(',').map((m) => m.trim().toUpperCase());
    final translated = {
      for (final p in parts)
        if (p.isNotEmpty) _known[p] ?? _withName(p) ?? sentenceCase(p),
    };
    return translated.join(' ');
  }

  static const _overlap = 'EL RANGO SE CRUZA CON LA CATEGORIA ';

  /// Mensajes que traen un nombre al final.
  static String? _withName(String p) {
    if (!p.startsWith(_overlap)) return null;
    final name = sentenceCase(p.substring(_overlap.length));
    return 'Ese rango de edad se cruza con la categoría $name.';
  }

  /// "YA EXISTE EL CORREO" → "Ya existe el correo".
  static String sentenceCase(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return lower;
    return lower[0].toUpperCase() + lower.substring(1);
  }
}

class _Upload {
  const _Upload(this.fields, this.field, this.path, this.bytes, this.fileName);
  final Map<String, String> fields;
  final String field;
  final String? path;
  final List<int>? bytes;
  final String fileName;
}
