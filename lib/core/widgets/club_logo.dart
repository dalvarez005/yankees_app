import 'package:flutter/material.dart';

/// Logo del club en un recuadro blanco redondeado, para los encabezados
/// azules.
class ClubLogo extends StatelessWidget {
  const ClubLogo({super.key, this.size = 36});

  final double size;

  static const asset = 'assets/branding/logo.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        // Se decodifica al tamaño en pantalla, no a 512 px.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        semanticLabel: 'Club Yankees',
      ),
    );
  }
}
