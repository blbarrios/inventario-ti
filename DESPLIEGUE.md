# Despliegue del MVP en Dokploy

La aplicación usa cuentas locales de TI. Todas las cuentas habilitadas pueden consultar y editar el inventario. El alta y el restablecimiento de contraseña se pueden hacer desde pgAdmin o la consola del servidor. Cada sesión dura 12 horas. El historial de estados registra el nombre de usuario.

## Configurar la aplicación

En Dokploy, crear una aplicación con el repositorio y el Dockerfile de la raíz. Usar `.` como contexto. Asociar el dominio al puerto interno `3000` y habilitar HTTPS.

Configurar las variables de ejecución siguientes, reemplazando los ejemplos por la conexión y el dominio reales.

```dotenv
DATABASE_URL=postgresql://USUARIO:CLAVE@HOST_INTERNO:5432/NOMBRE_BASE
APP_ORIGIN=https://inventario.example.org
INVENTORY_LOCAL_DEV=false
```

`APP_ORIGIN` es el origen público del frontend, con protocolo y dominio. La imagen configura `NODE_ENV=production`. En producción las cookies de sesión necesitan HTTPS. El puerto y el hostname de PostgreSQL se toman de la conexión interna del servicio en Dokploy. Usar el nombre de la base existente en la URL.

El Dockerfile compila Flutter con `USE_API=true`. Así, web consulta `/api` desde el mismo dominio y solicita inicio de sesión. Compilar Flutter sin esa opción sigue seleccionando el repositorio de demostración.

## Aplicar las migraciones

Desde la consola del contenedor de la aplicación, en `/app`, ejecutar lo siguiente con una conexión que pueda crear y modificar tablas en la base.

```sh
npm --prefix /app run migrate
```

Esto aplica las migraciones pendientes, incluida `003_auth`, que crea `auth_users` y `auth_sessions`. Ejecutar el comando de nuevo informa que no hay migraciones pendientes.

Si la API utiliza un usuario de PostgreSQL con permisos limitados, aplicar la migración con la conexión propietaria de las tablas. Luego, desde pgAdmin sobre la base del inventario, conceder estos permisos al usuario que ejecutará la API. El ejemplo usa `inventory_app` como nombre del rol.

```sql
GRANT USAGE ON SCHEMA public TO inventory_app;
GRANT SELECT, INSERT ON public.rooms TO inventory_app;
GRANT UPDATE (layout_version) ON public.rooms TO inventory_app;
GRANT SELECT, INSERT, UPDATE ON public.assets TO inventory_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.room_items, public.asset_positions TO inventory_app;
GRANT SELECT, INSERT ON public.asset_status_history TO inventory_app;
GRANT USAGE ON SEQUENCE public.asset_status_history_id_seq TO inventory_app;
GRANT SELECT ON public.auth_users TO inventory_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.auth_sessions TO inventory_app;
```

## Crear o restablecer una cuenta desde pgAdmin

Después de aplicar las migraciones y desplegar la versión que admite pgcrypto, abrir Query Tool sobre la base del inventario con la cuenta administrativa.

Abrir [api/sql/cuenta-ti.sql](api/sql/cuenta-ti.sql), cambiar los valores de account_username, account_name y account_password y ejecutar su contenido. El bloque crea la cuenta o actualiza su contraseña, la habilita y revoca sus sesiones anteriores. Usa bcrypt de pgcrypto y valida la longitud de la clave antes de guardarla. La API también admite los hashes scrypt creados desde la consola.

La contraseña debe tener al menos 12 caracteres y ocupar hasta 72 bytes en UTF-8. Después del cambio se ingresa con ese usuario y esa contraseña desde el formulario de la aplicación. El script SQL contiene una contraseña de ejemplo que obliga a reemplazarla antes de ejecutarlo.

## Crear la primera cuenta de TI

Ejecutar en la consola del contenedor con la conexión propietaria o administrativa en `DATABASE_URL`. La cuenta de PostgreSQL usada para administrar usuarios debe poder escribir en `auth_users` y revocar registros de `auth_sessions`.

```sh
export TI_USERNAME=tecnico
export TI_DISPLAY_NAME="Responsable de TI"
printf "Contraseña (12 a 256 caracteres): "
stty -echo
read -r TI_PASSWORD
stty echo
printf "\n"
export TI_PASSWORD
npm --prefix /app run user:set
unset TI_PASSWORD
```

Elegir el nombre de usuario con letras minúsculas, números, punto, guion, `@` o `_`, de 3 a 120 caracteres. La contraseña admite espacios y debe tener entre 12 y 256 caracteres. El comando guarda un hash scrypt en PostgreSQL.

Repetir `user:set` con un usuario existente cambia su contraseña y nombre visible, habilita su cuenta y revoca todas sus sesiones. Crear una cuenta por cada persona permite reconocer quién actualizó un equipo.

Para deshabilitar una cuenta y revocar sus sesiones, ejecutar lo siguiente.

```sh
TI_USERNAME=tecnico npm --prefix /app run user:disable
```

## Comprobar el acceso

Abrir el dominio HTTPS e ingresar con la cuenta recién creada. Crear una sala o un equipo, cambiar su estado y comprobar el nombre de usuario en el historial de la API. Recargar la página conserva la sesión hasta su vencimiento. Cerrar sesión revoca la sesión actual y vuelve al formulario.

La API exige sesión para consultar y editar salas, equipos, posiciones e historial. Las sesiones se guardan en PostgreSQL y sobreviven a reinicios de la API. Web usa cookie HttpOnly, Secure en producción y SameSite=Lax. Las escrituras llevan una cabecera propia y comprueban el origen configurado. El login limita los intentos a 20 por minuto por IP vista por la API. Con el proxy de Dokploy, varios usuarios pueden compartir ese límite.

## Desarrollo local y Windows

Para probar la autenticación con la API local, usar `HOST=127.0.0.1`, `NODE_ENV=development`, `INVENTORY_LOCAL_DEV=false` y el origen del frontend en `APP_ORIGIN`. Servir el bundle compilado mediante `PUBLIC_DIR` desde Fastify permite probar cookies desde el mismo origen.

`INVENTORY_LOCAL_DEV=true` conserva el acceso de prueba de loopback de los tests existentes. Ese modo está bloqueado con `NODE_ENV=production`.

Para generar un ejecutable que consulte el servidor desplegado, compilar con la URL pública de la API, sin barra final.

```sh
flutter build windows --release --dart-define=USE_API=true --dart-define=API_BASE=https://inventario.example.org
```

El ejecutable usa un token de sesión en memoria. Al cerrarlo, será necesario iniciar sesión de nuevo. La contraseña y la conexión PostgreSQL se configuran en el servidor. El ejecutable contiene únicamente la dirección HTTPS de la API.

## Verificación realizada

Se probaron las migraciones y el alta y desactivación por consola contra PostgreSQL 17 local. Las pruebas HTTP verifican contraseña incorrecta, acceso anónimo, bloqueo de origen ajeno, cookie segura, restauración desde otra instancia de la API, token de escritorio, cierre de sesión, expiración, cuenta desactivada, límite de intentos y operador en historial.

El despliegue real, la conexión a PostgreSQL del VPS y el dominio HTTPS se configuran en Dokploy. La sincronización automática entre pantallas sigue pendiente.
