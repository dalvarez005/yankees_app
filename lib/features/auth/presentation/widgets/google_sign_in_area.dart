import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/google_id_token_provider.dart';
import 'google_button.dart';
import 'google_web_button.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';

/// "Continuar con Google" en el teléfono (botón propio, [onPressed]) y en
/// web (botón de Google, que entrega el idToken a [onWebIdToken]).
class GoogleSignInArea extends StatefulWidget {
  const GoogleSignInArea({
    super.key,
    required this.loading,
    required this.onPressed,
    required this.onWebIdToken,
  });

  final bool loading;
  final VoidCallback? onPressed;
  final ValueChanged<String> onWebIdToken;

  @override
  State<GoogleSignInArea> createState() => _GoogleSignInAreaState();
}

class _GoogleSignInAreaState extends State<GoogleSignInArea> {
  StreamSubscription<String>? _tokens;
  late final Future<void> _ready = kIsWeb
      ? initializeGoogleSignIn()
      : Future.value();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _tokens = googleWebIdTokens().listen(
        (token) => widget.onWebIdToken(token),
        onError: (_) {},
      );
    }
  }

  @override
  void dispose() {
    unawaited(_tokens?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return GoogleButton(loading: widget.loading, onPressed: widget.onPressed);
    }
    if (widget.loading) {
      return const GoogleButton(loading: true, onPressed: null);
    }
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) =>
          snapshot.connectionState == ConnectionState.done
          ? buildGoogleWebButton(
              // Solo se ve: el clic lo atiende el botón de Google encima.
              visual: GoogleButton(loading: false, onPressed: () {}),
            )
          : const SizedBox(height: 54),
    );
  }
}
