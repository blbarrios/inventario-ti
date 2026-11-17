# Inventario TI por espacios

El acceso de TI y los pasos del MVP para Dokploy están documentados en [DESPLIEGUE.md](DESPLIEGUE.md).

Este documento reúne el alcance, las decisiones técnicas y el orden de ejecución para retomar el proyecto. Última actualización: 17 de noviembre de 2026. Etapa actual: primera base funcional en desarrollo local.

## Alcance acordado

- Aplicación Flutter para PC y móviles. La primera entrega se propone como Flutter Web.
- Salas del piloto: **Sala de sistemas 1**, **Sala de sistemas 2** y **Sala de bienestar**. Validar primero el flujo completo en Sistemas 1.
- TI actualiza los estados manualmente y es el único equipo con acceso. Desde su sesión, TI puede abrir una vista de presentación para enseñar el plano, el inventario y los estados a auditoría o a Coordinación Financiera. Esta vista oculta los controles de edición.
- El editor permite construir la distribución a partir de un lienzo en blanco y colocar los equipos. Los estados y las distribuciones se guardan en el PostgreSQL existente, administrado por Dokploy y consultado por TI desde pgAdmin. El frontend y la API se alojarán en ese mismo VPS con Dokploy.
- Segunda etapa: vistas por grupo para computadores administrativos, routers y videobeams. Las vistas reutilizan los equipos e historiales del inventario.

## Vistas y flujos

1. **Espacios.** Listado de salas con conteos por estado. Cada sala abre un plano interactivo con zoom y desplazamiento, marcadores con texto e icono y una lista que permite buscar por código, nombre o estado. Mostrar los equipos sin posición en **Por ubicar**.
2. **Editar distribución.** Añadir, mover y ajustar figuras básicas para mesas, filas y racks. Colocar o mover equipos con mouse y pantalla táctil. Incluir controles de posición que permitan editar con teclado. Mostrar cambios pendientes, con acciones explícitas para guardar o descartar. Al abrir la vista de consulta, los marcadores abren fichas.
3. **Ficha de equipo.** Panel lateral en PC y pantalla completa en móvil. Mostrar código, nombre, tipo, sala, estado, autor y hora de la última actualización, además del historial. Propuesta inicial de estados: **Sin verificar**, **Operativo**, **Con falla**, **En mantenimiento** y **Fuera de servicio**. El formulario permite añadir una observación al cambio.
4. **Presentación.** Accesible desde la sesión de TI. Mostrar plano, lista, estado y datos básicos del equipo. Mantener las mismas comprobaciones de sesión en el servidor.

El [inventario de red](../mapa-red-actual.md) sirve como referencia inicial. Antes de sembrar datos reales, validar con TI qué equipos pertenecen a cada sala. Las posiciones se asignan desde el editor.

## Stack para el piloto

| Capa | Decisión |
| --- | --- |
| Interfaz | Flutter Web y Dart. Usar `InteractiveViewer` para el plano, `Stack` para los marcadores interactivos y `LayoutBuilder` para adaptar la ficha al ancho disponible. |
| Backend | Node.js LTS, TypeScript y Fastify. API REST con JSON Schema para validar cuerpos y respuestas. |
| Persistencia | PostgreSQL existente. Propuesta de base dedicada en la misma instancia, con rol de aplicación de permisos limitados y credenciales de migración separadas. Usar `pg` para consultas parametrizadas y transacciones, y `node-pg-migrate` para versionar el esquema. |
| Sincronización | Server-Sent Events (SSE) del backend al navegador. PostgreSQL emite avisos con `LISTEN` y `NOTIFY`. |
| Acceso | Sesión web autenticada con cookie `HttpOnly`, `Secure` y `SameSite=Lax` en producción. Validar la sesión y el acceso de TI en las rutas de consulta, escritura y eventos. Validar el origen de las solicitudes de escritura. Cuentas locales de TI y gestión por consola para el MVP. |
| Hosting | Una aplicación de Dokploy en el VPS existente, con build por Dockerfile y un dominio HTTPS en Traefik. Fastify sirve el bundle de Flutter Web y `/api` en el mismo origen. PostgreSQL sigue en su servicio actual y la API se conecta por red privada. |

Referencias: [despliegue Flutter Web](https://docs.flutter.dev/deployment/web), [InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html), [validación Fastify](https://fastify.dev/docs/latest/Reference/Validation-and-Serialization/), [transacciones en `pg`](https://node-postgres.com/features/transactions) y [migraciones](https://github.com/salsita/node-pg-migrate).

## Modelo inicial

| Entidad | Datos mínimos |
| --- | --- |
| `rooms` | ID, nombre, dimensiones del lienzo y versión de la distribución. |
| `assets` | ID, código único, nombre, tipo, sala, estado actual, versión del estado y fecha del último cambio. Admitir equipos sin sala para las futuras vistas por grupo. |
| `room_items` | ID, sala, tipo de figura, etiqueta, posición, ancho y alto. |
| `asset_positions` | ID del equipo y coordenadas `x`, `y` normalizadas entre 0 y 1. Ausencia de fila para equipos por ubicar. |
| `asset_status_history` | ID, equipo, estado anterior, estado nuevo, observación, ID del operador y fecha del servidor con zona horaria. |
| `users` | ID interno, nombre visible, referencia al proveedor de identidad y acceso habilitado. Conservar el vínculo histórico al deshabilitar una cuenta. |

Los nombres y campos son una propuesta inicial. Usar una sola ficha por equipo y conservar su historial si cambia de ubicación. Guardar las fechas como `timestamptz` y mostrarlas en hora local.

## Contrato para iniciar el desarrollo

| Ruta | Comportamiento |
| --- | --- |
| `GET /api/rooms` | Devuelve salas con conteos por estado. |
| `GET /api/rooms/:id` | Devuelve lienzo, figuras, equipos, posiciones y versión de la distribución. |
| `GET /api/assets/:id` | Devuelve la ficha y el estado actual. |
| `GET /api/assets/:id/history` | Devuelve el historial, del cambio más reciente al más antiguo. |
| `PATCH /api/assets/:id/status` | Recibe el nuevo estado, la observación opcional y la versión del estado que está viendo el operador. |
| `PUT /api/rooms/:id/layout` | Guarda figuras y posiciones con la versión de la distribución que abrió el operador. Valida coordenadas y pertenencia de los equipos a la sala. |
| `GET /api/events` | Abre un canal SSE para recibir avisos de estado o distribución. |

### Escritura y concurrencia

- El cambio de estado compara la versión recibida con la guardada, actualiza el equipo, incrementa su versión y registra el historial en una transacción. El servidor toma la identidad del operador de la sesión. Repetir el mismo estado con la versión vigente devuelve el estado actual sin crear otra transición.
- Guardar el plano en una transacción que comprueba e incrementa la versión de la distribución. La versión del estado de un equipo es independiente, de modo que una edición del plano y un cambio de estado pueden guardarse a la vez.
- Ante una versión vencida, devolver `409 Conflict`. La app recarga los datos vigentes y permite revisar el cambio antes de volver a enviarlo. Ante una respuesta de guardado interrumpida, consultar primero el estado actual en el servidor. La app solo indica **Guardado** tras confirmar la respuesta.

### Sincronización y reconexión

1. En la misma transacción de escritura, ejecutar `pg_notify` con el tipo de cambio y el identificador del equipo o sala. PostgreSQL entrega el aviso tras confirmar la transacción.
2. La API mantiene una conexión dedicada para `LISTEN` y reenvía los avisos a navegadores con sesión de TI. Los avisos solo indican qué volver a consultar. Flutter obtiene los datos vigentes a través de REST.
3. Al abrir o restablecer el canal, recargar la vista activa y volver a consultar al regresar a la pestaña. Si se pierde el `LISTEN` del servidor, restablecerlo y cerrar o invalidar los canales de navegador para forzar esa recarga. Mientras se restablece la conexión, mostrar el estado de sincronización y permitir la recarga manual.
4. Para el despliegue, verificar que el proxy transmite el flujo SSE sin almacenarlo en búfer y que una sesión vencida pierde acceso al canal.

Referencias: [PostgreSQL LISTEN](https://www.postgresql.org/docs/current/sql-listen.html), [PostgreSQL NOTIFY](https://www.postgresql.org/docs/current/sql-notify.html) y [estándar de Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html).

## Despliegue en Dokploy

El VPS y Dokploy ya existen. Para el piloto se propone un solo contenedor de aplicación con Fastify y los archivos estáticos de Flutter. Dokploy gestiona la publicación del contenedor mediante Traefik. El PostgreSQL existente queda fuera del ciclo de despliegue de la aplicación.

1. **Construir la imagen.** Crear un `.dockerignore` y un Dockerfile multietapa con contexto `inventario-ti/`. Compilar Flutter con `flutter build web --release`, compilar TypeScript y copiar ambos resultados a la imagen de ejecución. Servir el bundle con `@fastify/static`. Conservar los errores JSON de `/api` y resolver las rutas de la app en `index.html`.
2. **Configurar la aplicación.** Crear una `Application` en Dokploy con tipo de build `Dockerfile`. Si se conserva la estructura prevista del repositorio, usar `inventario-ti/Dockerfile` como ruta del Dockerfile e `inventario-ti` como contexto. Fastify escuchará en `0.0.0.0:3000`. Usar ese puerto interno en Domains de Dokploy.
3. **Conectar a PostgreSQL.** En el servicio PostgreSQL existente de Dokploy, consultar el hostname y el puerto de **Internal Credentials**. Verificar que el contenedor de la API resuelve ese hostname y alcanza el puerto por la red interna. Crear la base dedicada y sus roles en esa instancia con una cuenta administrativa, desde pgAdmin si esa cuenta tiene los permisos necesarios. Configurar `DATABASE_URL` con el host interno y el rol de aplicación en las variables de ejecución de Dokploy. Proporcionar las credenciales de migración solo durante ese paso. Flutter consume `/api` sobre HTTPS y recibe solo configuración pública. pgAdmin sigue siendo el cliente de administración de TI con su propia conexión.
4. **Publicar y migrar.** Configurar el subdominio de la app en Dokploy y los registros DNS correspondientes, habilitar HTTPS y probar el acceso desde PC y móvil. Ejecutar las migraciones primero en la base de prueba y luego como paso controlado para la base del piloto. Verificar el respaldo y la recuperación antes de la primera migración de uso real.
5. **Verificar el despliegue.** Probar una ruta de salud con datos mínimos, el inicio de sesión de TI, la recarga directa de una ruta de sala y el flujo SSE a través de Traefik. Desde PC y móvil, confirmar que la distribución y los estados se conservan después de redeplegar la aplicación. Registrar la revisión desplegada y cómo volver a la versión anterior si el esquema sigue siendo compatible.

Referencias: [build con Dockerfile en Dokploy](https://docs.dokploy.com/docs/core/applications/build-type), [dominios y puertos en Dokploy](https://docs.dokploy.com/docs/core/domains), [conexión interna a PostgreSQL en Dokploy](https://docs.dokploy.com/docs/core/databases/connection) y [archivos estáticos en Fastify](https://github.com/fastify/fastify-static).

### Crear la base desde pgAdmin

Abrir Query Tool sobre la base `postgres` con la cuenta administrativa de PostgreSQL en Dokploy. Sustituir cada valor de ejemplo por una contraseña distinta.

```sql
CREATE ROLE inventory_migrator WITH LOGIN PASSWORD 'REEMPLAZAR_CLAVE_MIGRACIONES';
CREATE ROLE inventory_app WITH LOGIN PASSWORD 'REEMPLAZAR_CLAVE_API';
```

Ejecutar la siguiente sentencia sola, con autocommit habilitado. [PostgreSQL CREATE DATABASE](https://www.postgresql.org/docs/current/sql-createdatabase.html)

```sql
CREATE DATABASE inventory_ti OWNER inventory_migrator;
```

Refrescar **Databases** y abrir Query Tool sobre `inventory_ti`. Ejecutar con la cuenta administrativa.

```sql
REVOKE CONNECT, TEMPORARY ON DATABASE inventory_ti FROM PUBLIC;
GRANT CONNECT ON DATABASE inventory_ti TO inventory_app;
GRANT USAGE ON SCHEMA public TO inventory_app;
```

Para crear las tablas, ejecutar `npm run migrate` desde `inventario-ti/api` en un entorno que pueda alcanzar PostgreSQL. En esa ejecución, `DATABASE_URL` debe usar `inventory_migrator`, el hostname y puerto alcanzables desde ese entorno y la base `inventory_ti`. La migración existente conserva el historial del esquema en `pgmigrations`.

Después de ejecutar la migración, volver a Query Tool de `inventory_ti` con la cuenta administrativa y dar a la API los permisos sobre las tablas de inventario.

```sql
GRANT SELECT ON public.rooms TO inventory_app;
GRANT UPDATE (layout_version) ON public.rooms TO inventory_app;
GRANT SELECT, INSERT, UPDATE ON public.assets TO inventory_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.room_items, public.asset_positions TO inventory_app;
GRANT SELECT, INSERT ON public.asset_status_history TO inventory_app;
GRANT USAGE ON SEQUENCE public.asset_status_history_id_seq TO inventory_app;
```

La variable `DATABASE_URL` de ejecución de la API en Dokploy usa `inventory_app` y el hostname interno del servicio PostgreSQL. La creación de la base y sus tablas prepara el almacenamiento. Flutter consulta la API cuando se compila con USE_API=true. El acceso de TI usa sesiones de PostgreSQL.

### Base existente confirmada

La base de destino confirmada por TI se llama `inventory-app`. La contraseña se configurará directamente en Dokploy. Para ejecutar sentencias SQL que nombren esa base, usar `"inventory-app"` entre comillas dobles. La ruta de una URL PostgreSQL admite `/inventory-app`.

Usar los comandos de creación anteriores solo al preparar una instancia nueva. Para esta base existente, ejecutar las migraciones con una cuenta que pueda crear tablas y usar en la API un rol con los permisos de inventario documentados arriba. En Dokploy, obtener el hostname y puerto internos del servicio PostgreSQL y configurar `DATABASE_URL` con la base `inventory-app`.

Las rutas de inventario requieren una cuenta de TI. El modo INVENTORY_LOCAL_DEV=true se conserva para pruebas de loopback y queda bloqueado en producción. Consultar DESPLIEGUE.md para aplicar las migraciones, crear cuentas y configurar las sesiones.

El 17 de noviembre de 2026 las dos pruebas HTTP pasaron contra una base desechable llamada `inventory-app` con PostgreSQL 17. Se verificaron alta de equipo, código duplicado, dos cambios simultáneos con conflicto de versión, historial sin duplicados y guardado del plano con control de pertenencia a la sala. Otra instancia de la API pudo consultar los datos guardados. La prueba de escritura utilizó el rol limitado `inventory_app` con los permisos documentados. La instancia del VPS sigue pendiente de configuración y verificación.

## Orden de implementación y entrega

1. **Preparar desarrollo local.** Crear `inventario-ti/app/` y `inventario-ti/api/`, verificar las versiones de Flutter, Node y PostgreSQL, y dejar registradas las versiones elegidas. Crear una base de desarrollo con datos ficticios, migraciones y un `.env.example` sin valores reales. Documentar los comandos de arranque en este archivo cuando se puedan verificar.
2. **Cerrar Sistemas 1 de punta a punta.** Implementar listado, plano, editor, ficha, estado e historial. Probar la API contra PostgreSQL y el flujo de marcadores con las pruebas de Flutter. Incorporar autenticación de TI y sincronización SSE antes de compartir el piloto.
3. **Validar el piloto.** Cargar el inventario validado y habilitar Sistemas 2 y Bienestar. Verificar en un PC y un celular que el plano guardado se conserva, el cambio de estado se refleja en la otra pantalla y el historial identifica al operador. Probar dos cambios simultáneos, la reconexión y el acceso sin sesión. Verificar la vista de presentación con TI.
4. **Habilitar el despliegue en Dokploy.** Aplicar la secuencia anterior sobre una base de prueba del VPS. Validar la red privada, HTTPS y la autenticación antes de habilitar el piloto para TI.
5. **Agregar vistas por grupo.** Usar el inventario común para computadores administrativos, routers y videobeams después de validar las salas.

## Skills para el agente ejecutor

- `ui-ux-pro-max`, disponible en el entorno de planificación, para adaptación por tamaño, controles de edición y accesibilidad.
- `flutter-apply-architecture-best-practices` para estructurar vistas, lógica y datos. [Skill oficial](https://github.com/flutter/agent-plugins/blob/main/skills/flutter-apply-architecture-best-practices/SKILL.md)
- `flutter-build-responsive-layout` para validar los cambios entre PC y móvil. [Skill oficial](https://github.com/flutter/agent-plugins/blob/main/skills/flutter-build-responsive-layout/SKILL.md)
- `flutter-add-widget-test` para verificar la selección de marcadores, edición y actualización de estados. [Skill oficial](https://github.com/flutter/agent-plugins/blob/main/skills/flutter-add-widget-test/SKILL.md)

Las skills oficiales están identificadas para la fase de implementación. Los archivos enlazados se pueden consultar aunque la instalación esté pendiente.

## Pendientes de confirmar

- Crear las cuentas locales de TI siguiendo DESPLIEGUE.md. El restablecimiento de contraseña se realiza desde la consola con user:set.
- Confirmar la versión de PostgreSQL y el alcance al hostname interno desde el contenedor de la API durante la preparación del despliegue. Confirmar el subdominio y si el acceso de TI será desde internet, por VPN o solo por la red interna.
- Inventario inicial de las tres salas y nombres definitivos de los estados. El editor permite que TI levante las ubicaciones directamente en la app.

## Compilación local

El 17 de noviembre de 2026 se verificaron ambos comandos en Windows con Flutter 3.47.4, Dart 3.13.3 y Node.js 24.19.0. La compilación de Flutter necesitó acceso de escritura a la caché del SDK y acceso a `pub.dev`. La instalación de la API necesitó acceso al registro de npm.

- En `inventario-ti/app`, ejecutar `flutter build web --release`. El resultado queda en `app/build/web/`.
- En `inventario-ti/api`, ejecutar `npm ci` para instalar desde el archivo de bloqueo y `npm run build` para generar `api/dist/`.

### Ejecutable de escritorio para Windows

En `inventario-ti/app`, ejecutar `flutter build windows --release` con las herramientas de C++ de Visual Studio. La compilación x64 genera `build/windows/x64/runner/Release/inventario_ti.exe`. Conservar el ejecutable junto a `flutter_windows.dll` y el directorio `data`.

El paquete local `app/build/Inventario-TI-Windows-x64.zip` incluye esos archivos y las DLL redistribuibles de Visual C++ para x64. El 17 de noviembre de 2026 se comprobó que el ejecutable abre su ventana desde una copia extraída del ZIP. [Distribución de aplicaciones Flutter para Windows](https://docs.flutter.dev/platform-integration/windows/building)

## Pruebas locales

### Auditoría de interfaz

La revisión cubrió el inicio, el plano, la edición de posiciones, el inventario de la sala, la ficha de equipo y el modo de presentación. Se aplicaron `interface-design`, `impeccable` y `ui-ux-pro-max` a la interfaz Flutter. Se conservó el verde de la aplicación y se usaron superficies claras, bordes discretos y texto e iconos para identificar los estados.

| Hallazgo | Corrección |
| --- | --- |
| El resumen inicial solo distinguía equipos operativos. | El inicio muestra los cinco estados y sus conteos, además de una vista previa del plano de cada sala. |
| En móvil se superponían marcadores y el formulario quedaba comprimido. | El mapa ajusta los marcadores al ancho. En móvil se alterna entre plano y lista, y la ficha abre en una hoja con desplazamiento y la acción de guardado visible. |
| Arrastrar aplicaba cambios de posición sin confirmación y era la única forma de mover equipos. | La edición usa un borrador con Guardar y Descartar. Las flechas permiten mover el marcador seleccionado usando botones con etiquetas accesibles. |
| La observación escrita aparecía como historial aunque no se hubiera guardado un cambio. | El historial de sesión guarda únicamente las transiciones confirmadas y sus observaciones. Presentación muestra los datos básicos y el estado. |
| Encontrar un equipo exigía recorrer la sala. | La lista permite filtrar por nombre, código, tipo o estado. |

El inventario, los cambios de estado y las posiciones del prototipo siguen en memoria durante la sesión. La interfaz usa localización `es-CO` para los controles y las fechas de Flutter.

El análisis de Flutter terminó sin hallazgos y pasaron seis pruebas de interfaz. Se revisaron el inicio, el plano y la ficha en Chrome a 1280 × 800, 390 × 844, 320 × 720 y 844 × 390. Las etiquetas de estado alcanzan al menos 5,28:1 de contraste sobre su fondo en el tema claro.

### Cómo repetir las pruebas

- En `inventario-ti/app`, ejecutar `flutter test`. Las pruebas cubren el inicio a 390 × 844, el cambio de estado durante la sesión, el cierre de ficha, el arrastre en modo edición y el modo de presentación.
- En `inventario-ti/api`, configurar `DATABASE_URL` con una base PostgreSQL desechable y ejecutar `npm run migrate`. Ejecutarlo de nuevo confirma que no hay migraciones pendientes. Con los archivos de compilación disponibles, configurar `TEST_DATABASE_URL` con la misma conexión y ejecutar `node --test test/http.test.mjs`. La prueba levanta Fastify en un puerto local, crea una sala y un equipo de prueba y comprueba salud, conteo de equipos, archivos web y el error JSON de una ruta inexistente.
- Para servir el bundle de Flutter desde Fastify fuera de Docker, definir `PUBLIC_DIR` con la ruta a `app/build/web` y `HOST=127.0.0.1` para limitar el acceso al equipo local. En la imagen, el servidor usa el directorio `public` que contiene el bundle.

El 17 de noviembre de 2026 pasaron las cuatro pruebas de Flutter y la prueba HTTP con PostgreSQL 17. En Chrome se abrió el inicio, la Sala de sistemas 1 y la ficha de un equipo a 1280 × 800 y 390 × 844. `docker build -t inventario-ti:prueba-final .` generó la imagen, que respondió por HTTP y se conectó al PostgreSQL de prueba desde una red Docker local.

Tras actualizar `@fastify/static`, `npm audit --omit=dev` reportó cero vulnerabilidades en las dependencias de ejecución. La auditoría completa sigue reportando tres avisos moderados en dependencias de desarrollo. El Dockerfile actual copia esas dependencias a la imagen.

**Estado de ejecución.** Flutter puede consultar la API y guardar el inventario. El MVP incluye acceso de TI con sesiones de 12 horas, gestión de cuentas por consola y usuario en el historial. El despliegue y la comprobación en el VPS quedan a cargo de TI. La sincronización automática sigue pendiente.
