import { createHash, randomBytes } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import type { Pool } from 'pg';
import { hashPassword, verifyPassword } from './password.js';

type SessionUser = { id: string; username: string; displayName: string };
declare module 'fastify' {
  interface FastifyRequest { user: SessionUser | null; }
}

const cookieName = 'inventory_session';
const lifetimeSeconds = 12 * 60 * 60;
const tokenHash = (token: string) => createHash('sha256').update(token).digest('hex');

export async function configureAuth(app: FastifyInstance, pool: Pool, localDevelopment: boolean) {
  const production = process.env.NODE_ENV === 'production';
  const configuredOrigin = process.env.APP_ORIGIN;
  if (production && localDevelopment) throw new Error('Desactiva INVENTORY_LOCAL_DEV en producción');
  if (production && (!configuredOrigin || new URL(configuredOrigin).protocol !== 'https:')) {
    throw new Error('Configura APP_ORIGIN con el origen HTTPS de la aplicación');
  }
  const origin = configuredOrigin ? new URL(configuredOrigin).origin : null;
  const cookieOptions = {
    path: '/api', httpOnly: true, secure: production, sameSite: 'lax' as const,
  };
  const dummy = await hashPassword(randomBytes(32).toString('hex'));
  app.decorateRequest('user', null);
  await app.register(rateLimit, { global: false });

  function token(request: FastifyRequest) {
    const authorization = request.headers.authorization;
    if (authorization?.startsWith('Bearer ')) return authorization.slice(7);
    return request.cookies[cookieName];
  }

  async function authenticate(request: FastifyRequest, reply: FastifyReply) {
    const raw = token(request);
    if (!raw || !/^[a-f0-9]{64}$/.test(raw)) {
      return reply.code(401).send({ error: 'Inicia sesión para continuar' });
    }
    const result = await pool.query(`
      SELECT u.id, u.username, u.display_name AS "displayName"
      FROM auth_sessions s JOIN auth_users u ON u.id = s.user_id
      WHERE s.token_hash = $1 AND s.expires_at > now() AND u.active
    `, [tokenHash(raw)]);
    if (!result.rowCount) {
      reply.clearCookie(cookieName, cookieOptions);
      return reply.code(401).send({ error: 'Tu sesión terminó. Vuelve a ingresar.' });
    }
    request.user = result.rows[0];
  }

  // Custom header forces cross-origin browser writes to preflight before sending.
  app.addHook('onRequest', async (request, reply) => {
    if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) return;
    if (localDevelopment && !request.url.startsWith('/api/auth/')) return;
    if (request.headers['x-inventory-request'] !== '1') {
      return reply.code(403).send({ error: 'Solicitud no permitida' });
    }
    if (request.headers.origin && origin && request.headers.origin !== origin) {
      return reply.code(403).send({ error: 'Origen no permitido' });
    }
  });

  app.post<{ Body: { username: string; password: string; desktop?: boolean } }>('/api/auth/login', {
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
    schema: { body: {
      type: 'object', required: ['username', 'password'], additionalProperties: false,
      properties: {
        username: { type: 'string', minLength: 1, maxLength: 120 },
        password: { type: 'string', minLength: 1, maxLength: 256 },
        desktop: { type: 'boolean' },
      },
    } },
  }, async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    const username = request.body.username.trim().toLowerCase();
    const client = await pool.connect();
    let user;
    const raw = randomBytes(32).toString('hex');
    try {
      await client.query('BEGIN');
      // Coordinate login with password resets and account deactivation.
      await client.query('SELECT pg_advisory_xact_lock(7911, hashtext($1))', [username]);
      const result = await client.query('SELECT * FROM auth_users WHERE username = $1', [username]);
      user = result.rows[0];
      let valid: boolean;
      if (user?.password_hash.startsWith('$2a$')) {
        // Accounts created in pgAdmin use pgcrypto bcrypt (at most 72 bytes).
        if (Buffer.byteLength(request.body.password, 'utf8') > 72) {
          valid = false;
        } else {
          const check = await client.query(
            'SELECT public.crypt($1, $2) = $2 AS valid',
            [request.body.password, user.password_hash],
          );
          valid = check.rows[0].valid;
        }
      } else {
        valid = await verifyPassword(request.body.password, user?.password_hash ?? dummy);
      }
      if (!valid || !user?.active) {
        await client.query('ROLLBACK');
        return reply.code(401).send({ error: 'Usuario o contraseña incorrectos' });
      }
      await client.query('DELETE FROM auth_sessions WHERE expires_at <= now()');
      await client.query(
        "INSERT INTO auth_sessions (token_hash, user_id, expires_at) VALUES ($1, $2, now() + interval '12 hours')",
        [tokenHash(raw), user.id],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    // Windows keeps this token in memory. Browser sessions use an HttpOnly cookie.
    if (!request.body.desktop) reply.setCookie(cookieName, raw, { ...cookieOptions, maxAge: lifetimeSeconds });
    return {
      user: { id: user.id, username: user.username, displayName: user.display_name },
      ...(request.body.desktop ? { token: raw } : {}),
    };
  });

  app.get('/api/auth/me', { onRequest: authenticate }, async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return { user: request.user };
  });

  app.post('/api/auth/logout', async (request, reply) => {
    const raw = token(request);
    if (raw) await pool.query('DELETE FROM auth_sessions WHERE token_hash = $1', [tokenHash(raw)]);
    reply.clearCookie(cookieName, cookieOptions).header('Cache-Control', 'no-store');
    return { ok: true };
  });

  return async (request: FastifyRequest, reply: FastifyReply) => {
    reply.header('Cache-Control', 'no-store');
    if (localDevelopment) {
      request.user = { id: 'desarrollo-local', username: 'desarrollo-local', displayName: 'Desarrollo local' };
      return;
    }
    return authenticate(request, reply);
  };
}
