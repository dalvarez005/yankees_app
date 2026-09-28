import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../app/routes.dart';
import '../../auth/data/app_user.dart';
import '../../auth/data/auth_repository.dart';
import 'profile_form.dart';

/// "Mi perfil": ver y editar nombres y apellidos. Devuelve el usuario
/// actualizado al cerrar (o null si no cambió).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.user});

  final AppUser user;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late AppUser _user = widget.user;
  AppUser? _updated;
  // Cambia al recargar el perfil para que el formulario tome los datos nuevos.
  var _formVersion = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await AuthRepository.instance.fetchProfile();
      if (!mounted) return;
      setState(() {
        _user = fresh;
        _formVersion++;
      });
    } on AuthException {
      // Sin conexión se muestran los datos guardados en la sesión.
    }
  }

  Future<String?> _save(ProfileInput input) async {
    try {
      final updated = await AuthRepository.instance.updateProfile(input);
      if (!mounted) return null;
      setState(() => _user = _updated = updated);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Tus datos se actualizaron.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.navy,
          ),
        );
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<void> _signOut() async {
    await AuthRepository.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_updated);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Atrás',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(_updated),
          ),
          title: const Text('Mi perfil'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                        child: Text(
                          _user.initials,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _user.legalName.isEmpty ? _user.email : _user.legalName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 28),
                    ProfileForm(
                      key: ValueKey(_formVersion),
                      user: _user,
                      submitLabel: 'Guardar cambios',
                      onSubmit: _save,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Cerrar sesión'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
