import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
              SafeArea(
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
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.sports_baseball_rounded,
            color: AppColors.navy,
            size: 26,
          ),
        ),
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
