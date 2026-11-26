# Auditoría de interfaz — app Flutter `inventario-ti/app`

Fecha: 2026-11-17 · Método: lectura del código + capturas renderizadas (escritorio 1280×800 y móvil 390×844) con Roboto real, aplicando los criterios de Impeccable (`audit` / craft floor) y UI UX Pro Max (reglas para Flutter).

## Puntuación (escala Impeccable, 0–4)

| Dimensión | Antes | Después | Comentario |
|---|---|---|---|
| Accesibilidad | 3 | 3 | Buena base (Semantics, tooltips, objetivos ≥48 px). Se corrigió texto de 10 px y el desbordamiento con texto grande. |
| Rendimiento | 4 | 4 | Árbol pequeño, `RepaintBoundary` en la cuadrícula del plano. |
| Temas | 2 | 2 | Tokens como constantes globales; no hay tema oscuro (pendiente). |
| Adaptable | 3 | 4 | Diseños para móvil y escritorio; los marcadores se adaptan al ancho del plano. |
| Coherencia | 2 | 3 | Estados mostrados de forma uniforme y ordenados por gravedad. |
| **Total** | **14/20** | **16/20** | Bien, falta el tema oscuro. |

## Hallazgos y cambios aplicados

| # | Gravedad | Hallazgo | Cambio |
|---|---|---|---|
| 1 | P1 | El modo «Presentación» era un FilterChip que parecía un botón sin estado claro. | Interruptor con etiqueta (`_ModeSwitch`, toda la fila es pulsable, objetivo de 48 px) y un aviso que explica qué hace el modo. |
| 2 | P1 | Los marcadores del plano usaban texto de 10 px (por debajo del mínimo de 12) y alto fijo, lo que se desbordaba con texto grande. | Texto de 13/11,5 px; escala de texto limitada a 1,3× solo en el plano (la lista conserva el tamaño completo); ancho que se adapta (82/116/148 px). |
| 3 | P1 | Para cambiar el estado había que abrir un desplegable: dos toques y las opciones quedaban ocultas. | Fichas `ChoiceChip` con icono y color: las cinco opciones a la vista y se elige con un toque. |
| 4 | P2 | El botón «Guardar estado» aparecía deshabilitado sin explicar por qué. | Texto de ayuda: «Elige un estado distinto al actual para guardar». |
| 5 | P2 | El encabezado de la ficha (nombre y botón de cerrar) se desplazaba con el formulario y la X quedaba fuera de la vista. | Nombre y botón de cerrar fijos arriba; solo se desplaza el contenido. |
| 6 | P2 | El resumen pintaba los «0» de rojo o ámbar, como si fueran alertas. | Los conteos en cero se muestran en gris, con cifras tabulares, y se añadió una barra de distribución proporcional. |
| 7 | P2 | El estado se mostraba de tres formas distintas: texto coloreado en las salas, etiquetas sin conteo en la leyenda y etiquetas en la lista. | Se usa siempre `StatusTag` con conteo opcional («4 Sin verificar»). |
| 8 | P2 | El orden de los estados cambiaba de una vista a otra. | `statusesBySeverity` (falla → fuera de servicio → mantenimiento → operativo → sin verificar) en todas las vistas. |
| 9 | P3 | La barra superior de la sala decía «Espacios» y el nombre de la sala se repetía debajo. | La barra superior muestra el nombre de la sala; el cuerpo muestra el conteo y las acciones. |
| 10 | P3 | Los marcadores con falla o mantenimiento no destacaban en el plano. | El borde del marcador toma el color de su estado (excepto «Sin verificar»). |
| 11 | P3 | El historial usaba el carácter «→», que no se ve con algunas fuentes. | Icono de flecha y etiqueta accesible «De X a Y». |

## Pendiente (no aplicado)

- **Tema oscuro (P2):** hay que convertir los colores de `inventory_theme.dart` (`paper`, `ink`, `line`…) en un `ThemeExtension` y definir `darkTheme`. Los `CustomPainter` (cuadrícula y miniatura) también usan colores fijos.
- **Probar con lector de pantalla** (TalkBack/Narrador) el flujo de editar la distribución.
- **Persistencia:** los cambios solo duran la sesión (lo indican los mensajes); cuando se conecte la API habrá que diseñar los estados de carga y error.

Verificación: `flutter analyze` sin problemas y los 6 tests de widget pasan (se actualizó un test por el cambio a fichas).

---

## Rediseño visual (v2, 2026-11-17)

**Dirección:** el cuarto de red. Tinta grafito sobre «papel de etiqueta» blanco, grises fríos como el metal del rack, y el color reservado **solo para el estado**, mostrado como el LED de un puerto de switch. Sin sombras: la estructura se marca con líneas finas.

- **Tipografía:** IBM Plex Sans (interfaz) e IBM Plex Mono (códigos y cifras), incluidas en `app/assets/fonts` con licencia OFL. Escala de ~1,2 a partir de 14 px; la jerarquía se marca con el peso y el tono de la tinta.
- **Sello visual:** `StatusLed` (encendido para falla, mantenimiento y operativo; apagado y hueco para fuera de servicio; tenue para sin verificar) y `CodeTag` (código en monoespaciada sobre una tira, como cinta de rotuladora).
- **Inicio:** un panel de estado con un titular que dice qué importa («1 equipo requiere atención», «3 de 7 verificados»), una barra de proporción y la leyenda con los conteos. Las salas van en filas dentro de una sola superficie, en vez de tarjetas sueltas.
- **Modo:** control segmentado «Edición / Presentación», que siempre muestra el modo activo.
- **Sala:** el plano es papel de dibujo con cuadrícula de puntos; los marcadores parecen etiquetas; la leyenda y el zoom flotan sobre el plano. En edición, la cuadrícula se oscurece, el cursor cambia a «arrastrar» y las flechas reemplazan al zoom.
- **Ficha:** el estado actual va destacado; el selector de estado es una lista con LED y marca de verificación, que indica cuál es el «Actual»; el botón de guardar es de grafito.
- **Tokens:** `canvas / sheet / well / planPaper`, cuatro niveles de tinta (`ink / inkSoft / inkFaint / inkGhost`) y `hairline`, definidos en `inventory_theme.dart`.

Sigue pendiente el tema oscuro: con la tinta y el color de estado separados, basta con invertir los tokens.

---

## Alta de salas y equipos (2026-11-17)

Nuevo archivo `app/lib/forms.dart` con dos formularios que se muestran como diálogo en escritorio y como hoja inferior en móvil.

- **Agregar sala:** fila «+ Agregar sala» al final de la lista del inicio (solo en modo Edición). Pide el nombre, rechaza nombres repetidos y, al crearla, abre la sala nueva.
- **Agregar equipo:** botón «Agregar equipo» en la cabecera de la sala y en el estado vacío del plano («Agregar el primer equipo»). Pide nombre, código (en monoespaciada, sin espacios) y tipo, con chips de sugerencia (Switch, Router, Punto de acceso…). Valida que el código no se repita dentro de la sala. El equipo nuevo se coloca en el plano sin encimarse con los demás y queda seleccionado.
- La validación se dispara al salir de cada campo (`AutovalidateMode.onUnfocus`), no antes.
- Pruebas añadidas: alta de sala, nombre de sala repetido y alta de equipo. En total 9 tests, todos pasan; `flutter analyze` sin avisos.

---

## Ícono de dispositivo por equipo (2026-11-17)

- Cada equipo tiene un **ícono** (`DeviceIcon`): genérico, computador, portátil, servidor, switch, router, punto de acceso, teléfono, impresora, UPS, patch panel, cámara o pantalla. Son íconos de contorno, en la misma línea del resto.
- El ícono se **colorea según el estado** (reemplaza al LED en el marcador y en la lista); el LED se conserva en las leyendas y resúmenes de estado.
- Se elige en el **alta** (el ícono sigue al tipo mientras no lo cambies a mano, con chips y una cuadrícula) y en la **ficha** (sección «Ícono», se aplica al tocarlo).
- Por defecto se deduce del tipo escrito (`deviceIconForType`).
- Pruebas: alta con ícono deducido del tipo y cambio de ícono desde la ficha. 12 tests en verde; `flutter analyze` sin avisos.

### Para persistir el ícono (cuando se conecte la API)
La tabla `assets` hoy no tiene columna `icon`. Habrá que: añadir una migración (`icon text not null default 'generic'`), incluir el campo en `POST /api/assets` y en las respuestas de `GET`, y mapear el enum a texto en el cliente. Mientras tanto, el ícono vive solo en la sesión del navegador.

---

## Conexión con la API (2026-11-17)

La app ya no vive solo en memoria: hay un **repositorio** (`app/lib/inventory_repository.dart`) con dos implementaciones detrás de la misma interfaz.
- `DemoInventoryRepository`: datos en memoria (la app corre sin backend y respalda los tests).
- `HttpInventoryRepository`: habla con la API Fastify (REST con `package:http`).

Se elige por flags de compilación: por defecto **demo**; con `--dart-define=USE_API=true` usa la API (y `--dart-define=API_BASE=...` para desarrollo cruzado de orígenes). El Dockerfile ya pasa `USE_API=true`, así en producción el bundle consume `/api` en el mismo origen.

### Qué se conectó
- **Inicio**: carga `GET /rooms` + `GET /rooms/:id` (con indicador de carga y pantalla de error con «Reintentar»).
- **Crear sala** → `POST /rooms`. **Crear equipo** → `POST /assets` (envía el ícono) y luego `PUT /rooms/:id/layout` para persistir su posición.
- **Cambiar estado** → `PATCH /assets/:id/status` (con `version` para control de concurrencia; avisa si otro cambió el estado).
- **Cambiar ícono** → `PATCH /assets/:id/icon`.
- **Guardar plano** → `PUT /rooms/:id/layout`.
- **Historial** → `GET /assets/:id/history` al abrir la ficha.

### Backend añadido
- Migración `002_asset_icon.js`: columna `icon` en `assets` (con `check`), por defecto `generic`.
- `POST /rooms` (crear sala) y `PATCH /assets/:id/icon` en `inventory.ts`; `POST /assets` ahora acepta `icon`.
- `@fastify/cors` en `server.ts`, **solo** cuando `INVENTORY_LOCAL_DEV=true` (para el dev server de Flutter en otro puerto).

### Cómo correr en local
1. Base de datos lista y migraciones aplicadas:
```bash
npm --prefix api install
npm --prefix api run migrate
```
2. API en modo local (habilita las rutas de inventario y CORS):
```bash
INVENTORY_LOCAL_DEV=true DATABASE_URL=postgres://... npm --prefix api run dev
```
3. App apuntando a la API:
```bash
cd app && flutter run -d chrome --dart-define=USE_API=true --dart-define=API_BASE=http://localhost:3000
```

### Pendiente
- **Auth de TI**: en producción las rutas `/api/*` responden 503 hasta configurar el acceso (`registerInventoryRoutes` lo exige). Hay que definir el proveedor de identidad y validar la sesión antes de un despliegue útil con datos reales.
- **SSE en vivo**: el README lo contempla (LISTEN/NOTIFY), pero la API aún no expone el endpoint. Hoy la app refleja los cambios propios al instante; para ver cambios de otros usuarios en vivo falta agregar el stream SSE y suscribirse desde el cliente.
- Verificación: `flutter analyze` sin avisos, 18 tests en verde (incluye pruebas del cliente HTTP con `MockClient`), y `tsc` del backend compila.

---

## Responsable, Canvas ampliado, edición y CSV (2026-11-17)

### Responsable (por equipo, texto libre)
- Campo `responsible` en `assets` (migración `004_asset_responsible.js`), opcional.
- Se captura en el alta y en la edición; se muestra en la ficha («Responsable: …»).
- `POST /assets` lo acepta; `GET` lo devuelve.

### Editar equipos existentes
- Botón «Editar equipo» (lápiz) en la ficha → formulario para nombre, tipo y responsable. El **código no se cambia** (es el identificador).
- Nuevo `PATCH /assets/:id` (nombre/tipo/responsable) en la API. El ícono se sigue cambiando aparte con `PATCH /assets/:id/icon`.

### Canvas ampliado + mobiliario
- Más zoom (hasta 5×) y más margen de desplazamiento.
- **Zonas** (`room_items`: mesa, fila, rack) que ya existían en la BD: se dibujan en el plano detrás de los equipos, con etiqueta.
- En «Editar distribución»: barra «Agregar zona», y cada zona se puede **seleccionar, arrastrar, redimensionar (asa inferior derecha), renombrar/cambiar tipo y eliminar**. Se guardan con «Guardar plano» (ahora el `PUT …/layout` envía las zonas; antes las borraba).

### Importar CSV + plantilla
- Menú ⋮ en la sala (modo edición): **Importar CSV** y **Descargar plantilla**.
- Columnas: `codigo,nombre,tipo,icono,responsable,estado` (encabezados sin distinguir may/min ni acentos; `codigo/nombre/tipo` obligatorios). Acepta claves o etiquetas en español para ícono y estado.
- El parser (`csv_import.dart`) entiende campos entre comillas y comas. Importa fila por fila con `POST /assets`, aplica el estado si no es «Sin verificar», persiste posiciones con un `PUT …/layout`, y muestra un resumen con los omitidos (p. ej. códigos repetidos).
- La selección/descarga de archivo usa `dart:html` solo en web (con stub para tests/escritorio).

### Verificación
- `flutter analyze` sin avisos; **28 tests** en verde (incluye parser de CSV, edición, responsable y alta de zona); `tsc` del backend compila.

### Pendiente para persistir todo
Aplicar las migraciones nuevas antes de usar la API con datos reales:
```bash
npm --prefix api run migrate
```
Sigue pendiente lo de antes: auth de TI para producción y SSE en vivo.

## Auditoría de «Todos los equipos» y mantenimiento pendiente

- **Inicio:** nueva sección «Mantenimiento pendiente», bajo el resumen de estado. Muestra hasta 5 equipos, con su persona y su sala, y abre la ficha en una hoja inferior. Si hay más, lleva a «Todos los equipos» con el filtro activado.
- **Cabecera del inicio:** «Todos los equipos» pasó a estar a la derecha del título («Equipos» en móvil).
- **Todos los equipos:** usa los mismos componentes que la lista de cada sala (`AssetRow`, `SheetSurface`), con íconos redondeados, buscador con botón para limpiar, estados de carga, error y vacío como en el inicio, y un filtro con su contador.
- **Ficha:** el interruptor de mantenimiento va en un recuadro, igual que el estado actual. Los errores muestran un mensaje legible en lugar de la excepción.
- **Token `maintenanceInk`:** reemplaza el ámbar `0xFF8F5607` que estaba repetido en cuatro sitios.
