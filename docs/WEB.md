# Versión web (PWA para iPhone)

La misma app de Flutter compilada para el navegador. En iPhone se abre en
Safari y se agrega a la pantalla de inicio: queda con el logo y a pantalla
completa. Android sigue usando el APK.

## Qué cambia respecto del APK

| | APK (Android) | Web |
| --- | --- | --- |
| Leer boleta y fecha del comprobante | En el teléfono (ML Kit) | En la API (`POST /api/Payment/ReadVoucher`, Tesseract) |
| Foto que se sube | WebP comprimido | La del navegador, achicada al elegirla (máx. 2400 px) |
| Iniciar sesión con Google | Botón propio | Botón oficial de Google (requiere autorizar el dominio, abajo) |
| Notificaciones del sistema | Sí (push FCM) | Push FCM web: se activan con el botón "Activar" del inicio; en iPhone solo con la app agregada a inicio (iOS 16.4+) |

El resto (pantallas, permisos, cobros, hijos, categorías, recuperar contraseña,
WhatsApp) es el mismo código.

## Rendimiento

- **Service worker propio** (`web/sw.js`): guarda la app en el teléfono. El
  código (index, `main.dart.js`) se pide primero a la red, así una versión
  nueva llega al recargar; motor gráfico, fuentes e íconos se sirven de lo
  guardado y se refrescan en segundo plano. Después de la primera visita la
  app abre sin descargar el motor (~7 MB) y funciona sin internet hasta la
  pantalla de inicio de sesión.
- **Motor gráfico desde nuestro dominio** (`web/flutter_bootstrap.js`,
  `canvasKitBaseUrl`), no desde `gstatic.com`.
- **nginx** (`deploy/web/nginx.conf`): gzip, y 30 días de caché para
  `canvaskit/`, `assets/` e `icons/`; el resto se revalida en cada visita.
- **Pantalla de carga** con el logo mientras arranca.
- **WebAssembly (`--wasm`)**: es más rápido y la app ya es compatible, pero no
  se pudo verificar que dibuje en el navegador de pruebas (sin GPU). Probarlo
  en un teléfono real antes de publicarlo:
  `flutter build web --release --wasm`. Los navegadores que no lo soportan
  usan la versión JavaScript automáticamente.

En pantallas anchas (PC, tablet) la app se muestra como una columna centrada
del ancho de un teléfono (`WideScreenFrame`).

## Probar en la PC

Contra la API del servidor (acepta `http://localhost:<puerto>` porque
`Cors__AllowLocalhost=true` en el servidor de pruebas):

```bash
flutter build web --release
cd build/web && python3 -m http.server 5180   # abrir http://localhost:5180
# Reiniciar el servidor después de cada build: flutter borra y recrea build/web.
```

o con recarga en caliente: `CHROME_EXECUTABLE=/usr/bin/chromium flutter run -d chrome --web-port 5180`.

No usar el puerto 5555: lo ocupa el emulador de Android.

## Publicar en el servidor

Imagen Docker con nginx y la app ya compilada (`deploy/web/Dockerfile`). Un
solo comando desde la PC compila, arma la imagen para el servidor ARM, la
envía y reinicia:

```bash
deploy/web/deploy.sh orangepi@192.168.1.77 linux/arm64
```

En el servidor queda `~/yankees-web/compose.yaml`; el contenedor se reinicia
solo si se cae o se reinicia el servidor, usa ~5 MB de memoria (límite 64 MB)
y tiene healthcheck. La imagen pesa ~94 MB (la mayoría es el motor gráfico de
Flutter). Volver atrás: volver a correr el script desde el commit anterior.

## Configuración pendiente (una vez)

1. **Cloudflare:** en el túnel, agregar el hostname público
   `yankees.quantis.site` → `http://localhost:5180`. La API ya acepta ese
   origen (`Cors__AllowedOrigins__0` en `~/yankees-api/.env`); si se usa otro
   dominio, cambiarlo ahí y reiniciar la API.
2. **Google Cloud Console** → Credenciales → client id **web**
   (`619026017478-6ceh…`) → *Orígenes autorizados de JavaScript*: agregar
   `https://yankees.quantis.site` y, para pruebas, `http://localhost:5180`.
   Sin esto el botón de Google no aparece en web (correo y contraseña sí
   funcionan).
3. **Push en el navegador:** configurado (app web de Firebase en
   `lib/core/notifications/firebase_web_options.dart`, clave VAPID en
   `Env.firebaseVapidKey`, `web/firebase-messaging-sw.js`). La API necesita
   `Push__WebAppUrl=https://yankees.quantis.site` para que tocar el aviso abra la app.