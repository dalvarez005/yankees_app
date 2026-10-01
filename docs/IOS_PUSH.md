# Push en iOS: lo que falta hacer en una Mac

La configuración de iOS se dejó lista desde Linux y **no se ha compilado ni
probado**. Esto es lo que queda para quien abra el proyecto en una Mac.

## Ya configurado en el repo

- `Runner.entitlements` con `aps-environment` (capacidad de push), enlazado
  en las tres configuraciones del target Runner.
- `Info.plist`: `UIBackgroundModes` → `remote-notification`.
- `GoogleService-Info.plist` referenciado en el proyecto de Xcode (grupo
  Runner, fase Resources).
- `AppDelegate.swift`: delegado de `UNUserNotificationCenter` para mostrar
  avisos con la app abierta.
- Dart: Firebase se inicia desde `FirebasePushMessaging.create()`; no hace
  falta `FirebaseApp.configure()` en Swift. En iOS se espera el token de
  APNs antes de pedir el de FCM; si no llega, la app consulta los avisos
  cada 30 s mientras esté abierta.
- API: los push ya incluyen la configuración de APNs (sonido por defecto).

## Pendiente

1. **Copiar `GoogleService-Info.plist`** a `ios/Runner/`. No está en git
   (igual que `google-services.json`); se descarga de Firebase →
   Configuración del proyecto → Tus apps → Club Yankees iOS. Sin el archivo
   la compilación falla.
2. **Llave APNs**: developer.apple.com → Certificates, Identifiers &
   Profiles → Keys → "+" → Apple Push Notifications service (APNs). Subir el
   `.p8`, el Key ID y el Team ID en Firebase → Configuración del proyecto →
   Cloud Messaging → app de Apple → Clave de autenticación de APNs. Requiere
   cuenta de Apple Developer de pago.
3. **Firma**: abrir `ios/Runner.xcworkspace`, elegir el Team en Signing &
   Capabilities y confirmar que aparece la capacidad Push Notifications (el
   App ID `com.clubyankees.yankees` debe tenerla habilitada).
4. **Compilar** con `flutter build ios` y probar en un **iPhone real**.
5. **Antes de publicar**: cambiar `aps-environment` de `development` a
   `production` en `Runner.entitlements`.

## Qué probar

Los mismos casos verificados en Android: permiso al entrar por primera vez,
aviso con la app en segundo plano, con la app abierta, con la app cerrada, y
que tocar el aviso abra Notificaciones.
