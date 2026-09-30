# API: módulo de pagos (cobros, comprobantes y solvencia)

La app móvil ya tiene las pantallas terminadas y funcionando con datos simulados. Este documento define lo que la API tiene que exponer para conectarlas. El cliente ya está escrito contra este contrato en `lib/features/payments/data/payments_repository.dart` (`ApiPaymentsRepository`). Para probarlo contra la API se compila con `--dart-define=PAYMENTS_API=true`.

> Todo sigue las convenciones actuales de la API: `responseCode`/`responseMessage`, `typeOperation`, paginación `page`/`pageSize`, funciones de PostgreSQL con `responsecode`/`response_message`, sin FKs físicas y permisos con `RequirePermission`.

---

## 1. Flujo

```
Admin asigna cobro ──► [P] Por pagar ──(padre sube comprobante)──► [R] En revisión
                           ▲                                            │
                           │                         ┌──────────────────┴─────────────┐
                           │                  admin aprueba                  admin rechaza
                           │                         ▼                      (comentario obligatorio)
                           │                   [A] Pagado                          ▼
                           └────────(padre sube otro comprobante)────────── [X] Rechazado

Admin anula (solo P, R o X) ──► [C] Anulado (no se cobra, no se muestra al padre)
```

- **Padre:** ve lo que debe por cada hijo, sube la foto del comprobante y ve el estado. Si se lo rechazan, ve el motivo y un botón que abre WhatsApp con el número que configuró el club. Si se lo aprueban, ve su **solvencia**.
- **Admin con `pagos.asignar`:** asigna cobros a un hijo o a todos los hijos de una categoría, y puede anularlos.
- **Admin con `pagos.validar`:** revisa la foto y aprueba, o rechaza con motivo obligatorio.
- **Admin con `configuracion.gestionar`:** define el número de WhatsApp de contacto.

**Solvente** = no tiene cobros en estado `P`, `R` ni `X`. Lo que está en revisión todavía cuenta como deuda.

---

## 2. Permisos nuevos

Van a la tabla `permission` (migración 24). SUPER_ADMIN los recibe automáticamente por `fn_get_user_access`.

```sql
INSERT INTO public.permission (code, name, description, module) VALUES
  ('pagos.asignar',  'Asignar cobros',        'Asignar y anular cobros a los hijos.',                 'Pagos'),
  ('pagos.validar',  'Validar comprobantes',  'Aprobar o rechazar comprobantes de pago.',             'Pagos'),
  ('configuracion.gestionar', 'Configuración', 'Cambiar el WhatsApp de contacto y otros ajustes.',    'Configuración')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name, description = EXCLUDED.description, module = EXCLUDED.module;
```

Los endpoints del padre usan el permiso existente `hijos.gestionar_propios`.

---

## 3. Tablas sugeridas

Sin FKs físicas, como el resto del proyecto. Montos en `numeric(10,2)` y fechas en UTC.

```sql
-- Cobro asignado a un hijo.
CREATE TABLE public.charge (
    id              varchar(44) PRIMARY KEY,          -- mismo formato de id que users/dependent
    dependent_id    varchar(44) NOT NULL,
    users_id        varchar(44) NOT NULL,             -- padre dueño del hijo al momento de asignar
    concept         varchar(100) NOT NULL,
    description     varchar(250),
    amount          numeric(10,2) NOT NULL CHECK (amount > 0),
    due_date        date,
    status          varchar(1) NOT NULL DEFAULT 'P' CHECK (status IN ('P','R','X','A','C')),
    batch_id        varchar(44),                      -- agrupa los cobros creados juntos por categoría
    created_by      varchar(44) NOT NULL,
    create_datetime timestamp NOT NULL DEFAULT NOW(),
    update_datetime timestamp NOT NULL DEFAULT NOW(),
    paid_datetime   timestamp,
    cancelled_by    varchar(44)
);
CREATE INDEX ix_charge_users_status ON public.charge (users_id, status);
CREATE INDEX ix_charge_status_created ON public.charge (status, create_datetime);

-- Cada comprobante subido (historial: un cobro puede tener varios si lo rechazan).
CREATE TABLE public.payment_voucher (
    id              varchar(44) PRIMARY KEY,
    charge_id       varchar(44) NOT NULL,
    uploaded_by     varchar(44) NOT NULL,
    file_key        varchar(300) NOT NULL,            -- ruta en disco / blob; NUNCA se expone directo
    content_type    varchar(50) NOT NULL,
    file_size       integer NOT NULL,
    reference       varchar(60),                      -- nro. de boleta/transferencia (opcional)
    status          varchar(1) NOT NULL DEFAULT 'R' CHECK (status IN ('R','A','X')),
    review_comment  varchar(500),                     -- obligatorio si status = 'X'
    reviewed_by     varchar(44),
    upload_datetime timestamp NOT NULL DEFAULT NOW(),
    review_datetime timestamp
);
CREATE INDEX ix_voucher_charge ON public.payment_voucher (charge_id, upload_datetime DESC);
-- Solo un comprobante en revisión por cobro:
CREATE UNIQUE INDEX ux_voucher_one_in_review ON public.payment_voucher (charge_id) WHERE status = 'R';

-- Ajustes clave/valor (el WhatsApp de contacto y futuros).
CREATE TABLE public.app_setting (
    key             varchar(60) PRIMARY KEY,
    value           varchar(500),
    updated_by      varchar(44),
    update_datetime timestamp NOT NULL DEFAULT NOW()
);
INSERT INTO public.app_setting (key, value) VALUES
  ('payments.whatsapp_number', ''),
  ('payments.contact_name', 'Tesorería del club')
ON CONFLICT DO NOTHING;
```

---

## 4. Endpoints

Todas las respuestas llevan `responseCode` (`"00"` = éxito) y `responseMessage`. Los errores siguen el `GlobalExceptionFilter`: `05` → 401, `03` → 403 (sin permiso) y el resto → 400 con `message`.

### 4.1 Objeto `Charge` (lo usan casi todos los endpoints)

```json
{
  "chargeId": "c-8f2…",
  "dependentId": "d-1a…",
  "dependentName": "Sofía Castro",
  "categoryName": "Infantil",
  "concept": "Mensualidad de octubre",
  "description": "Incluye seguro",
  "amount": 150.00,
  "dueDate": "2026-10-15",
  "status": "P",
  "createdAt": "2026-09-29T20:10:00Z",
  "paidAt": null,
  "parentName": "Luis Istacuy",
  "parentEmail": "luis@correo.com",
  "voucher": {
    "voucherId": "v-77…",
    "status": "X",
    "uploadedAt": "2026-09-30T14:02:00Z",
    "fileUrl": "/api/Payment/GetVoucherFile/v-77…",
    "reference": "889231",
    "reviewComment": "El monto no coincide con el cobro.",
    "reviewedAt": "2026-09-30T18:40:00Z",
    "reviewedBy": "Tesorería"
  }
}
```

- `status` del cobro: `P` por pagar, `R` en revisión, `X` rechazado, `A` pagado, `C` anulado.
- `voucher` es el **último** comprobante, o `null` si nunca subió uno. Su `status` es `R`, `A` o `X`.
- `parentName` y `parentEmail` solo en endpoints de admin; en los del padre pueden omitirse.
- `reviewedBy` es un nombre para mostrar (nombre del admin o "Tesorería"), no un id.
- Fechas ISO-8601 en UTC; `dueDate` como fecha sin hora (`yyyy-MM-dd`).

### 4.2 Padre (`[Authorize]` + `hijos.gestionar_propios`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Payment/GetMyCharges` | Cobros de **sus** hijos, sin los anulados (`C`). Respuesta `{ chargeData: Charge[] }`. |
| POST | `/api/Payment/UploadVoucher` | `multipart/form-data`: `chargeId`, `reference` (opcional) y `file`. Respuesta `{ chargeData: Charge }` con el cobro ya en `R`. |
| GET | `/api/Payment/GetContactSettings` | `{ settingsData: { whatsappNumber: "50255551234", displayName: "Tesorería del club" } }` |
| GET | `/api/Payment/GetVoucherFile/{voucherId}` | Devuelve la imagen (`image/jpeg` o `image/png`). Solo el dueño del cobro o alguien con `pagos.validar`. La app la pide con `Authorization: Bearer`. |

**Reglas de `UploadVoucher`:**
- El cobro tiene que ser de un hijo **del usuario del token** (nunca confiar en ids del body). Si no → `39 COBRO NO EXISTE` (no revelar que existe).
- Solo si el cobro está en `P` o `X`:
  - Si está en `R` → `30 COBRO YA TIENE COMPROBANTE EN REVISION`.
  - Si está en `A` → `30 COBRO YA PAGADO`.
  - Si está en `C` → `39 COBRO NO EXISTE`.
- Archivo:
  - Tipo `image/jpeg` o `image/png`, verificado por los *magic bytes* y no solo por la extensión o el content-type.
  - Máximo **5 MB**.
  - Si no cumple → `30 ARCHIVO NO VALIDO` / `30 ARCHIVO DEMASIADO GRANDE`.
  - La app ya comprime a 2000 px y calidad 85 %.
- Guardar el archivo fuera de `wwwroot`, con nombre generado (GUID), nunca el nombre original. Guardar `file_key`, tipo y tamaño.
- Con un solo lock o transacción: insertar el `payment_voucher` en `R` y pasar el cobro a `R`.
- `reference`: máximo 60 caracteres, opcional.
- Rate limit: reutilizar `AuthAttempts` o crear uno de ~10/min por usuario.

`GetContactSettings`: si `whatsappNumber` está vacío, la app muestra "El club aún no configuró un número de contacto".

### 4.3 Admin: cobros (`pagos.asignar`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Payment/GetChargeData?page=1&pageSize=100&status=P&search=sofi` | Todos los cobros, más recientes primero. `status` y `search` opcionales; `search` busca en nombre del hijo, del padre y concepto. `{ page, pageSize, hasNext, chargeData: Charge[] }` |
| POST | `/api/Payment/ManageCharge` | Alta (`A`) o anulación (`D`), ver abajo. |
| GET | `/api/Dependent/GetAllDependents?search=&page=1&pageSize=30` | Para elegir a qué hijo cobrar. `{ dependentData: [{ dependentId, firstName, firstLastName, categoryId, categoryName, parentName }] }`. Busca por nombre o CUI; solo hijos activos. Permiso `pagos.asignar`. |

**Alta** a un hijo **o** a toda una categoría (exactamente uno de los dos):
```json
{
  "typeOperation": "A",
  "chargeData": {
    "concept": "Mensualidad de octubre",
    "description": "Opcional",
    "amount": 150.00,
    "dueDate": "2026-10-15",
    "categoryId": 3
  }
}
```
o con `"dependentId": "d-1a…"` en lugar de `categoryId`.

Respuesta: `{ "responseCode": "00", "createdCount": 12 }`.
- Por categoría: un cobro por cada hijo **activo** de esa categoría, todos con el mismo `batch_id`, en una sola transacción. Si la categoría no tiene hijos, `createdCount: 0`; la app avisa, no es un error.
- Validaciones:
  - `concept` entre 1 y 100 caracteres.
  - `description` hasta 250.
  - `amount` mayor a 0 y hasta 100000, con 2 decimales.
  - `dueDate` hoy o después (opcional).
  - La categoría tiene que estar activa y el hijo existir y estar activo.
- Guardar `users_id` = padre actual del hijo, para que el cobro no "salte" de dueño si luego cambia.

**Anulación:**
```json
{ "typeOperation": "D", "chargeData": { "chargeId": "c-8f2…" } }
```
- Solo si está en `P`, `R` o `X`; si está en `A` → `30 NO SE PUEDE ANULAR UN COBRO PAGADO`.
- Si tenía un comprobante en `R`, ese comprobante queda en `X` con comentario `"Cobro anulado por el club"`.

### 4.4 Admin: validación (`pagos.validar`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/Payment/GetPendingReviews?page=1&pageSize=100` | Cobros en `R` con su `voucher`, `parentName` y `parentEmail`, **más antiguos primero**. `{ page, pageSize, hasNext, chargeData: Charge[] }` |
| POST | `/api/Payment/ReviewVoucher` | Aprobar o rechazar, ver abajo. |

```json
{ "voucherId": "v-77…", "decision": "A" }
{ "voucherId": "v-77…", "decision": "X", "comment": "El monto no coincide con el cobro." }
```
Respuesta: `{ chargeData: Charge }` actualizado.
- `decision` es `A` (aprobar) o `X` (rechazar).
- **`comment` obligatorio si `decision = X`**, entre 10 y 500 caracteres; si no → `30 COMENTARIO OBLIGATORIO`. Si es `A`, `comment` es opcional.
- Solo si el comprobante está en `R`. Si ya se revisó → `30 COMPROBANTE YA REVISADO`, lo que evita que dos admins lo revisen a la vez. Usar `SELECT … FOR UPDATE`.
- Aprobar: comprobante `A`, cobro `A` y `paid_datetime = NOW()`.
- Rechazar: comprobante `X` con comentario, cobro `X`. El padre puede volver a subir.
- Guardar `reviewed_by` y `review_datetime`. Opcionalmente, registrar un log de auditoría como el de `user_role_audit`.

### 4.5 Admin: configuración (`configuracion.gestionar`)

| Método | Ruta | Body / respuesta |
|---|---|---|
| POST | `/api/Payment/UpdateContactSettings` | `{ "whatsappNumber": "50255551234", "displayName": "Tesorería del club" }` → `{ settingsData: {...} }` |

- `whatsappNumber`: solo dígitos con código de país, entre 8 y 15 dígitos; si no → `30 NUMERO DE WHATSAPP INVALIDO`. La API debe quitar `+`, espacios y guiones antes de validar.
- `displayName`: opcional, hasta 60 caracteres.
- `GetContactSettings` lo puede leer cualquier usuario autenticado.

---

## 5. Mensajes de error

La app traduce estos mensajes; si se usa otro, se muestra tal cual en formato de oración.

| Código | Mensaje |
|---|---|
| 39 | `COBRO NO EXISTE` |
| 30 | `COBRO YA TIENE COMPROBANTE EN REVISION` |
| 30 | `COBRO YA PAGADO` |
| 30 | `NO SE PUEDE ANULAR UN COBRO PAGADO` |
| 30 | `ARCHIVO NO VALIDO` |
| 30 | `ARCHIVO DEMASIADO GRANDE` |
| 30 | `COMENTARIO OBLIGATORIO` |
| 30 | `COMPROBANTE YA REVISADO` |
| 30 | `NUMERO DE WHATSAPP INVALIDO` |
| 03 | `NO TIENE PERMISO PARA ESTA ACCION` (ya existe) |

---

## 6. Seguridad (importante)

- **Aislamiento del padre:** en `GetMyCharges`, `UploadVoucher` y `GetVoucherFile`, filtrar siempre por el `userId` del token. Un padre nunca debe poder ver ni subir a cobros de otra familia, aunque adivine un id.
- **Archivos:**
  - Validar los *magic bytes*, el tamaño y el tipo.
  - No servirlos como estáticos; se sirven solo por `GetVoucherFile` con autorización, con `Content-Disposition: inline` y `X-Content-Type-Options: nosniff`.
  - Opcional: reescalar o recomprimir en el servidor para quitar los metadatos EXIF.
- **Montos:** `numeric`, nunca `float`. El monto lo define el admin; el padre nunca lo envía.
- **Concurrencia:** índice único de un solo comprobante en `R` por cobro, y `FOR UPDATE` al revisar.
- **Permisos:** en C# (`RequirePermission`) **y** en la función SQL (`fn_has_permission`), igual que roles y categorías.

---

## 7. Checklist de pruebas sugerido

- [ ] El padre A no ve ni puede subir a un cobro del padre B (tiene que responder `COBRO NO EXISTE`).
- [ ] Subir con el cobro en `R` o `A` falla con el mensaje correcto.
- [ ] Subir un PDF renombrado a `.jpg` → `ARCHIVO NO VALIDO`.
- [ ] Rechazar sin comentario, o con menos de 10 caracteres → `COMENTARIO OBLIGATORIO`.
- [ ] Dos admins aprueban el mismo comprobante a la vez: uno obtiene `COMPROBANTE YA REVISADO`.
- [ ] Asignar a una categoría con N hijos activos crea N cobros; sin hijos, `createdCount: 0`.
- [ ] Anular un cobro pagado falla; anular uno en revisión deja el comprobante en `X`.
- [ ] Un usuario sin `pagos.validar` recibe 403 en `GetPendingReviews` y `ReviewVoucher`.
- [ ] `GetVoucherFile` sin token → 401; de otra familia → 403 o 404.

---

## 8. Extras opcionales (no bloquean la app)

- **Notificaciones push** al padre cuando se aprueba o rechaza un comprobante, y al admin cuando llega uno nuevo.
- **PDF de constancia de solvencia** firmado por el club: `GET /api/Payment/GetSolvencyCertificate?dependentId=`. La app ya muestra la solvencia en pantalla.
- **Cobros recurrentes** (mensualidad automática por categoría el día 1).
