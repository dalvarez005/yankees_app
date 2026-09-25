# Yankees App

App móvil (Android / iOS) del Club Yankees para gestión de pagos: los padres o tutores ven a sus hijos inscritos, cuánto deben y suben los comprobantes (bouchers) de pago; los administradores gestionan inscripciones y validan pagos.

Este repositorio es **solo el frontend en Flutter**. La API la desarrolla otro equipo.

## Requisitos
- Flutter 3.47+ (Dart 3.13+)
- Android SDK / emulador (Android Studio)
- Para compilar iOS se necesita macOS con Xcode

## Correr el proyecto
```bash
flutter pub get
flutter run
```

## Estructura
```
lib/
  app/                     tema, colores y rutas
  features/
    auth/
      data/                modelo de usuario y AuthRepository (contrato + mock)
      presentation/        login, registro, validadores y widgets
    home/                  pantalla temporal post-login
```

## Backend
Las pantallas no llaman a la API directamente: usan `AuthRepository` (`lib/features/auth/data/auth_repository.dart`).
Hoy está activo `MockAuthRepository` con datos en memoria. Para conectar la API real, crear una implementación de `AuthRepository` y asignarla en `AuthRepository.instance`.

### Usuarios de prueba (mock)
| Correo | Contraseña | Rol |
|---|---|---|
| admin@yankees.com | admin123 | Administrador |
| padre@yankees.com | padre123 | Padre / tutor |

## Ramas
- `master`: versión estable
- `develop`: integración del desarrollo en curso
