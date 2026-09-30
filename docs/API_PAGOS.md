# Contrato v2: cuotas, validación de usuarios, comprobantes y solvencia

> Fuente de verdad compartida entre la API (`YankeesManagement.Api`) y la app (`yankees`).
> Si algo cambia, se cambia **aquí primero**. Convenciones de siempre:
> - Respuestas con `responseCode` (`"00"` = ok) y `responseMessage`; errores con `message`.
> - Códigos: `05` → 401 (sesión), `03` → 403 (sin permiso), `30`/`39` → 400, `96` → 500.
> - Paginación `page` / `pageSize` (máximo 100) → `{ page, pageSize, hasNext, totalRecords? }`.
> - Funciones SQL con `responsecode` y `response_message`, sin FKs físicas.
> - Permisos con `RequirePermission` en C# **y** `fn_has_permission` en SQL.
> - Fechas en ISO-8601 UTC; fechas sin hora como `yyyy-MM-dd`; montos en `numeric(10,2)` (en JSON, número).
> - Moneda: quetzales (GTQ).

---

## 1. Reglas de negocio

### 1.1 Roles y permisos
- **Un solo SUPER_ADMIN.** Se define **solo por base de datos** con `SELECT * FROM fn_set_super_admin('correo@x.com')`: degrada al anterior al rol 1 y deja registro en `user_role_audit`.
  - La API **nunca** puede asignar ni quitar el rol SUPER_ADMIN. `UpdateUserRole` con el rol SUPER_ADMIN → `03 NO SE PUEDE ASIGNAR SUPER_ADMIN`.
  - Un trigger impide que haya más de un usuario activo con ese rol.
- **SUPER_ADMIN tiene todos los permisos, incluidos los futuros.**
- **Crear y editar roles y asignarles permisos: solo SUPER_ADMIN.** Se valida con `fn_is_super_admin`, no con un permiso. Por eso **se elimina el permiso `roles.gestionar`**.
- **Catálogo final de permisos** (tabla `permission`):

| Código | Módulo | Qué permite |
|---|---|---|
| `usuarios.ver` | Usuarios | Ver usuarios, su rol y su estado |
| `usuarios.gestionar` | Usuarios | Cambiar rol (excepto SUPER_ADMIN) y activar/desactivar |
| `usuarios.validar` | Usuarios | Validar usuarios nuevos y definir o editar sus cuotas |
| `categorias.gestionar` | Categorías | Crear, editar, desactivar y reactivar categorías |
| `jugadores.ver` | Jugadores | Ver todos los hijos por categoría |
| `pagos.validar` | Pagos | Aprobar o rechazar comprobantes |
| `pagos.gestionar` | Pagos | Ver todos los cobros, anular, ver insolventes y reportes, notificar insolventes |
| `configuracion.gestionar` | Configuración | Cuotas por defecto, día límite de pago y WhatsApp de contacto |
| `hijos.gestionar_propios` | Familia | Gestionar sus propios hijos y pagos |

- Se eliminan `roles.gestionar` y `pagos.asignar`, junto con sus filas en `role_permission`.

### 1.2 Alta y validación de usuarios
- Todo usuario nuevo (registro por correo o por Google) queda con **perfil de cobro pendiente**: `billing_profile.status = 'P'`.
- Mientras esté en `P`, la app muestra **"Estamos configurando tu perfil"** y no deja avanzar. En la API, los endpoints de familia y pagos del padre responden `03 PERFIL PENDIENTE DE VALIDACION`. `/me`, logout y notificaciones siguen funcionando.
- **Exentos:** los usuarios cuyo rol tiene al menos un permiso de administración (cualquiera distinto de `hijos.gestionar_propios`), y SUPER_ADMIN. Para ellos `billing.status = 'N'` (no aplica) y no se les cobra.
- Al crearse un perfil `P`, se envía una notificación `USER_PENDING_VALIDATION` a **todos** los usuarios activos con `usuarios.validar`.
- **Validar** (con `usuarios.validar`): se definen `enrollmentFee` (inscripción, > 0) y `monthlyFee` (mensualidad, > 0).
  - Los valores sugeridos son los de configuración por defecto.
  - El perfil pasa a `A`.
  - Se crea **en ese momento** el cobro de **inscripción**, que vence a los `dueDay` días de la validación (por defecto, a los 15 días).
  - La primera **mensualidad** se genera el día 1 del mes siguiente.
  - Se notifica al usuario (`USER_VALIDATED`).
- **Editar cuotas** (con `usuarios.validar`):
  - La mensualidad nueva aplica **desde el próximo período**; los cobros ya generados no cambian.
  - La inscripción solo se puede cambiar si su cobro sigue en `P` o `X`, y se actualiza el monto de ese cobro.
- Usuarios existentes al migrar: los que no son exentos quedan en `P`, y los exentos en `N`.

### 1.3 Cobros
- **Dos tipos:** `I` = inscripción (una vez por usuario) y `M` = mensualidad (una por usuario y por período `YYYY-MM`).
- Los cobros son **por usuario (familia)**, no por hijo.
- Estados del cobro:
  - `P`: por pagar.
  - `R`: comprobante en revisión.
  - `X`: comprobante rechazado; se puede subir otro.
  - `A`: pagado.
  - `C`: anulado.
- **Mensualidad automática:**
  - Un `BackgroundService` en la API corre al iniciar y cada hora, y llama a `fn_generate_monthly_charges(p_today date)`.
  - Desde el día 1 de cada mes crea el cobro `M` del período actual para cada usuario con perfil `A` y `monthly_fee > 0`, con `amount = monthly_fee` vigente y `due_date` = día `dueDay` del mes (por defecto el 15).
  - Es **idempotente**: índice único `(users_id, type, period)`.
  - Notifica `CHARGE_CREATED` al usuario.
- **Pago en tiempo:** el comprobante se subió en `due_date` o antes, y luego se aprobó (`paidOnTime = true`).
- **Insolvente:** el usuario tiene al menos un cobro en `P` o `X` con `due_date < hoy`.
  - Un cobro en `R` **no** hace insolvente: el padre ya pagó a tiempo y está en revisión.
  - Si después se rechaza y ya venció, pasa a insolvente.
  - Se calcula en las consultas, sin guardar un flag, con la función `fn_is_insolvent(user_id)` y una vista para los reportes.

### 1.4 Comprobantes (`journal_payment`)
Se reutiliza la tabla existente `journal_payment` y se completa. Está vacía, así que se puede alterar.

| Columna | Origen | Notas |
|---|---|---|
| `id` | API | GUID sin guiones (varchar 44, como los demás ids) |
| `users_id` | token | Dueño |
| `charge_id` | request | **Nueva**. Cobro que paga |
| `description` | **padre (obligatorio)** | 5 a 250 caracteres, p. ej. "Depósito Banrural mensualidad octubre" |
| `amount` | **padre (obligatorio)** | Tiene que ser **igual** al monto del cobro; si no → `30 MONTO NO COINCIDE CON EL COBRO`. Cambiar el tipo `money` a `numeric(10,2)` |
| `bank_reference` | **padre (obligatorio)** | Número de boleta o transferencia, 4 a 60 caracteres, alfanumérico con guiones. **Único** entre los comprobantes no rechazados → `30 REFERENCIA YA UTILIZADA` |
| `payment_date` | **padre (obligatorio)** | **Nueva**. Fecha del depósito, que no puede ser futura |
| `file_hash` | API | SHA-256 (hex) de los bytes **recibidos**. Repetido → `30 COMPROBANTE DUPLICADO` |
| `perceptual_hash` | API | dHash de 64 bits (16 caracteres hex) de la imagen decodificada. Si la distancia de Hamming con cualquier comprobante previo es ≤ 6 → `30 COMPROBANTE DUPLICADO` |
| `ocr_fingertip` | API | SHA-256 del texto OCR **normalizado** (mayúsculas, sin espacios ni signos). El OCR lo hace la app (ML Kit) y lo manda como `ocrText`. Si el texto normalizado tiene 20 caracteres o más y coincide con otro → `30 COMPROBANTE DUPLICADO`. Sin texto útil, se guarda el hash del texto vacío y no se compara |
| `status` | API | `R` en revisión, `A` aprobado, `X` rechazado |
| `storage_key`, `content_type`, `file_size` | API | **Nuevas**. Archivo guardado |
| `suspected_edit`, `edit_signals` | app + API | **Nuevas**. Indicios de edición, que se le muestran al validador |
| `review_comment`, `reviewed_by`, `review_datetime` | API | **Nuevas**. El comentario es obligatorio si se rechaza (10 a 500 caracteres) |
| `create_datetime`, `update_datetime` | API | |

- **Compresión:**
  - **App:** comprime al máximo razonable antes de subir: WebP, lado mayor 1280 px, calidad 55, sin metadatos. La meta es que pese 250 KB o menos.
  - **API:** vuelve a codificar a WebP (lado mayor 1280 px, calidad 50) con SkiaSharp, sin metadatos, y guarda solo esa versión. El archivo recibido no puede pasar de **2 MB** → `30 ARCHIVO DEMASIADO GRANDE`. Tipos aceptados, verificados por *magic bytes*: JPEG, PNG y WebP → `30 ARCHIVO NO VALIDO`.
- **Imagen editada** (heurística, **no es infalible**):
  - La app lee el EXIF del **original, antes de comprimir** y manda `editSignals` (texto separado por `;`) si detecta:
    - que el campo `Software` menciona un editor (Photoshop, GIMP, Snapseed, Lightroom, PicsArt, Canva, Pixlr, Fotor, Editor…);
    - que `DateTimeOriginal` y `DateTime` no coinciden;
    - dimensiones atípicas.
  - La API también revisa los metadatos del archivo recibido, por si llegaran. Si hay señales, marca `suspected_edit = true`: **no rechaza**, pero el validador ve la advertencia.
- Al subir: se guarda el comprobante en `R`, el cobro pasa a `R`, y se notifica `VOUCHER_SUBMITTED` a quienes tienen `pagos.validar`.
- Al revisar:
  - Si se aprueba: el comprobante y el cobro quedan en `A`, se guarda `paid_datetime` y `paid_on_time`, y se notifica `VOUCHER_APPROVED`.
  - Si se rechaza: el comprobante y el cobro quedan en `X` con el comentario, y se notifica `VOUCHER_REJECTED`.
- El archivo se guarda en disco, en `Storage:VoucherPath` (appsettings, fuera de `wwwroot`), con nombre `{id}.webp`. Solo se sirve por `GetVoucherFile` con autorización.

### 1.5 Notificaciones (in-app)
- Tabla `notification`: `id`, `users_id`, `type`, `title`, `body`, `data` (jsonb), `create_datetime`, `read_datetime`.
- Tipos:
  - `USER_PENDING_VALIDATION`: `data {userId}`.
  - `USER_VALIDATED`.
  - `CHARGE_CREATED`: `data {chargeId}`.
  - `VOUCHER_SUBMITTED`: `data {voucherId, chargeId}`.
  - `VOUCHER_APPROVED` y `VOUCHER_REJECTED`: `data {chargeId}`.
  - `PAYMENT_REMINDER`: `data {overdueAmount}`.
- Push (FCM) queda **para una fase siguiente**, porque requiere un proyecto de Firebase. Las tablas y los tipos ya sirven para eso.

### 1.6 Recordatorio a insolventes
- Con `pagos.gestionar` se notifica a todos los insolventes o a los que se seleccionen.
- Máximo **un recordatorio por usuario cada 24 h**; los demás se cuentan como `skipped`.
- El mensaje por defecto indica el monto vencido; el admin puede agregar un texto de hasta 300 caracteres.

---

## 2. Configuración (tabla `parameter`, `type_parameter` = "PAGOS")

| Clave | Por defecto | Uso |
|---|---|---|
| `DEFAULT_ENROLLMENT_FEE` | `0` | Sugerido al validar |
| `DEFAULT_MONTHLY_FEE` | `0` | Sugerido al validar |
| `PAYMENT_DUE_DAY` | `15` | Día límite de la mensualidad (1 a 28) y días para pagar la inscripción |
| `WHATSAPP_NUMBER` | `''` | Contacto si se rechaza un comprobante |
| `WHATSAPP_CONTACT_NAME` | `Tesorería del club` | |

---

## 3. Endpoints

### 3.1 Perfil
`GET /api/User/me` agrega el objeto `billing`:
```json
"billing": {
  "status": "P",
  "enrollmentFee": 250.00,
  "monthlyFee": 150.00,
  "solvent": true,
  "overdueAmount": 0.00
}
```
- `status` es `P`, `A` o `N`.
- Con `P` o `N`, los montos pueden ser `null`.

### 3.2 Validación de usuarios (`usuarios.validar`)

| Método | Ruta | Request → Response |
|---|---|---|
| GET | `/api/Billing/GetPendingUsers?page=1&pageSize=50&search=` | `{ userData: [{ userId, email, firstName, firstLastName, createdAt, dependentsCount }] }`, los más antiguos primero |
| POST | `/api/Billing/ValidateUser` | `{ userId, enrollmentFee, monthlyFee }` → `{ billingData }` |
| POST | `/api/Billing/UpdateUserFees` | `{ userId, enrollmentFee?, monthlyFee? }` → `{ billingData }` |
| GET | `/api/Billing/GetUserBilling/{userId}` | `{ billingData }` |

`billingData`:
```json
{
  "userId": "…",
  "status": "A",
  "enrollmentFee": 250.0,
  "monthlyFee": 150.0,
  "approvedBy": "Diego Alvarez",
  "approvedAt": "…",
  "solvent": false,
  "overdueAmount": 150.0
}
```

Errores:
- `39 USUARIO NO EXISTE`
- `30 USUARIO YA VALIDADO`
- `30 USUARIO NO REQUIERE VALIDACION` (exento)
- `30 MONTO INVALIDO` (debe ser > 0 y ≤ 100000)
- `30 INSCRIPCION YA PAGADA` (si se edita la inscripción con el cobro en `R` o `A`)

### 3.3 Configuración

| Método | Ruta | Permiso | Body / respuesta |
|---|---|---|---|
| GET | `/api/Settings/GetPaymentSettings` | cualquier usuario autenticado | `{ settingsData: { defaultEnrollmentFee, defaultMonthlyFee, dueDay, whatsappNumber, contactName } }` |
| POST | `/api/Settings/UpdatePaymentSettings` | `configuracion.gestionar` | El mismo objeto; todos los campos son opcionales |

Validaciones:
- `dueDay` entre 1 y 28.
- Los montos ≥ 0.
- `whatsappNumber`: solo dígitos, entre 8 y 15, o vacío.
- `contactName` hasta 60 caracteres.
- Error: `30 CONFIGURACION INVALIDA`.

### 3.4 Pagos del padre (`hijos.gestionar_propios` y perfil `A`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Payment/GetMyCharges` | `{ chargeData: Charge[] }`, sin los anulados, del más reciente al más antiguo |
| GET | `/api/Payment/GetMyBalance` | `{ balanceData: { solvent, totalOwed, overdueAmount, inReviewAmount, nextDueDate } }` |
| POST | `/api/Payment/UploadVoucher` | multipart, ver abajo → `{ chargeData: Charge }` |
| GET | `/api/Payment/GetVoucherFile/{voucherId}` | `image/webp`; solo el dueño o alguien con `pagos.validar` |

`UploadVoucher` es `multipart/form-data` con:
- `chargeId`, `amount` (con punto decimal), `bankReference`, `description` y `paymentDate`, todos obligatorios.
- `ocrText` (opcional, hasta 4000 caracteres), `editSignals` (opcional, hasta 500).
- `file`.

Errores:
- `39 COBRO NO EXISTE`
- `30 COBRO YA TIENE COMPROBANTE EN REVISION`
- `30 COBRO YA PAGADO`
- `30 MONTO NO COINCIDE CON EL COBRO`
- `30 REFERENCIA YA UTILIZADA`
- `30 COMPROBANTE DUPLICADO`
- `30 ARCHIVO NO VALIDO`
- `30 ARCHIVO DEMASIADO GRANDE`
- `30 FECHA DE PAGO INVALIDA`
- `30 DATOS DEL COMPROBANTE INCOMPLETOS`
- `03 PERFIL PENDIENTE DE VALIDACION`

**`Charge`:**
```json
{
  "chargeId": "…", "userId": "…", "type": "M", "concept": "Mensualidad octubre 2026",
  "period": "2026-10", "amount": 150.00, "dueDate": "2026-10-15",
  "status": "P", "overdue": false, "createdAt": "…", "paidAt": null, "paidOnTime": null,
  "parentName": "Luis Istacuy", "parentEmail": "…",
  "voucher": {
    "voucherId": "…", "status": "R", "uploadedAt": "…", "fileUrl": "/api/Payment/GetVoucherFile/…",
    "amount": 150.00, "bankReference": "889231", "description": "…", "paymentDate": "2026-10-03",
    "suspectedEdit": false, "editSignals": null,
    "reviewComment": null, "reviewedAt": null, "reviewedBy": null
  }
}
```
- `concept` lo arma la API: "Inscripción" o "Mensualidad {mes} {año}", con el mes en español.
- `parentName` y `parentEmail` solo en los endpoints de admin.
- `voucher` es el **último** comprobante, o `null` si no hay.

### 3.5 Validación de comprobantes (`pagos.validar`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Payment/GetPendingReviews?page=1&pageSize=50` | Cobros en `R` con su `voucher`, `parentName` y `parentEmail`, los más antiguos primero |
| POST | `/api/Payment/ReviewVoucher` | `{ voucherId, decision: "A" \| "X", comment? }` → `{ chargeData }`. Errores: `30 COMENTARIO OBLIGATORIO`, `30 COMPROBANTE YA REVISADO` |

### 3.6 Gestión de pagos (`pagos.gestionar`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Payment/GetChargeData?status=&type=&period=&search=&page=1&pageSize=50` | Todos los cobros → `{ chargeData, page, pageSize, hasNext }` |
| POST | `/api/Payment/CancelCharge` | `{ chargeId }` → `{ chargeData }`. Si ya está pagado → `30 NO SE PUEDE ANULAR UN COBRO PAGADO`. Si tenía un comprobante en `R`, queda en `X` con el comentario "Cobro anulado por el club" |
| GET | `/api/Payment/GetInsolventUsers?categoryId=&search=&page=1&pageSize=50` | `{ userData: [{ userId, name, email, overdueAmount, overdueCharges, oldestDueDate, lastReminderAt, dependents: [{ name, categoryId, categoryName }] }], page, pageSize, hasNext, totalRecords }`. `categoryId` filtra a los usuarios con al menos un hijo en esa categoría |
| POST | `/api/Payment/NotifyInsolvents` | `{ userIds?: string[], message? }`. Con `userIds` en `null` notifica a todos los insolventes → `{ notifiedCount, skippedCount }` |
| GET | `/api/Payment/GetSolvencyReport` | `{ reportData: { period, approvedUsers, solventUsers, insolventUsers, pendingValidationUsers, overdueAmount, collectedThisPeriod, inReviewAmount } }` |

### 3.7 Notificaciones (cualquier usuario autenticado, solo las suyas)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Notification/GetMyNotifications?page=1&pageSize=30&unreadOnly=false` | `{ notificationData: [{ notificationId, type, title, body, data, createdAt, readAt }], unreadCount, hasNext }` |
| POST | `/api/Notification/MarkAsRead` | `{ notificationIds?: string[], all?: bool }` → `{ unreadCount }` |

### 3.8 Jugadores (`jugadores.ver`; antes era solo SUPER_ADMIN)
`GET /api/Dependent/GetDependentDataByCategory?categoryId=&search=&page=1&pageSize=100`
- Se **agregan** a cada elemento: `dependentId`, `parentUserId`, `parentName` y `parentSolvent` (bool, o `null` si el padre está exento o pendiente).
- `search` busca por nombre o CUI; `categoryId` es opcional.

### 3.9 Roles
- `Role/*`, `Permission/*`, `Role/UpdateRolePermissions` y `Role/GetRolePermissions`: **solo SUPER_ADMIN**. Con cualquier otro rol → `03`.
- `User/UpdateUserRole` y `User/GetUserData`: se mantienen con `usuarios.gestionar` y `usuarios.ver`. Asignar el rol SUPER_ADMIN → `03 NO SE PUEDE ASIGNAR SUPER_ADMIN`.
- `GetRolePermissions` devuelve el rol SUPER_ADMIN marcado; la app no lo ofrece para asignar.

---

## 4. Seguridad
- El padre solo ve lo suyo: se filtra siempre por el `userId` del token.
- Los archivos se validan por *magic bytes* y se vuelven a codificar, y se sirven con `X-Content-Type-Options: nosniff`.
- Al revisar y al generar cobros se usa `FOR UPDATE` y los índices únicos.
- El OCR y las señales de edición que manda la app son **indicios**, no pruebas: el validador humano decide.
