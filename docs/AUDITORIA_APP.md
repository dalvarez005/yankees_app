# Auditoría de la app (octubre 2026)

Estado de la app Flutter `yankees` al 4 de octubre de 2026: tamaño, funcionalidad,
arquitectura y buenas prácticas. Lo marcado **Hecho** se corrigió en el mismo cambio;
el resto queda priorizado para decidir.

## 1. Tamaño del APK

| Entrega | Antes | Ahora |
| --- | --- | --- |
| APK universal (3 arquitecturas, librerías sin comprimir) | 90.5 MB | — |
| `app-arm64-v8a-release.apk` (teléfonos actuales) | — | **16.1 MB** |
| `app-armeabi-v7a-release.apk` (teléfonos viejos de 32 bits) | — | 14.7 MB |

Qué ocupaba el espacio (por arquitectura): motor de Flutter 11.7 MB, OCR de ML Kit
11.1 MB, código Dart 6.5 MB, todo guardado sin comprimir y repetido para arm64, armv7 y
x86_64 (este último solo sirve para emuladores).

- **Hecho:** un APK por arquitectura (`--split-per-abi`), código ofuscado
  (`--obfuscate --split-debug-info=build/symbols`) y librerías nativas comprimidas
  (`packaging.jniLibs.useLegacyPackaging = true`). Instalado ocupa más que el archivo
  descargado (se descomprime), lo normal.
- **Hecho:** la fuente Poppins va dentro de la app (`assets/fonts`, 4 pesos, ~620 KB) y
  se desactivó la descarga en tiempo de ejecución. Antes, sin internet en el primer
  arranque se veía otra fuente. Se cambió el único `w800` a `w700`.
- **Pendiente (ahorra ~11 MB por arquitectura):** el OCR usa el modelo de ML Kit
  embebido. Existe la variante que lo descarga Google Play Services la primera vez
  (`play-services-mlkit-text-recognition`). El plugin `google_mlkit_text_recognition`
  fija la variante embebida, así que requiere sustituir la dependencia nativa o hacer el
  OCR en el servidor (el API ya recibe el texto leído). Riesgo medio.
- **Para Play Store:** `flutter build appbundle`; Play entrega a cada teléfono solo su
  arquitectura.

Los símbolos para leer errores ofuscados quedan en `build/symbols` (no se suben al repo);
guardarlos por versión publicada.

## 2. Funcionalidad revisada

- **Hecho:** los administradores (SUPER_ADMIN o rol con algún permiso de admin) ya no
  ven "Mi familia" ni abren pantallas de padre desde notificaciones
  (`AppUser.managesOwnFamily`). La API tampoco les concede `hijos.gestionar_propios`
  (migración 40). Se eliminó el modo "Mi familia embebida en el panel", que solo usaban
  los admins.
- **Hecho:** username de cuentas de Google sin dominio (API, migración 40).
- **Hecho:** logo del club en ícono (Android adaptable, legado e iOS) y encabezados
  (`ClubLogo`, imagen de 77 KB decodificada al tamaño en pantalla).
- Sin errores de análisis estático; 184 tests pasan.

## 3. Arquitectura y buenas prácticas (pendiente, por prioridad)

**Alta**
1. **Firma de release con la llave de depuración** (`signingConfig = debug`). Ninguna
   actualización publicada podrá firmarse con otra llave después: crear la llave propia
   antes de repartir la app y guardarla fuera del repo.
2. **Versión fija `0.1.0+1`.** Android solo instala una actualización con `versionCode`
   mayor. Subirla en cada entrega (`version: 0.1.1+2`, …).

**Media**
3. **Archivos muy grandes:** `charge_detail_page.dart` (1.200 líneas: detalle, subida
   del comprobante, OCR, paneles), `payments_repository.dart` (640),
   `voucher_processor.dart` (620), `admin_home_page.dart` (600). Partir por pantalla /
   widget (p. ej. `upload_voucher_page.dart` aparte) facilita leer y probar.
4. **Implementaciones de prueba dentro del código de producción:** 7 repositorios
   definen `Mock…` en el mismo archivo que la versión real. Mover los mocks a
   `lib/…/data/mock/` o a `test/` (si el modo `USE_MOCK` no se usa fuera del desarrollo).
5. **Localizador de servicios con `static instance`** (12 singletons mutables:
   `AuthRepository.instance`, `PaymentsRepository.instance`, …). Funciona y los tests lo
   aprovechan, pero las dependencias son implícitas. Si la app crece, pasar a inyección
   explícita (un `AppServices` creado en `main` y entregado por `InheritedWidget` o un
   paquete como `provider`/`get_it`).
6. **Errores tragados:** 13 `catch (_)` sin registro. La mayoría son intencionales
   (cerrar sesión sin red, limpiar notificaciones); conviene al menos `debugPrint` para
   diagnosticar en desarrollo.

**Baja**
7. **Plugins con Kotlin Gradle Plugin antiguo** (`firebase_core`,
   `flutter_image_compress_common`): Flutter avisa que una versión futura dejará de
   compilarlos. Actualizar cuando publiquen versiones compatibles.
8. Dependencias: todas en uso (`exif`, `flutter_svg`, etc.); no se quitó ninguna.

## 4. Cómo generar los APK

```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
# Repartir app-arm64-v8a-release.apk (y app-armeabi-v7a-release.apk para teléfonos viejos)
```
