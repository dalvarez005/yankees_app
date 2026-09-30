import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';

/// Piezas visuales compartidas: cabecera de marca, tarjetas de lista,
/// avatares, estados (pill), esqueletos de carga y estados vacíos.

// ============================================================ Marca

/// Costuras decorativas estilo pelota de béisbol (trazo blanco muy tenue).
class BaseballStitches extends StatelessWidget {
  const BaseballStitches({super.key, required this.size, this.opacity = 0.07});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _StitchesPainter(opacity));
}

class _StitchesPainter extends CustomPainter {
  _StitchesPainter(this.opacity);
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = size.width / 2;
    final center = Offset(r, r);
    canvas.drawCircle(center, r, paint);
    final seam = Rect.fromCircle(
      center: center.translate(-r * 0.9, 0),
      radius: r * 0.7,
    );
    final seam2 = Rect.fromCircle(
      center: center.translate(r * 0.9, 0),
      radius: r * 0.7,
    );
    canvas.drawArc(seam, -0.9, 1.8, false, paint);
    canvas.drawArc(seam2, 3.14 - 0.9, 1.8, false, paint);
  }

  @override
  bool shouldRepaint(covariant _StitchesPainter old) => old.opacity != opacity;
}

/// Fondo azul con degradado, costuras y curva inferior (como el login).
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.child, this.curve = true});

  final Widget child;

  /// Borde inferior curvo; sin curva queda recto para montar tarjetas encima.
  final bool curve;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyLight],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -70,
            top: -40,
            child: BaseballStitches(size: 220),
          ),
          const Positioned(
            left: -60,
            bottom: 10,
            child: BaseballStitches(size: 140),
          ),
          child,
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: curve
          ? ClipPath(clipper: BrandCurveClipper(), child: content)
          : content,
    );
  }
}

class BrandCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(0, size.height - 40)
    ..quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.55,
      size.height - 20,
    )
    ..quadraticBezierTo(
      size.width * 0.85,
      size.height - 38,
      size.width,
      size.height - 10,
    )
    ..lineTo(size.width, 0)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Barra superior de las pantallas internas: azul, atrás estilo iOS.
AppBar pageAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) => AppBar(
  backgroundColor: AppColors.navy,
  foregroundColor: Colors.white,
  systemOverlayStyle: SystemUiOverlayStyle.light,
  leading: IconButton(
    tooltip: 'Atrás',
    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
    onPressed: () => Navigator.of(context).maybePop(),
  ),
  title: Text(title),
  actions: actions,
);

// ============================================================ Avatares y pills

/// Paleta sobria para avatares; el color sale del texto, así cada persona
/// mantiene el mismo color en todas las listas.
const _avatarPalette = [
  AppColors.navy,
  Color(0xFF0F766E),
  Color(0xFFB45309),
  Color(0xFF6D28D9),
  Color(0xFFBE123C),
  Color(0xFF0369A1),
  Color(0xFF15803D),
];

Color avatarColor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

/// Iniciales (o ícono) sobre un fondo suave del color de la persona.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.seed,
    this.initials,
    this.icon,
    this.size = 46,
    this.muted = false,
  });

  final String seed;
  final String? initials;
  final IconData? icon;
  final double size;

  /// Gris: registros inactivos.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.textMuted : avatarColor(seed);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: icon != null
          ? Icon(icon, color: color, size: size * 0.5)
          : Text(
              initials ?? '',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.34,
              ),
            ),
    );
  }
}

enum PillTone { brand, success, danger, warning, neutral }

/// Etiqueta corta de estado o rol.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.tone = PillTone.neutral,
    this.icon,
    this.filled = false,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;

  /// Fondo sólido (para destacar, p. ej. el super admin).
  final bool filled;

  Color get _color => switch (tone) {
    PillTone.brand => AppColors.navy,
    PillTone.success => AppColors.success,
    PillTone.danger => AppColors.error,
    PillTone.warning => const Color(0xFFB45309),
    PillTone.neutral => AppColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? _color : _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ Listas

/// Tarjeta de una fila de lista: avatar, título, detalle y acción.
class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.footer,
    this.trailing,
    this.onTap,
    this.dimmed = false,
    this.subtitleLines = 1,
  });

  final Widget leading;
  final String title;
  final String? subtitle;

  /// Líneas visibles del detalle (se corta con "…").
  final int subtitleLines;

  /// Fila extra debajo (pills, progreso…).
  final Widget? footer;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Registros inactivos: fondo y texto apagados.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: dimmed ? AppColors.background : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: dimmed ? AppColors.textMuted : AppColors.text,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: subtitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: 8),
                        footer!,
                      ],
                    ],
                  ),
                ),
                trailing ??
                    (onTap == null
                        ? const SizedBox(width: 8)
                        : const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textMuted,
                            ),
                          )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Título de grupo en una lista ("ACTIVAS · 5").
class ListHeader extends StatelessWidget {
  const ListHeader(this.label, {super.key, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
    child: Text(
      count == null ? label.toUpperCase() : '${label.toUpperCase()} · $count',
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    ),
  );
}

/// Tarjetas grises que laten mientras carga una lista.
class ListSkeleton extends StatefulWidget {
  const ListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  State<ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<ListSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.border,
      borderRadius: BorderRadius.circular(6),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: Column(
        children: [
          for (var i = 0; i < widget.count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(i.isEven ? 150 : 120, 12),
                      const SizedBox(height: 8),
                      _bar(i.isEven ? 190 : 160, 10),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Ícono grande, título, explicación y (opcional) un botón.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon = Icons.add_rounded,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 46, color: AppColors.navy),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel!),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error de carga con botón para reintentar.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'No pudimos cargar la información',
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_rounded,
    title: title,
    message: message,
    actionLabel: 'Reintentar',
    actionIcon: Icons.refresh_rounded,
    onAction: onRetry,
  );
}

/// Contenido de una lista con carga/erro/vacío resueltos, desplazable para
/// que "deslizar para actualizar" funcione siempre.
class AsyncListView extends StatelessWidget {
  const AsyncListView({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.children,
    this.empty,
    this.header,
    this.hero,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 100),
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final List<Widget> children;

  /// Se muestra si no hay [children].
  final Widget? empty;

  /// Siempre visible arriba (buscador, resumen…).
  final Widget? header;

  /// Arriba de todo y a lo ancho, sin [padding] (cabecera de marca).
  final Widget? hero;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = [
      ?header,
      if (loading && error == null)
        const ListSkeleton()
      else if (loading)
        ErrorState(message: error!, onRetry: onRetry)
      else if (children.isEmpty)
        ?empty
      else
        ...children,
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: hero == null ? padding : EdgeInsets.zero,
      children: hero == null
          ? body
          : [
              hero!,
              Padding(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            ],
    );
  }
}
