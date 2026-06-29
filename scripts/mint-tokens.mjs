import { createHmac } from 'node:crypto';

const b64url = (input) => Buffer.from(input).toString('base64url');

function sign(payload, secret) {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  const data = `${header}.${body}`;
  const sig = createHmac('sha256', secret).update(data).digest('base64url');
  return `${data}.${sig}`;
}

export function mintToken({ personId, appRole, secret, exp }) {
  if (!secret) throw new Error('secret required');
  const now = Math.floor(Date.now() / 1000);
  return sign(
    {
      sub: personId,
      role: 'authenticated',
      aud: 'authenticated',
      app_role: appRole,
      iat: now,
      exp: exp ?? now + 60 * 60 * 24 * 14,
    },
    secret,
  );
}

// ---- CLI: node scripts/mint-tokens.mjs ----
const PEOPLE = ['vk', 'ruthu', 'xavi', 'nati', 'vroom', 'peeps', 'deepthy', 'adarshi'];
const ORGANIZER = 'ruthu';

if (import.meta.url === `file://${process.argv[1]}`) {
  const secret = process.env.SUPABASE_JWT_SECRET;
  const base = (process.env.SITE_URL || '').replace(/\/$/, '');
  if (!secret) { console.error('Set SUPABASE_JWT_SECRET'); process.exit(1); }
  if (!base) { console.error('Set SITE_URL'); process.exit(1); }
  const exp = Math.floor(new Date('2026-07-10T00:00:00Z').getTime() / 1000);
  for (const id of PEOPLE) {
    const appRole = id === ORGANIZER ? 'organizer' : 'member';
    const tok = mintToken({ personId: id, appRole, secret, exp });
    console.log(`${id}\t${appRole}\t${base}/?k=${tok}`);
  }
}
