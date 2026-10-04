import 'package:flutter/widgets.dart';

/// Anchos de la app para que se vea bien en teléfono, tablet y PC (web).
///
/// En teléfono todo usa el ancho completo. En pantallas anchas los fondos
/// (encabezados azules, barras) siguen ocupando todo el ancho y el
/// contenido se centra con un ancho máximo legible.
abstract final class Responsive {
  /// Listas y formularios: tarjetas de una columna, cómodas de leer.
  static const listMaxWidth = 760.0;

  /// Paneles con cuadrícula (inicio del administrador).
  static const dashboardMaxWidth = 1080.0;

  /// Desde aquí se considera pantalla ancha (tablet / PC).
  static const wide = 720.0;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  /// [base] más el margen lateral que centra un contenido de [maxWidth].
  static EdgeInsets centered(
    BuildContext context,
    EdgeInsets base, {
    double maxWidth = listMaxWidth,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final extra = width > maxWidth ? (width - maxWidth) / 2 : 0.0;
    return base.copyWith(left: base.left + extra, right: base.right + extra);
  }

  /// Columnas para una cuadrícula de tarjetas de ~[itemWidth] px.
  static int columns(double width, {double itemWidth = 240, int min = 2}) {
    final n = (width / itemWidth).floor();
    return n < min ? min : n;
  }
}

/// Centra [child] con un ancho máximo, sin cambiar su alto.
class MaxWidth extends StatelessWidget {
  const MaxWidth({
    super.key,
    required this.child,
    this.maxWidth = Responsive.listMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
