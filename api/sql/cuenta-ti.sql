-- Ejecutar en Query Tool sobre la base del inventario, después de las migraciones.
-- Cambiar estos tres valores antes de ejecutar.
DO $account$
DECLARE
  account_username text := lower(trim('Bladimir'));
  account_name text := 'Area de TI';
  account_password text := 'Bladi39672028*';
BEGIN
  IF account_username !~ '^[a-z0-9._@-]{3,120}$' THEN
    RAISE EXCEPTION 'El usuario debe tener entre 3 y 120 caracteres válidos';
  END IF;
  IF char_length(account_password) < 12 OR octet_length(account_password) > 72
     OR account_password = 'CAMBIAR_POR_UNA_CLAVE_PERSONAL' THEN
    RAISE EXCEPTION 'Usa una contraseña propia de al menos 12 caracteres y hasta 72 bytes';
  END IF;

  PERFORM pg_advisory_xact_lock(7911, hashtext(account_username));

  INSERT INTO public.auth_users (username, display_name, password_hash, active)
  VALUES (account_username, account_name, public.crypt(account_password, public.gen_salt('bf', 12)), true)
  ON CONFLICT (username) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    password_hash = EXCLUDED.password_hash,
    active = true;

  DELETE FROM public.auth_sessions
  WHERE user_id IN (SELECT id FROM public.auth_users WHERE username = account_username);
END
$account$;
