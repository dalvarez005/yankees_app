import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:google_identity_services_web/id.dart' as gis;
import 'package:web/web.dart' as web;

/// "Continuar con Google" en web.
///
/// Google solo entrega el idToken en el navegador a través de su propio
/// botón, y no deja cambiar sus colores (al pasar el mouse se pone celeste).
/// Por eso se dibuja nuestro botón ([visual]) y encima, transparente, el de
/// Google: el toque lo recibe Google (funciona igual en Safari del iPhone) y
/// lo que se ve es el estilo de la app.
Widget buildGoogleWebButton({required Widget visual}) => LayoutBuilder(
  builder: (context, constraints) => SizedBox(
    height: 54,
    child: Stack(
      children: [
        Positioned.fill(child: visual),
        Positioned.fill(
          child: _TransparentGoogleButton(width: constraints.maxWidth),
        ),
      ],
    ),
  ),
);

class _TransparentGoogleButton extends StatefulWidget {
  const _TransparentGoogleButton({required this.width});

  final double width;

  @override
  State<_TransparentGoogleButton> createState() =>
      _TransparentGoogleButtonState();
}

class _TransparentGoogleButtonState extends State<_TransparentGoogleButton> {
  static var _count = 0;

  late final String _viewType = _register(widget.width);

  /// Google admite como máximo 400 px de ancho y 40 px de alto (tamaño
  /// grande): se estira con CSS para cubrir todo nuestro botón.
  static String _register(double width) {
    final viewType = 'yankees-google-button-${_count++}';
    final gsiWidth = width.clamp(200, 400).toDouble();
    final scaleX = width > gsiWidth ? width / gsiWidth : 1.0;
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final host = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'flex'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.overflow = 'hidden'
        // Casi invisible: sigue recibiendo el clic.
        ..style.opacity = '0.01';
      final button = web.HTMLDivElement()
        ..style.transform = 'scale($scaleX, 1.4)';
      host.append(button);
      gis.id.renderButton(
        button,
        gis.GsiButtonConfiguration(
          type: gis.ButtonType.standard,
          size: gis.ButtonSize.large,
          shape: gis.ButtonShape.rectangular,
          width: gsiWidth,
          locale: 'es',
        ),
      );
      return host;
    });
    return viewType;
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
