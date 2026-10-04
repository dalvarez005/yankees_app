import 'package:web/web.dart' as web;

/// La web está abierta como app agregada a la pantalla de inicio (PWA).
bool isStandaloneWebApp() =>
    web.window.matchMedia('(display-mode: standalone)').matches;
