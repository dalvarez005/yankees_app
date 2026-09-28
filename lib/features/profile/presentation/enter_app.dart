import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../auth/data/app_user.dart';
import '../data/profile_review_store.dart';

/// Después de iniciar sesión: al inicio, o a confirmar datos si es el primer
/// ingreso en este dispositivo o si el nombre es de relleno.
///
/// [justRegistered]: quien se registró con el formulario acaba de escribir
/// sus datos, no hace falta pedírselos de nuevo.
Future<void> enterApp(
  BuildContext context,
  AppUser user, {
  bool justRegistered = false,
}) async {
  final store = ProfileReviewStore.instance;
  if (justRegistered) await store.markReviewed(user.id);
  final review = await store.needsReview(user);
  if (!context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil(
    review ? Routes.confirmProfile : Routes.home,
    (_) => false,
    arguments: user,
  );
}
