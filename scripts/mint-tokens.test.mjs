import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { mintToken } from './mint-tokens.mjs';

test('mintToken signs an HS256 JWT with the expected claims', () => {
  const secret = 'test-secret';
  const tok = mintToken({ personId: 'ruthu', appRole: 'organizer', secret, exp: 9999999999 });
  const [h, p, s] = tok.split('.');

  // signature verifies against the secret
  const expectedSig = createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url');
  assert.equal(s, expectedSig);

  // header
  const header = JSON.parse(Buffer.from(h, 'base64url').toString());
  assert.deepEqual(header, { alg: 'HS256', typ: 'JWT' });

  // claims
  const payload = JSON.parse(Buffer.from(p, 'base64url').toString());
  assert.equal(payload.sub, 'ruthu');
  assert.equal(payload.role, 'authenticated');
  assert.equal(payload.aud, 'authenticated');
  assert.equal(payload.app_role, 'organizer');
  assert.equal(payload.exp, 9999999999);
  assert.equal(typeof payload.iat, 'number');
});

test('a wrong secret does not verify (tamper check)', () => {
  const tok = mintToken({ personId: 'vk', appRole: 'member', secret: 'real', exp: 9999999999 });
  const [h, p, s] = tok.split('.');
  const wrong = createHmac('sha256', 'wrong').update(`${h}.${p}`).digest('base64url');
  assert.notEqual(s, wrong);
});
