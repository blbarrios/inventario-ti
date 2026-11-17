import Fastify from 'fastify';
import cookie from '@fastify/cookie';
import cors from '@fastify/cors';
import fastifyStatic from '@fastify/static';
import { Pool } from 'pg';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { registerInventoryRoutes } from './inventory.js';
import { configureAuth } from './auth.js';

const root = dirname(fileURLToPath(import.meta.url));
const localDevelopment = process.env.INVENTORY_LOCAL_DEV === 'true';
const host = process.env.HOST ?? (localDevelopment ? '127.0.0.1' : '0.0.0.0');
if (localDevelopment && host !== '127.0.0.1' && host !== '::1') {
  throw new Error('INVENTORY_LOCAL_DEV requiere un host de loopback');
}
const app = Fastify({ logger: true });
const pool = new Pool({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000 });
app.addHook('onClose', async () => pool.end());
await app.register(cookie);
// In local dev the Flutter dev server runs on another origin; allow it.
if (localDevelopment) {
  await app.register(cors, {
    origin: /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/, credentials: true,
  });
}
app.get('/api/health', async (_request, reply) => {
  try { await pool.query('SELECT 1'); return { status: 'ok', database: 'connected' }; }
  catch { return reply.code(503).send({ status: 'unavailable', database: 'disconnected' }); }
});
const requireUser = await configureAuth(app, pool, localDevelopment);
await app.register(async (routes) => registerInventoryRoutes(routes, pool, requireUser), { prefix: '/api' });
const publicRoot = process.env.PUBLIC_DIR
  ? resolve(process.env.PUBLIC_DIR)
  : join(root, '../public');
await app.register(fastifyStatic, { root: publicRoot, prefix: '/', wildcard: false });
app.setNotFoundHandler((request, reply) => {
  if (request.url.startsWith('/api/')) return reply.code(404).send({ error: 'Ruta de API no encontrada' });
  return reply.sendFile('index.html');
});
await app.listen({ host, port: Number(process.env.PORT ?? 3000) });
