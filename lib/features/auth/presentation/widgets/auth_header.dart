import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/layout/responsive.dart';

import '../../../../core/widgets/club_logo.dart';

import 'package:flutter/services.dart';

import '../../../../app/app_colors.dart';
import '../../../../core/widgets/app_ui.dart';

/// Cabecera azul marino con curva inferior y logo del club.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Íconos de la barra de estado en blanco sobre el fondo azul.
      value: SystemUiOverlayStyle.light,
      child: ClipPath(
        clipper: BrandCurveClipper(),
        child: Container(
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
              // Costuras decorativas estilo pelota de béisbol.
              Positioned(
                right: -70,
                top: -40,
                child: BaseballStitches(size: 220),
              ),
              Positioned(
                left: -60,
                bottom: 10,
                child: BaseballStitches(size: 140),
              ),
              // En PC el texto se alinea con el formulario centrado.
              MaxWidth(
                maxWidth: 480,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 44,
                          child: showBack ? const _BackButton() : null,
                        ),
                        const _ClubBadge(),
                        const SizedBox(height: 28),
                        Text(
                          title,
                          style: text.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 56),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón atrás estilo iOS: chevron + "Atrás", arriba a la izquierda.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        padding: const EdgeInsets.only(right: 12),
        minimumSize: const Size(44, 44),
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 4),
            Text('Atrás', style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
      ),
    );
  }
}

class _ClubBadge extends StatelessWidget {
  const _ClubBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ClubLogo(size: 64),
        const SizedBox(width: 12),
        Text(
          'CLUB YANKEES',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

/// Pantallas de acceso (ingresar, registrarse, recuperar): en teléfono el
/// encabezado va arriba del formulario; en PC, a dos columnas, con la marca a
/// la izquierda y el formulario a la derecha.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.header, required this.child});

  final AuthHeader header;
  final Widget child;

  /// Desde este ancho se usan dos columnas.
  static const splitWidth = 900.0;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < splitWidth) {
      return SingleChildScrollView(child: Column(children: [header, child]));
    }
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Container(
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
                  right: -90,
                  top: -60,
                  child: BaseballStitches(size: 320),
                ),
                const Positioned(
                  left: -80,
                  bottom: -40,
                  child: BaseballStitches(size: 260),
                ),
                if (header.showBack)
                  const Positioned(left: 32, top: 24, child: _BackButton()),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ClubLogo(size: 112),
                          const SizedBox(height: 32),
                          Text(
                            'CLUB YANKEES',
                            style: text.titleSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            header.title,
                            style: text.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            header.subtitle.replaceAll('\n', ' '),
                            style: text.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
