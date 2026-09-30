import 'package:url_launcher/url_launcher.dart';

/// Abre el chat de WhatsApp con [number] (solo dígitos, con código de
/// país) y un mensaje ya escrito. Si WhatsApp no está instalado, `wa.me`
/// abre la versión web. Devuelve false si no se pudo abrir nada.
Future<bool> openWhatsApp(String number, {String? message}) async {
  final digits = number.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return false;
  final uri = Uri.https('wa.me', '/$digits', {
    if (message != null && message.isNotEmpty) 'text': message,
  });
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
