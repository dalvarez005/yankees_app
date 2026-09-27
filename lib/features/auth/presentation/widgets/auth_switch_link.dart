import 'package:flutter/material.dart';

import '../../../../app/app_colors.dart';

class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Wrap para que no se desborde con letra grande de accesibilidad.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: const TextStyle(color: AppColors.textMuted)),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}
