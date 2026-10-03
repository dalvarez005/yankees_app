import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../auth/data/app_user.dart';
import '../data/profile_review_store.dart';

/// Después de iniciar sesión: al inicio, o a confirmar datos si la cuenta
/// (de Google) todavía tiene nombre o apellido de relleno.
void enterApp(BuildContext context, AppUser user) {
  final review = ProfileReview.needed(user);
  Navigator.of(context).pushNamedAndRemoveUntil(
    review ? Routes.confirmProfile : Routes.home,
    (_) => false,
    arguments: user,
  );
}
